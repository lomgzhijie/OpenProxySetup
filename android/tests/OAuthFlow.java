package org.openproxysetup.oauthtest;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Method;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLConnection;
import java.net.URLStreamHandler;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;

public final class OAuthFlow extends Instrumentation {
    private static final String CALLBACK = "https://openproxysetup.ccwu.cc/oauth/android/callback.html";
    private static final String ACCOUNT = "00000000000000000000000000000001";
    private final AtomicInteger exchanges = new AtomicInteger();
    private final AtomicInteger refreshes = new AtomicInteger();
    private final AtomicInteger verification = new AtomicInteger();
    private volatile String expectedChallenge;
    private Activity main;

    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        URL.setURLStreamHandlerFactory(protocol -> !"https".equals(protocol) ? null : new URLStreamHandler() {
            @Override protected URLConnection openConnection(URL url) { return fake(url); }
        });
        start();
    }

    @Override public void onStart() {
        Bundle outcome = new Bundle();
        try {
            main = startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("org.openproxysetup", "org.openproxysetup.MainActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            java.lang.reflect.Field field = main.getClass().getDeclaredField("cloudflareOAuth");
            field.setAccessible(true);
            Object flow = field.get(main);
            Method start = flow.getClass().getDeclaredMethod("start");
            start.setAccessible(true);
            Method challenge = flow.getClass().getDeclaredMethod("challenge", String.class);
            challenge.setAccessible(true);
            require("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM".equals(challenge.invoke(null,
                    "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")), "RFC 7636 test vector");

            Uri request = (Uri) start.invoke(flow);
            require("dash.cloudflare.com".equals(request.getHost()) && CALLBACK.equals(request.getQueryParameter("redirect_uri")), "authorization destination");
            require("account-settings.read page.write workers-kv-storage.write offline_access".equals(request.getQueryParameter("scope")), "least-privilege scopes");
            String state = request.getQueryParameter("state");
            dispatch("unrelated-state", "code", "unexpected");
            require(exchanges.get() == 0, "invalid state is rejected");
            dispatch(state, "error", "access_denied");
            dispatch(state, "code", "unexpected");
            require(exchanges.get() == 0, "denied callback consumed the pending authorization");

            request = (Uri) start.invoke(flow);
            expectedChallenge = request.getQueryParameter("code_challenge");
            require(!state.equals(request.getQueryParameter("state")), "new state for a new attempt");
            state = request.getQueryParameter("state");
            dispatch(state, "code", "fixture-code+with+plus");
            waitForVerification();
            require(exchanges.get() == 1 && refreshes.get() == 1, "one code exchange and one refresh");
            require(verification.get() == 2, "authorized account passed Pages and KV validation");
            dispatch(state, "code", "fixture-code+with+plus");
            require(exchanges.get() == 1, "successful callback is also single use");
            outcome.putString("result", "PASS PKCE, failed/cancelled/replayed callbacks, refresh, and verified deployment account selection");
            finish(Activity.RESULT_OK, outcome);
        } catch (Throwable error) {
            outcome.putString("result", android.util.Log.getStackTraceString(error));
            finish(Activity.RESULT_CANCELED, outcome);
        }
    }

    private void dispatch(String state, String name, String value) {
        Uri uri = Uri.parse(CALLBACK).buildUpon().appendQueryParameter("state", state).appendQueryParameter(name, value).build();
        Intent intent = new Intent(Intent.ACTION_VIEW, uri).setClassName("org.openproxysetup", "org.openproxysetup.OAuthCallbackActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        main.startActivity(intent);
        waitForIdleSync();
        SystemClock.sleep(200L);
    }

    private void waitForVerification() throws Exception {
        java.lang.reflect.Field screen = main.getClass().getDeclaredField("screen");
        screen.setAccessible(true);
        for (int i = 0; i < 60; i++) {
            waitForIdleSync();
            if (screen.getInt(main) == 2 && verification.get() == 2) return;
            SystemClock.sleep(100L);
        }
        throw new AssertionError("OAuth authorization did not advance to the domain step");
    }

    private HttpURLConnection fake(URL url) {
        return new HttpURLConnection(url) {
            private final ByteArrayOutputStream payload = new ByteArrayOutputStream();
            @Override public void connect() {}
            @Override public void disconnect() {}
            @Override public boolean usingProxy() { return false; }
            @Override public OutputStream getOutputStream() { return payload; }
            @Override public int getResponseCode() { return "api.github.com".equals(url.getHost()) ? 503 : 200; }
            @Override public InputStream getInputStream() {
                String result;
                if ("dash.cloudflare.com".equals(url.getHost()) && "/oauth2/token".equals(url.getPath())) {
                    Uri form = Uri.parse("https://localhost/?" + new String(payload.toByteArray(), StandardCharsets.UTF_8));
                    require("POST".equals(getRequestMethod()) && !getInstanceFollowRedirects(), "fixed token destination");
                    require("fixture-client-id".equals(form.getQueryParameter("client_id")), "registered client used");
                    require(form.getQueryParameter("client_secret") == null, "no embedded secret");
                    if ("authorization_code".equals(form.getQueryParameter("grant_type"))) {
                        exchanges.incrementAndGet();
                        require("fixture-code+with+plus".equals(form.getQueryParameter("code")), "form percent encoding");
                        require(CALLBACK.equals(form.getQueryParameter("redirect_uri")), "matching redirect");
                        verifyChallenge(form.getQueryParameter("code_verifier"));
                        result = "{\"token_type\":\"Bearer\",\"access_token\":\"short-token\",\"expires_in\":30,\"refresh_token\":\"fixture-refresh\"}";
                    } else {
                        refreshes.incrementAndGet();
                        require("refresh_token".equals(form.getQueryParameter("grant_type")), "refresh grant");
                        require("fixture-refresh".equals(form.getQueryParameter("refresh_token")), "refresh token used");
                        result = "{\"token_type\":\"Bearer\",\"access_token\":\"fresh-token\",\"expires_in\":900}";
                    }
                } else if ("api.cloudflare.com".equals(url.getHost())) {
                    require("Bearer fresh-token".equals(getRequestProperty("Authorization")), "refreshed credential used");
                    if (url.getPath().equals("/client/v4/accounts")) {
                        result = "{\"success\":true,\"result\":[{\"id\":\"" + ACCOUNT + "\",\"name\":\"Fixture account\"}]}";
                    } else {
                        require(url.getPath().startsWith("/client/v4/accounts/" + ACCOUNT + "/"), "only selected account verified");
                        verification.incrementAndGet();
                        result = "{\"success\":true,\"result\":[]}";
                    }
                } else throw new AssertionError("Unexpected service in OAuth QA");
                return new ByteArrayInputStream(result.getBytes(StandardCharsets.UTF_8));
            }
        };
    }

    private void verifyChallenge(String verifier) {
        try {
            byte[] digest = java.security.MessageDigest.getInstance("SHA-256").digest(verifier.getBytes(StandardCharsets.US_ASCII));
            require(expectedChallenge.equals(java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(digest)), "PKCE verifier bound to browser request");
        } catch (java.security.NoSuchAlgorithmException error) { throw new AssertionError(error); }
    }

    private static void require(boolean condition, String details) {
        if (!condition) throw new AssertionError(details);
    }
}
