package org.openproxysetup.sitetest;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import android.webkit.CookieManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import java.io.*;
import java.lang.reflect.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Run on an isolated emulator. No Cloudflare or DNSHE request is made. */
public final class SiteFlow extends Instrumentation {
    private String mode;
    private Activity app;
    private static final String ADDRESS = "https://ops-qa.test/admin", SECRET = "qa-only-password-123";
    @Override public void onCreate(Bundle args) {
        super.onCreate(args); mode=args.getString("mode","save");
        URL.setURLStreamHandlerFactory(protocol -> !"https".equals(protocol) ? null : new URLStreamHandler(){
            @Override protected URLConnection openConnection(URL url) throws IOException {
                if(!url.getHost().equals("api.github.com")) throw new IOException("Unexpected API request");
                return new HttpURLConnection(url) {
                    public void connect(){} public void disconnect(){} public boolean usingProxy(){return false;}
                    public int getResponseCode(){return 503;}
                    public InputStream getInputStream(){return new ByteArrayInputStream(new byte[0]);}
                };
            }
        }); start();
    }
    private static void require(boolean b,String label){if(!b)throw new AssertionError(label);}
    private Object get(Object target,String name)throws Exception{
        Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);
    }
    private void set(Object target,String name,Object value)throws Exception{
        Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);f.set(target,value);
    }
    private Object call(Object target,String name,Class<?>[] types,Object...args)throws Exception{
        Method m=target.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(target,args);
    }
    private View find(View view,String text){
        if(view instanceof android.widget.TextView && ((android.widget.TextView)view).getText().toString().equals(text))return view;
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){
            View found=find(((ViewGroup)view).getChildAt(i),text);if(found!=null)return found;
        }
        return null;
    }
    private EditText input(View view,boolean secret){
        if(view instanceof EditText && (((EditText)view).getHint().toString().contains("密码"))==secret)return (EditText)view;
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){
            EditText found=input(((ViewGroup)view).getChildAt(i),secret);if(found!=null)return found;
        }return null;
    }
    private String js(WebView web,String script)throws Exception{
        CountDownLatch done=new CountDownLatch(1);String[] value={null};
        runOnMainSync(()->web.evaluateJavascript(script,v->{value[0]=v;done.countDown();}));
        require(done.await(5,TimeUnit.SECONDS),"JavaScript callback");return value[0];
    }
    private void screenshot(String name)throws Exception{
        SystemClock.sleep(400);
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        getUiAutomation().takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);
        Bundle image=new Bundle();
        image.putString("shot_"+name,android.util.Base64.encodeToString(out.toByteArray(),android.util.Base64.NO_WRAP));
        sendStatus(2,image);
    }
    @Override public void onStart(){
        Bundle result=new Bundle();
        try{
            app=startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("org.openproxysetup","org.openproxysetup.MainActivity")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            runOnMainSync(()->{try{set(app,"dark",true);call(app,"render",new Class[]{int.class},6);}catch(Exception e){throw new RuntimeException(e);}});
            waitForIdleSync();
            if(mode.equals("save")){
                runOnMainSync(()->{
                    input(app.getWindow().getDecorView(),false).setText(ADDRESS);
                    input(app.getWindow().getDecorView(),true).setText(SECRET);
                    require(find(app.getWindow().getDecorView(),"保存站点").performClick(),"Save button");
                    CookieManager.getInstance().setCookie("https://ops-qa.test/","ops_qa_session=test-session; Max-Age=86400; Secure; SameSite=Strict");
                    CookieManager.getInstance().flush();
                });
                String data=app.getSharedPreferences("saved_site",0).getString("data","");
                require(!data.isEmpty()&&!data.contains(SECRET)&&!data.contains("ops-qa.test"),"Encrypted preferences");
                screenshot("android-manage.png");
            }else{
                require(ADDRESS.equals(get(app,"manageUrl"))&&SECRET.equals(get(app,"managePassword")),"Restart restores site");
                require(CookieManager.getInstance().getCookie("https://ops-qa.test/").contains("test-session"),"Restart restores cookie");
                runOnMainSync(()->{
                    input(app.getWindow().getDecorView(),false).setText("https://different.test");
                    require(input(app.getWindow().getDecorView(),true).getText().length()==0,"Changed host clears password");
                    input(app.getWindow().getDecorView(),false).setText(ADDRESS);
                    input(app.getWindow().getDecorView(),true).setText(SECRET);
                });
                ActivityMonitor monitor=addMonitor("org.openproxysetup.SiteBrowserActivity",null,false);
                runOnMainSync(()->find(app.getWindow().getDecorView(),"在应用内打开后台").performClick());
                Activity browser=monitor.waitForActivityWithTimeout(10000);require(browser!=null,"Embedded activity");
                WebView web=(WebView)get(browser,"web");
                Method same=browser.getClass().getDeclaredMethod("sameOrigin",String.class,String.class);same.setAccessible(true);
                require((Boolean)same.invoke(null,"https://OPS-QA.test:443/admin","https://ops-qa.test"),"Same HTTPS origin");
                for(String bad:new String[]{"http://ops-qa.test","https://ops-qa.test:444","https://user@ops-qa.test","https://ops-qa.test.evil.test"})
                    require(!(Boolean)same.invoke(null,bad,"https://ops-qa.test"),"Reject unsafe origin");
                String login="<html><body><main class='container' style='margin:16px;padding:24px'><h1>Open Proxy Setup</h1><h2>站点后台</h2><form id='loginForm'><p>后台密码</p><input id='password' type='password'><p><button type='submit'>登录</button></p></form></main></body></html>";
                ByteArrayOutputStream output=new ByteArrayOutputStream();
                try(InputStream in=getContext().getAssets().open("admin.html")){byte[] b=new byte[4096];int n;while((n=in.read(b))>0)output.write(b,0,n);}
                byte[] admin=output.toByteArray();
                runOnMainSync(()->{
                    web.stopLoading();WebViewClient original=web.getWebViewClient();
                    web.setWebViewClient(new WebViewClient(){
                        @Override public WebResourceResponse shouldInterceptRequest(WebView v,WebResourceRequest r){
                            byte[] body=r.getUrl().getHost().equals("ops-qa.test")?
                                (r.getUrl().getPath().equals("/login")?login.getBytes(StandardCharsets.UTF_8):admin):new byte[0];
                            return new WebResourceResponse("text/html","UTF-8",new ByteArrayInputStream(body));
                        }
                        @Override public void onPageFinished(WebView v,String u){original.onPageFinished(v,u);}
                        @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){return original.shouldOverrideUrlLoading(v,r);}
                    });
                    web.loadUrl("https://ops-qa.test/login");
                });
                String filled="";
                for(int i=0;i<50;i++){SystemClock.sleep(150);filled=js(web,"document.querySelector('#password')?.value==='qa-only-password-123'");if("true".equals(filled))break;}
                require("true".equals(filled),"Password filled at selected login");
                require("\"dark\"".equals(js(web,"document.documentElement.dataset.opsTheme")),"Dark theme");
                js(web,"location.href='https://other-qa.test/login';true");SystemClock.sleep(300);
                require("\"ops-qa.test\"".equals(js(web,"location.hostname")),"Cross-origin navigation blocked");
                runOnMainSync(()->web.loadUrl(ADDRESS));
                String ready="";
                for(int i=0;i<100;i++){
                    SystemClock.sleep(150);
                    ready=js(web,"location.pathname==='/admin'&&!!document.querySelector('.module')");
                    if("true".equals(ready))break;
                }
                require("true".equals(ready),"Admin page rendered");
                SystemClock.sleep(2500);
                screenshot("android-backend-dark.png");
                runOnMainSync(()->find(browser.getWindow().getDecorView(),"☀ / ☾").performClick());SystemClock.sleep(500);
                require("\"light\"".equals(js(web,"document.documentElement.dataset.opsTheme")),"Light theme");
                screenshot("android-backend-light.png");
                runOnMainSync(browser::finish);waitForIdleSync();
                runOnMainSync(()->find(app.getWindow().getDecorView(),"清除本机站点与登录会话").performClick());
                SystemClock.sleep(300);
                AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();boolean clicked=false;
                for(AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText("清除"))
                    if("清除".contentEquals(node.getText()))clicked=node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                require(clicked,"Clear confirmation button");SystemClock.sleep(700);
                require(!app.getSharedPreferences("saved_site",0).contains("data"),"Saved site removed");
                require(CookieManager.getInstance().getCookie("https://ops-qa.test/")==null,"Login session removed");
            }
            result.putString("result","PASS "+mode);finish(Activity.RESULT_OK,result);
        }catch(Throwable error){result.putString("result",android.util.Log.getStackTraceString(error));finish(Activity.RESULT_CANCELED,result);}
    }
}
