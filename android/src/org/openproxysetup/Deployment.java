package org.openproxysetup;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.IntConsumer;

final class Deployment {
    private static final String CLOUDFLARE = "https://api.cloudflare.com/client/v4/accounts/";
    private static final String DNSHE = "https://api005.dnshe.com/index.php?m=domain_hub";
    private final String accountUrl;
    private final String project = "openproxysetup-" + UUID.randomUUID().toString().substring(0, 13).replace("-", "");
    private final byte[] worker;
    private String kvId;
    private boolean kvAttempted;
    private boolean projectAttempted;
    private boolean projectReady;
    private String deploymentId;
    private String uploadMarker;

    Deployment(String account, byte[] worker) {
        if (!account.matches("[a-fA-F0-9]{32}")) {
            throw new IllegalArgumentException("请输入 32 位 Cloudflare Account ID。");
        }
        accountUrl = CLOUDFLARE + account;
        this.worker = worker;
    }

    String pagesHost() {
        return project + ".pages.dev";
    }

    void verify(String token) throws Exception {
        cloudflare("验证 Pages 权限", "/pages/projects?per_page=1", "GET", token, null);
        cloudflare("验证 KV 权限", "/storage/kv/namespaces?per_page=10", "GET", token, null);
    }

    void deploy(String token, String password, IntConsumer progress) throws Exception {
        progress.accept(2);
        if (kvId == null) {
            String title = project + "-KV";
            if (kvAttempted) {
                JSONArray namespaces = cloudflare("查询 KV", "/storage/kv/namespaces?per_page=100&search=" + title,
                        "GET", token, null).getJSONArray("result");
                kvId = find(namespaces, "title", title, "查询 KV").optString("id", null);
            }
            if (kvId == null) {
                kvAttempted = true;
                kvId = cloudflare("创建 KV", "/storage/kv/namespaces", "POST", token, json("title", title))
                        .getJSONObject("result").getString("id");
            }
        }

        progress.accept(3);
        if (projectAttempted && !projectReady) {
            try {
                cloudflare("查询 Pages 项目", path(), "GET", token, null);
                projectReady = true;
            } catch (RequestException error) {
                if (error.status != 404) throw error;
            }
        }
        if (!projectReady) {
            JSONObject config = json(
                    "compatibility_date", LocalDate.now().toString(),
                    "kv_namespaces", json("KV", json("namespace_id", kvId)),
                    "env_vars", json("ADMIN", json("type", "secret_text", "value", password)));
            projectAttempted = true;
            cloudflare("创建 Pages 项目", "/pages/projects", "POST", token,
                    json("name", project, "production_branch", "main",
                            "deployment_configs", json("production", config)));
            projectReady = true;
        }

        if (deploymentId == null && uploadMarker != null) {
            JSONArray recent = cloudflare("查询 Pages 发布记录", path() + "/deployments?per_page=10",
                    "GET", token, null).getJSONArray("result");
            for (int i = 0; i < recent.length(); i++) {
                JSONObject item = recent.getJSONObject(i);
                JSONObject trigger = item.optJSONObject("deployment_trigger");
                JSONObject metadata = trigger == null ? null : trigger.optJSONObject("metadata");
                if (metadata != null && uploadMarker.equals(metadata.optString("commit_message"))) {
                    deploymentId = item.getString("id");
                    break;
                }
            }
        }
        if (deploymentId == null) {
            if (uploadMarker == null) uploadMarker = "Open Proxy Setup Android " + UUID.randomUUID();
            String boundary = "OpenProxySetup" + UUID.randomUUID().toString().replace("-", "");
            ByteArrayOutputStream form = new ByteArrayOutputStream();
            part(form, boundary, "branch", null, "main".getBytes(StandardCharsets.UTF_8));
            part(form, boundary, "manifest", null, "{}".getBytes(StandardCharsets.UTF_8));
            part(form, boundary, "commit_message", null, uploadMarker.getBytes(StandardCharsets.UTF_8));
            part(form, boundary, "_worker.js", "_worker.js", worker);
            form.write(("--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));
            deploymentId = request("上传 Pages", accountUrl + path() + "/deployments", "POST",
                    bearer(token), "multipart/form-data; boundary=" + boundary, form.toByteArray())
                    .getJSONObject("result").getString("id");
        }
        for (int attempt = 0; attempt < 8; attempt++) {
            JSONObject status = cloudflare("检查 Pages 部署", path() + "/deployments/" + deploymentId,
                    "GET", token, null).getJSONObject("result").getJSONObject("latest_stage");
            switch (status.getString("status")) {
                case "success":
                    if (status.getString("name").equals("deploy")) return;
                    break;
                case "failure":
                case "canceled":
                    deploymentId = null;
                    uploadMarker = null;
                    throw new IOException("Pages 部署失败。可在 Cloudflare 控制台查看部署详情后重试。");
                default:
                    break;
            }
            if (attempt < 7) Thread.sleep(2_000);
        }
        throw new IOException("Pages 仍在发布，请稍后点击继续部署检查进度。");
    }

    void bind(String token, String domain, String key, String secret, Runnable bindingStarted) throws Exception {
        Map<String, String> headers = new HashMap<>();
        headers.put("X-API-Key", key);
        headers.put("X-API-Secret", secret);
        String id = "";
        for (int page = 1; page <= 20; page++) {
            JSONArray list = dnshe("查询 DNSHE 域名", "subdomains&action=list&page=" + page + "&per_page=200",
                    "GET", headers, null).getJSONArray("subdomains");
            id = find(list, "full_domain", domain, "查询 DNSHE 域名").optString("id");
            if (!id.isEmpty() || list.length() < 200) break;
        }
        if (!id.matches("[0-9]+")) throw new IOException("DNSHE 中找不到该域名，请检查域名和授权账号。");
        JSONArray records = dnshe("查询 DNSHE 记录", "dns_records&action=list&subdomain_id=" + id,
                "GET", headers, null).getJSONArray("records");
        boolean recordExists = false;
        for (int i = 0; i < records.length(); i++) {
            JSONObject record = records.getJSONObject(i);
            String name = unqualified(record.getString("name"));
            if (!name.equalsIgnoreCase(domain) && !name.equals("@")) continue;
            if (recordExists || !record.getString("type").equals("CNAME")
                    || !unqualified(record.getString("content")).equalsIgnoreCase(pagesHost())) {
                throw new IOException("DNSHE 已有冲突的 DNS 记录。请在 DNSHE 控制台检查后重试。");
            }
            recordExists = true;
        }
        String domains = path() + "/domains";
        JSONArray attached = cloudflare("查询 Pages 自定义域", domains, "GET", token, null).getJSONArray("result");
        bindingStarted.run();
        if (find(attached, "name", domain, "查询 Pages 自定义域").length() == 0) {
            cloudflare("添加 Pages 自定义域", domains, "POST", token, json("name", domain));
        }
        if (!recordExists) {
            dnshe("创建 DNSHE CNAME", "dns_records&action=create", "POST", headers,
                    json("subdomain_id", Long.parseLong(id), "type", "CNAME", "name", "@",
                            "content", pagesHost(), "ttl", 600));
        }
    }

    boolean domainActive(String token, String domain) throws Exception {
        return cloudflare("检查自定义域", path() + "/domains/" + domain, "GET", token, null)
                .getJSONObject("result").optString("status").equals("active");
    }

    private String path() {
        return "/pages/projects/" + project;
    }

    private JSONObject cloudflare(String label, String suffix, String method, String token, JSONObject body) throws Exception {
        return jsonRequest(label, accountUrl + suffix, method, bearer(token), body);
    }

    private JSONObject dnshe(String label, String endpoint, String method, Map<String, String> headers, JSONObject body) throws Exception {
        return jsonRequest(label, DNSHE + "&endpoint=" + endpoint, method, headers, body);
    }

    private static Map<String, String> bearer(String token) {
        return Collections.singletonMap("Authorization", "Bearer " + token);
    }

    private static JSONObject jsonRequest(String label, String url, String method, Map<String, String> headers,
                                          JSONObject body) throws Exception {
        return request(label, url, method, headers, "application/json", body == null ? null :
                body.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static JSONObject request(String label, String url, String method, Map<String, String> headers,
                                      String contentType, byte[] body) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(15_000);
            connection.setReadTimeout(30_000);
            connection.setRequestMethod(method);
            connection.setRequestProperty("Accept", "application/json");
            headers.forEach(connection::setRequestProperty);
            if (body != null) {
                connection.setDoOutput(true);
                connection.setFixedLengthStreamingMode(body.length);
                connection.setRequestProperty("Content-Type", contentType);
                try (OutputStream output = connection.getOutputStream()) {
                    output.write(body);
                }
            }
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) throw new RequestException(label, status);
            try (InputStream input = connection.getInputStream()) {
                JSONObject response = new JSONObject(new String(readBytes(input), StandardCharsets.UTF_8));
                if (!response.optBoolean("success")) throw new RequestException(label, status);
                return response;
            }
        } catch (RequestException error) {
            throw error;
        } catch (Exception error) {
            throw new IOException(label + "失败，请检查网络后重试。", error);
        } finally {
            connection.disconnect();
        }
    }

    static byte[] readBytes(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        for (int count; (count = input.read(buffer)) != -1; ) output.write(buffer, 0, count);
        return output.toByteArray();
    }

    private static JSONObject json(Object... fields) throws Exception {
        JSONObject object = new JSONObject();
        for (int i = 0; i < fields.length; i += 2) object.put((String) fields[i], fields[i + 1]);
        return object;
    }

    private static JSONObject find(JSONArray array, String field, String value, String label) throws Exception {
        JSONObject found = new JSONObject();
        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.getJSONObject(i);
            if (!item.optString(field).equalsIgnoreCase(value)) continue;
            if (found.length() > 0) throw new IOException(label + "返回多个相同结果。请检查账号资源后重试。");
            found = item;
        }
        return found;
    }

    private static String unqualified(String value) {
        return value.replaceFirst("\\.$", "");
    }

    private static void part(ByteArrayOutputStream form, String boundary, String name, String filename,
                             byte[] bytes) throws IOException {
        String header = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + name + "\"";
        if (filename != null) header += "; filename=\"" + filename + "\"\r\nContent-Type: application/javascript";
        form.write((header + "\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        form.write(bytes);
        form.write("\r\n".getBytes(StandardCharsets.UTF_8));
    }

    private static final class RequestException extends IOException {
        final int status;

        RequestException(String label, int status) {
            super(label + "失败（HTTP " + status + "）。请检查账号、授权与服务状态后重试。");
            this.status = status;
        }
    }
}
