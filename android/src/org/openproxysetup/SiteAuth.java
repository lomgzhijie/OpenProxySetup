package org.openproxysetup;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Password verification always starts without browser cookies and never follows redirects. */
final class SiteAuth {
    static String adminUrl(String value) {
        try {
            String input=value.trim();
            URI uri=new URI(input.contains("://")?input:"https://"+input);
            if(!"https".equalsIgnoreCase(uri.getScheme())||uri.getHost()==null||uri.getUserInfo()!=null) return null;
            return new URI("https",null,uri.getHost().toLowerCase(java.util.Locale.ROOT),
                    uri.getPort()==443?-1:uri.getPort(),"/admin",null,null).toASCIIString();
        }catch(Exception e){return null;}
    }
    static String domain(String url) {
        URI uri=URI.create(url);return uri.getHost()+(uri.getPort()==-1?"":":"+uri.getPort());
    }
    static String origin(String url) {return url.substring(0,url.length()-"/admin".length());}
    static String verify(String url,String password,String userAgent)throws IOException {
        if(!url.equals(adminUrl(url))||password.isEmpty())throw new IOException("请输入站点网址和后台密码。");
        HttpURLConnection login=connection(origin(url)+"/login",userAgent);
        try {
            login.setRequestMethod("POST");login.setDoOutput(true);
            login.setRequestProperty("Content-Type","application/x-www-form-urlencoded; charset=UTF-8");
            // Explicitly empty: a persisted auth cookie must never validate a wrong password.
            login.setRequestProperty("Cookie","");
            byte[] body=("password="+URLEncoder.encode(password,"UTF-8")).getBytes(StandardCharsets.UTF_8);
            login.setFixedLengthStreamingMode(body.length);
            try(OutputStream output=login.getOutputStream()){output.write(body);}
            finally{java.util.Arrays.fill(body,(byte)0);}
            int code=login.getResponseCode();
            if(code==401||code==403)throw new IOException("密码不正确，或站点限制了登录访问。请检查后重试。");
            if(code!=200)throw new IOException(code>=300&&code<400?"站点登录发生重定向，请检查网址。":"站点暂时无法验证，请稍后重试。");
            if(!jsonType(login))throw new IOException("密码不正确，请重新输入。");
            try {
                if(!new JSONObject(read(login)).optBoolean("success",false))throw new IOException("密码不正确，请重新输入。");
            }catch(org.json.JSONException e){throw new IOException("站点返回了无效的登录结果。");}
            String cookie="";
            for(java.util.Map.Entry<String,java.util.List<String>> header:login.getHeaderFields().entrySet()){
                if(header.getKey()!=null&&header.getKey().equalsIgnoreCase("Set-Cookie"))
                    for(String line:header.getValue())if(line.startsWith("auth="))cookie=line.split(";",2)[0];
            }
            if(cookie.length()<=5||cookie.contains("\r")||cookie.contains("\n"))throw new IOException("站点未返回有效的登录凭据。");
            HttpURLConnection check=connection(origin(url)+"/admin/config.json",userAgent);
            try {
                check.setRequestProperty("Cookie",cookie);
                if(check.getResponseCode()!=200||!jsonType(check))throw new IOException("后台登录验证未通过，请检查密码。");
                try {if(new JSONObject(read(check)).optString("UUID","").isEmpty())throw new IOException("站点不是受支持的管理后台。");}
                catch(org.json.JSONException e){throw new IOException("站点返回了无效的后台数据。");}
            }finally{check.disconnect();}
            return cookie;
        }catch(java.net.SocketTimeoutException e){throw new IOException("验证超时，请检查网络后重试。");}
        catch(javax.net.ssl.SSLException e){throw new IOException("HTTPS 连接验证失败，请检查站点证书。");}
        finally{login.disconnect();}
    }
    private static HttpURLConnection connection(String url,String ua)throws IOException {
        HttpURLConnection request=(HttpURLConnection)new URL(url).openConnection();
        request.setInstanceFollowRedirects(false);request.setConnectTimeout(15000);request.setReadTimeout(15000);
        request.setRequestProperty("User-Agent",ua);request.setRequestProperty("Accept","application/json");
        request.setRequestProperty("Cache-Control","no-store");return request;
    }
    private static boolean jsonType(HttpURLConnection c){String type=c.getContentType();return type!=null&&type.toLowerCase(java.util.Locale.ROOT).startsWith("application/json");}
    private static String read(HttpURLConnection c)throws IOException {
        try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){
            byte[] buffer=new byte[4096];int n;
            while((n=in.read(buffer))!=-1){if(out.size()+n>2*1024*1024)throw new IOException("站点返回的数据过大。");out.write(buffer,0,n);}
            return new String(out.toByteArray(),StandardCharsets.UTF_8);
        }
    }
}
