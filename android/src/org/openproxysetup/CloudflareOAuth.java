package org.openproxysetup;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.SystemClock;

import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.List;

final class CloudflareOAuth {
    static final String REDIRECT = "https://openproxysetup.ccwu.cc/oauth/android/callback.html";
    private static final Uri CALLBACK = Uri.parse(REDIRECT);
    private static final String AUTHORIZE = "https://dash.cloudflare.com/oauth2/auth";
    private static final String TOKEN = "https://dash.cloudflare.com/oauth2/token";
    private static final String SCOPES = "account-settings.read page.write workers-kv-storage.write offline_access";
    private static final long CALLBACK_TIMEOUT_MS = 10 * 60_000L;
    private static final SecureRandom RANDOM = new SecureRandom();

    private final SharedPreferences pending;
    private final String clientId;

    CloudflareOAuth(Context context) {
        pending = context.getSharedPreferences("cloudflare_oauth_pending", Context.MODE_PRIVATE);
        clientId = context.getString(R.string.cloudflare_oauth_client_id);
    }

    boolean configured() { return !clientId.isEmpty(); }

    Uri start() throws IOException {
        if (!configured()) throw new IOException("浏览器授权尚未配置，请使用 API Token。");
        String state = randomValue();
        String verifier = randomValue();
        if (!pending.edit().putString("state", state).putString("verifier", verifier)
                .putLong("started", System.currentTimeMillis()).commit()) {
            throw new IOException("无法保存本次授权，请检查设备存储后重试。");
        }
        return Uri.parse(AUTHORIZE).buildUpon()
                .appendQueryParameter("client_id", clientId)
                .appendQueryParameter("response_type", "code")
                .appendQueryParameter("redirect_uri", REDIRECT)
                .appendQueryParameter("scope", SCOPES)
                .appendQueryParameter("state", state)
                .appendQueryParameter("code_challenge", challenge(verifier))
                .appendQueryParameter("code_challenge_method", "S256")
                .build();
    }

    void cancel() { pending.edit().clear().apply(); }

    static boolean isCallback(Uri link) {
        return link != null && "https".equals(link.getScheme())
                && CALLBACK.getEncodedAuthority().equals(link.getEncodedAuthority())
                && CALLBACK.getEncodedPath().equals(link.getEncodedPath()) && link.getFragment() == null;
    }

    boolean matchesPending(Uri link) {
        if (!configured() || !isCallback(link)) return false;
        String expected = pending.getString("state", "");
        List<String> states = link.getQueryParameters("state");
        return !expected.isEmpty() && states.size() == 1 && MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8), states.get(0).getBytes(StandardCharsets.UTF_8));
    }

    Exchange accept(Uri link) throws IOException {
        if (!matchesPending(link)) {
            throw new IOException("此链接与本次授权不匹配，请重新在应用内发起授权。");
        }
        String verifier = pending.getString("verifier", "");
        long age = System.currentTimeMillis() - pending.getLong("started", 0);
        // Consume a matched callback before issuing a token request. Replays cannot exchange the code again.
        if (!pending.edit().clear().commit()) throw new IOException("无法完成授权，请重试。");
        if (verifier.isEmpty() || age < 0 || age > CALLBACK_TIMEOUT_MS) {
            throw new IOException("授权链接已过期，请重新授权。");
        }
        if (link.getQueryParameter("error") != null) throw new IOException("Cloudflare 授权未完成，请重新授权。");
        List<String> codes = link.getQueryParameters("code");
        if (codes.size() != 1 || codes.get(0).isEmpty() || codes.get(0).length() > 4096) {
            throw new IOException("Cloudflare 没有返回有效的授权码，请重试。");
        }
        return new Exchange(codes.get(0), verifier);
    }

    final class Exchange {
        private final String code, verifier;

        private Exchange(String code, String verifier) { this.code = code; this.verifier = verifier; }

        Session exchange() throws IOException {
            JSONObject response = requestToken(new Uri.Builder()
                    .appendQueryParameter("grant_type", "authorization_code")
                    .appendQueryParameter("client_id", clientId)
                    .appendQueryParameter("code", code)
                    .appendQueryParameter("redirect_uri", REDIRECT)
                    .appendQueryParameter("code_verifier", verifier));
            Session session = new Session();
            session.apply(response);
            return session;
        }
    }

    final class Session {
        private String access = "", refresh = "";
        private long expiresAt;

        private void apply(JSONObject response) throws IOException {
            String issuedAccess = response.optString("access_token", "");
            long seconds = response.optLong("expires_in", 0);
            if (issuedAccess.isEmpty() || seconds <= 0
                    || !"Bearer".equalsIgnoreCase(response.optString("token_type"))) {
                throw new IOException("Cloudflare 返回的登录信息不完整，请重新授权。");
            }
            access = issuedAccess;
            refresh = response.optString("refresh_token", refresh);
            expiresAt = SystemClock.elapsedRealtime() + Math.min(seconds, 86_400L) * 1000L;
        }

        synchronized String accessToken() throws IOException {
            long remaining = expiresAt - SystemClock.elapsedRealtime();
            if (remaining > 60_000L || (remaining > 0 && refresh.isEmpty())) return access;
            if (refresh.isEmpty()) throw new IOException("Cloudflare 授权已过期，请重新授权。");
            apply(requestToken(new Uri.Builder()
                    .appendQueryParameter("grant_type", "refresh_token")
                    .appendQueryParameter("client_id", clientId)
                    .appendQueryParameter("refresh_token", refresh)));
            return access;
        }
    }

    private static JSONObject requestToken(Uri.Builder form) throws IOException {
        // Android URI percent encoding is valid for form encoding, including spaces and literal plus signs.
        byte[] body = form.build().getEncodedQuery().getBytes(StandardCharsets.UTF_8);
        HttpURLConnection connection = (HttpURLConnection) new URL(TOKEN).openConnection();
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(15_000);
            connection.setReadTimeout(20_000);
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
            connection.setRequestProperty("Accept", "application/json");
            connection.setDoOutput(true);
            connection.setFixedLengthStreamingMode(body.length);
            try (OutputStream out = connection.getOutputStream()) { out.write(body); }
            int status = connection.getResponseCode();
            if (status == 400 || status == 401 || status == 403) {
                throw new IOException("Cloudflare 拒绝了授权请求（HTTP " + status + "）。请重新授权或使用 API Token。");
            }
            if (status != 200) throw new IOException("Cloudflare 授权服务暂不可用（HTTP " + status + "）。");
            try (InputStream input = connection.getInputStream()) {
                return new JSONObject(new String(Deployment.readBytes(input), StandardCharsets.UTF_8));
            } catch (org.json.JSONException error) {
                throw new IOException("Cloudflare 返回的授权结果无效，请重新授权。");
            }
        } finally {
            connection.disconnect();
            java.util.Arrays.fill(body, (byte) 0);
        }
    }

    private static String randomValue() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    static String challenge(String verifier) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(verifier.getBytes(StandardCharsets.US_ASCII));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException(error);
        }
    }
}
