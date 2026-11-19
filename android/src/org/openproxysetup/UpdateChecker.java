package org.openproxysetup;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class UpdateChecker {
    private static final String RELEASES = "https://api.github.com/repos/lomgzhijie/OpenProxySetup/releases?per_page=100";
    private static final String DOWNLOADS = "https://github.com/lomgzhijie/OpenProxySetup/releases/download/";
    private static final Pattern APK_NAME = Pattern.compile("OpenProxySetup-android-v(\\d+\\.\\d+\\.\\d+)\\.apk");
    final String version;
    final String downloadUrl;

    private UpdateChecker(String version, String downloadUrl) {
        this.version = version;
        this.downloadUrl = downloadUrl;
    }

    static UpdateChecker check(String currentVersion) throws Exception {
        HttpURLConnection request = (HttpURLConnection) new URL(RELEASES).openConnection();
        request.setConnectTimeout(12_000);
        request.setReadTimeout(12_000);
        request.setInstanceFollowRedirects(false);
        request.setRequestProperty("User-Agent", "OpenProxySetup-Android");
        request.setRequestProperty("Accept", "application/vnd.github+json");
        try {
            if (request.getResponseCode() != 200) throw new IOException("暂时无法获取新版本，请稍后重试或前往官网。");
            try (InputStream input = request.getInputStream()) {
                return select(new JSONArray(new String(Deployment.readBytes(input), StandardCharsets.UTF_8)), currentVersion);
            }
        } finally {
            request.disconnect();
        }
    }

    static UpdateChecker select(JSONArray releases, String currentVersion) throws Exception {
        UpdateChecker newest = null;
        for (int i = 0; i < releases.length(); i++) {
            JSONObject release = releases.getJSONObject(i);
            if (release.optBoolean("draft", true) || release.optBoolean("prerelease", true)) continue;
            String tag = release.optString("tag_name");
            if (!tag.matches("(?:android-)?v\\d+\\.\\d+\\.\\d+")) continue;
            JSONArray assets = release.optJSONArray("assets");
            if (assets == null) continue;
            for (int j = 0; j < assets.length(); j++) {
                JSONObject asset = assets.getJSONObject(j);
                Matcher name = APK_NAME.matcher(asset.optString("name"));
                if (!name.matches() || !"uploaded".equals(asset.optString("state")) || asset.optLong("size") <= 0) continue;
                String version = name.group(1);
                if (!isNewer(version, currentVersion) || (newest != null && !isNewer(version, newest.version))) continue;
                String download = DOWNLOADS + tag + "/" + name.group();
                if (!download.equals(asset.optString("browser_download_url"))) continue;
                newest = new UpdateChecker(version, download);
            }
        }
        return newest;
    }

    private static boolean isNewer(String next, String current) {
        String[] a = next.split("\\.");
        String[] b = current.split("\\.");
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            long left = i < a.length ? Long.parseLong(a[i]) : 0;
            long right = i < b.length ? Long.parseLong(b[i]) : 0;
            if (left != right) return left > right;
        }
        return false;
    }
}
