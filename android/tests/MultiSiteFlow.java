package org.openproxysetup.sitetest;

import android.app.*;
import android.content.*;
import android.os.*;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.webkit.*;
import android.webkit.CookieManager;
import android.widget.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.lang.reflect.*;
import java.util.*;
import org.json.*;

/** Isolated-emulator regression: cookie-independent login, multiple sites, migration and two modes. */
public final class MultiSiteFlow extends Instrumentation {
    private Activity app;
    private String mode;
    private static String lastUa="";
    private static int posts;
    private static int domainChecks;
    @Override public void onCreate(Bundle args){
        super.onCreate(args);mode=args.getString("mode","prepare");
        URL.setURLStreamHandlerFactory(protocol->!protocol.equals("https")?null:new URLStreamHandler(){
            @Override protected URLConnection openConnection(URL url){return new HttpURLConnection(url){
                ByteArrayOutputStream body=new ByteArrayOutputStream();
                public void connect(){}public void disconnect(){}public boolean usingProxy(){return false;}
                public OutputStream getOutputStream(){return body;}
                boolean good(){return body.toString().equals("password=correct-password");}
                public int getResponseCode(){
                    if(url.getHost().equals("api.github.com"))return 503;
                    if(url.getHost().equals("api.cloudflare.com")) {
                        require("GET".equals(getRequestMethod()),"Automatic validation only queries status");
                        domainChecks++; return 200;
                    }
                    if("POST".equals(getRequestMethod())){
                        if(body.toString().contains("slow-password"))SystemClock.sleep(1200);
                        require("".equals(getRequestProperty("Cookie")),"No old cookie on password POST");
                        require(!getInstanceFollowRedirects(),"No redirects with password");posts++;
                        lastUa=getRequestProperty("User-Agent");return 200;
                    }
                    require("auth=fresh-session".equals(getRequestProperty("Cookie")),"Protected check uses new cookie");
                    require(lastUa.equals(getRequestProperty("User-Agent")),"Consistent user agent");return 200;
                }
                public String getContentType(){return "POST".equals(getRequestMethod())&&!good()?"text/html":"application/json";}
                public InputStream getInputStream(){
                    if(url.getHost().equals("api.cloudflare.com"))return new ByteArrayInputStream("{\"success\":true,\"result\":{\"status\":\"active\"}}".getBytes(StandardCharsets.UTF_8));
                    return new ByteArrayInputStream(("POST".equals(getRequestMethod())?
                    good()?"{\"success\":true}":"<html>Wrong password</html>":"{\"UUID\":\"test-id\"}").getBytes(StandardCharsets.UTF_8));}
                public Map<String,List<String>> getHeaderFields(){
                    Map<String,List<String>> headers=new HashMap<>();if(good())headers.put("Set-Cookie",Arrays.asList("auth=fresh-session; Path=/; Secure; HttpOnly"));return headers;
                }
            };}
        });start();
    }
    static void require(boolean condition,String label){if(!condition)throw new AssertionError(label);}
    Object field(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    Object call(Object target,String name,Class<?>[] types,Object...values)throws Exception{
        Method m=target.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(target,values);
    }
    Class<?> store()throws Exception{return Class.forName("org.openproxysetup.SavedSite",true,getTargetContext().getClassLoader());}
    List<?> sites()throws Exception{Method m=store().getDeclaredMethod("all",Context.class);m.setAccessible(true);return (List<?>)m.invoke(null,getTargetContext());}
    Object site(String host)throws Exception{for(Object s:sites())if(((String)field(s,"url")).contains(host))return s;throw new AssertionError("Missing "+host);}
    View find(View view,String value){
        if(view instanceof TextView&&((TextView)view).getText().toString().equals(value))return view;
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View v=find(((ViewGroup)view).getChildAt(i),value);if(v!=null)return v;}
        return null;
    }
    String textContents(View view){
        StringBuilder value=new StringBuilder();
        if(view instanceof TextView)value.append(((TextView)view).getText()).append('\n');
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)value.append(textContents(((ViewGroup)view).getChildAt(i)));
        return value.toString();
    }
    EditText input(View view,boolean password){
        if(view instanceof EditText&&(((EditText)view).getHint().toString().contains("密码"))==password)return (EditText)view;
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){EditText v=input(((ViewGroup)view).getChildAt(i),password);if(v!=null)return v;}
        return null;
    }
    void tap(String text){runOnMainSync(()->{View v=find(app.getWindow().getDecorView(),text);require(v!=null,"Control "+text);v.performClick();});}
    void enter(String domain,String password){runOnMainSync(()->{input(app.getWindow().getDecorView(),false).setText(domain);input(app.getWindow().getDecorView(),true).setText(password);});}
    void waitDone()throws Exception{
        for(int i=0;i<100;i++){SystemClock.sleep(100);if(!(Boolean)field(app,"siteVerifying")){waitForIdleSync();SystemClock.sleep(250);return;}}
        throw new AssertionError("Verification timeout");
    }
    void picture(String name)throws Exception{
        SystemClock.sleep(700);ByteArrayOutputStream out=new ByteArrayOutputStream();
        getUiAutomation().takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);
        Bundle shot=new Bundle();shot.putString("shot_"+name,android.util.Base64.encodeToString(out.toByteArray(),android.util.Base64.NO_WRAP));sendStatus(2,shot);
    }
    void waitForText(String text) {
        for (int attempt=0;attempt<50;attempt++) {
            AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();
            if(root!=null&&!root.findAccessibilityNodeInfosByText(text).isEmpty())return;
            SystemClock.sleep(100);
        }
        throw new AssertionError("Visible feedback did not appear: "+text);
    }
    void tapDialog(String text) {
        waitForText(text);
        AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();
        for(AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText(text))
            if(text.contentEquals(node.getText())&&node.performAction(AccessibilityNodeInfo.ACTION_CLICK)){waitForIdleSync();return;}
        throw new AssertionError("Missing dialog action: "+text);
    }
    void testNetworkNotice() throws Exception {
        runOnMainSync(()->{try{call(app,"render",new Class[]{int.class},0);}catch(Exception e){throw new RuntimeException(e);}});
        require(!textContents(app.getWindow().getDecorView()).contains("开始前"),"Home no longer has the static notice");
        tap("开始部署  →");waitForText("Cloudflare 和 DNSHE");
        picture("android-network-notice.png");
        tapDialog("暂不部署");
        require((Integer)field(app,"screen")==0,"Cancel remains on home");
        tap("开始部署  →");tapDialog("已准备好，继续");
        require((Integer)field(app,"screen")==1,"Confirmation enters authorization");
    }
    void seedLegacy()throws Exception{
        Method key=store().getDeclaredMethod("key");key.setAccessible(true);
        javax.crypto.Cipher cipher=javax.crypto.Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE,(javax.crypto.SecretKey)key.invoke(null));
        byte[] data=cipher.doFinal("{\"url\":\"https://legacy.test/admin\",\"password\":\"correct-password\"}".getBytes(StandardCharsets.UTF_8));
        getTargetContext().getSharedPreferences("saved_site",0).edit().clear().putString("data",android.util.Base64.encodeToString(data,2))
            .putString("iv",android.util.Base64.encodeToString(cipher.getIV(),2)).commit();
        getTargetContext().getSharedPreferences("MainActivity",0).edit().putBoolean("dark",true).putBoolean("managementMode",true).commit();
    }
    void testDeploymentSite() throws Exception {
        runOnMainSync(() -> {
            try { call(app, "render", new Class[]{int.class}, 1); }
            catch (Exception error) { throw new RuntimeException(error); }
        });
        tap("2"); require((Integer)field(app,"screen") == 2,"Step 2 can be selected");
        tap("3"); require((Integer)field(app,"screen") == 3,"Step 3 can be selected");
        tap("4"); require((Integer)field(app,"screen") == 4,"Step 4 can be selected");
        tap("暂时只发布 Pages"); require((Integer)field(app,"screen") == 1,"Publishing still requires authorization");
        tap("管理");

        Class<?> deploymentClass = Class.forName("org.openproxysetup.Deployment",true,getTargetContext().getClassLoader());
        Constructor<?> ctor = deploymentClass.getDeclaredConstructor(String.class,byte[].class);
        ctor.setAccessible(true);
        Object deployment = ctor.newInstance("0123456789abcdef0123456789abcdef",new byte[0]);
        Method pagesHost = deploymentClass.getDeclaredMethod("pagesHost");
        pagesHost.setAccessible(true);
        String host = (String)pagesHost.invoke(deployment);
        String url = "https://" + host + "/admin";
        runOnMainSync(() -> {
            try {
                for (String[] entry : new String[][]{{"boundDomain","custom.test"},{"deployedPassword","correct-password"}}) {
                    Field target = app.getClass().getDeclaredField(entry[0]);
                    target.setAccessible(true); target.set(app,entry[1]);
                }
                Field target = app.getClass().getDeclaredField("deployment");
                target.setAccessible(true); target.set(app,deployment);
                call(app,"rememberDeploymentSite",new Class[]{String.class,String.class},url,"");
                call(app,"finish",new Class[]{boolean.class,boolean.class,String.class},true,false,"已验证");
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        require(sites().size()==2 && site("custom.test")!=null && site("legacy.test")!=null,"Custom domain replaces only its Pages address");
        require(find(app.getWindow().getDecorView(),"custom.test  →")!=null,"List refreshes after domain becomes active");
        ActivityMonitor monitor = addMonitor("org.openproxysetup.SiteBrowserActivity",null,false);
        runOnMainSync(() -> {
            try { call(app,"openDashboard",new Class[]{String.class},url); }
            catch (Exception error) { throw new RuntimeException(error); }
        });
        Activity browser = monitor.waitForActivityWithTimeout(10000);
        require(browser!=null && sites().size()==2,"Opening the Pages fallback leaves the saved custom domain in place");
        runOnMainSync(browser::finish);
    }
    void testConvenience() throws Exception {
        Class<?> type=app.getClass();
        runOnMainSync(()->{
            try {
                Field language=type.getDeclaredField("docLanguage");language.setAccessible(true);
                for(int i=0;i<4;i++) {
                    language.setInt(app,i);call(app,"render",new Class[]{int.class},7);
                    String docs=textContents(app.getWindow().getDecorView());
                    require(!docs.contains("<div")&&!docs.contains("<img")&&!docs.contains("github-only-")&&!docs.contains("&nbsp;"),"GitHub-only markup excluded from offline docs");
                    require(docs.contains("Windows")&&docs.contains("Android"),"Platform comparison retained in docs");
                }
                call(app,"render",new Class[]{int.class},6);
            }catch(Exception e){throw new RuntimeException(e);}
        });
        for(String input:new String[]{" example.com ","https://example.com/admin/","http://EXAMPLE.com/"}) {
            require("example.com".equals(call(app,"normalizeDomain",new Class[]{String.class},input)),"Domain cleanup");
        }
        for(int i=0;i<100;i++) {
            String password=(String)call(app,"generatePassword",new Class[]{});
            require(password.length()==20&&password.matches(".*[A-Z].*")&&password.matches(".*[a-z].*")&&password.matches(".*[0-9].*"),"Generated password strength");
        }
        runOnMainSync(()->{
            try {call(app,"render",new Class[]{int.class},1);}
            catch(Exception error){throw new RuntimeException(error);}
        });
        require(find(app.getWindow().getDecorView(),"使用 API Token 授权")==null,"Manual token card initially collapsed");
        tap("改用手动 API Token 授权 ▸");
        require(find(app.getWindow().getDecorView(),"使用 API Token 授权")!=null,"Manual token card expands");
        tap("4"); tap("生成强密码");
        require(((String)field(app,"password")).length()==20,"Generator fills the deployment form");
        Method save=store().getDeclaredMethod("save",Context.class,String.class,String.class,String.class,String.class);
        save.setAccessible(true);
        save.invoke(null,getTargetContext(),"https://notes.test/admin","correct-password","","家用站点");
        Method defaultSave=store().getDeclaredMethod("save",Context.class,String.class,String.class);
        defaultSave.setAccessible(true);
        defaultSave.invoke(null,getTargetContext(),"https://notes.test/admin","updated-password");
        require("家用站点".equals(field(site("notes.test"),"note")),"Reverification preserves encrypted note");
        save.invoke(null,getTargetContext(),"https://renamed.test/admin","updated-password","https://notes.test/admin",null);
        require("家用站点".equals(field(site("renamed.test"),"note")),"Domain replacement preserves note");
        runOnMainSync(()->{
            try { call(app,"render",new Class[]{int.class},6); }
            catch(Exception error){throw new RuntimeException(error);}
            View note=find(app.getWindow().getDecorView(),"家用站点");
            require(note!=null,"Saved note is displayed");
            ViewGroup card=(ViewGroup)note.getParent();
            int domainRow=-1;
            for(int i=0;i<card.getChildCount();i++)if(find(card.getChildAt(i),"renamed.test  →")!=null)domainRow=i;
            require(domainRow>=0&&card.indexOfChild(note)>domainRow,"Domain appears above the note");
        });
        runOnMainSync(()->{
            try {
                Class<?> deploymentClass=Class.forName("org.openproxysetup.Deployment",true,getTargetContext().getClassLoader());
                Constructor<?> constructor=deploymentClass.getDeclaredConstructor(String.class,byte[].class);
                constructor.setAccessible(true);
                Object deployment=constructor.newInstance("0123456789abcdef0123456789abcdef",new byte[0]);
                for(Object[] entry:new Object[][]{{"deployment",deployment},{"verifiedToken","fixture-token"},{"boundDomain","auto.test"},
                        {"deployedPassword","correct-password"},{"pagesReady",true},{"resumed",true}}) {
                    Field f=type.getDeclaredField((String)entry[0]); f.setAccessible(true); f.set(app,entry[1]);
                }
                call(app,"finish",new Class[]{boolean.class,boolean.class,String.class},false,true,"等待验证");
                Field after=type.getDeclaredField("domainCheckAfter"); after.setAccessible(true); after.setLong(app,0);
                Field resumed=type.getDeclaredField("resumed"); resumed.setAccessible(true); resumed.setBoolean(app,false);
                call(app,"autoCheckDomain",new Class[]{});
                require(domainChecks==0,"Automatic checks pause in background");
                resumed.setBoolean(app,true);
                call(app,"render",new Class[]{int.class},6);
                call(app,"autoCheckDomain",new Class[]{});
                require(domainChecks==0,"Automatic checks pause away from the progress page");
                call(app,"render",new Class[]{int.class},5);
            } catch(Exception error){throw new RuntimeException(error);}
        });
        for(int i=0;i<100&&!(Boolean)field(app,"domainActive");i++)SystemClock.sleep(100);
        require((Boolean)field(app,"domainActive")&&domainChecks==1,"Foreground automatic query recognizes a verified domain");
        require(site("auto.test")!=null,"Automatic verification saves the custom domain");
        runOnMainSync(()->{
            try {
                for(Object[] entry:new Object[][]{{"failedPhase",3},{"progressMessage","HTTP 503 token=private-fixture password=private-password"}}) {
                    Field f=type.getDeclaredField((String)entry[0]); f.setAccessible(true);f.set(app,entry[1]);
                }
                call(app,"copyDiagnostics",new Class[]{});
                String diagnostic=getTargetContext().getSystemService(android.content.ClipboardManager.class).getPrimaryClip().getItemAt(0).getText().toString();
                require(diagnostic.contains("HTTP 503")&&!diagnostic.contains("private-fixture")&&!diagnostic.contains("private-password"),"Diagnostic copy only includes safe categories");
            } catch(Exception error){throw new RuntimeException(error);}
        });
    }
    @Override public void onStart(){
        Bundle result=new Bundle();
        try{
            if(mode.equals("prepare") || mode.equals("deployment") || mode.equals("convenience") || mode.equals("rename") || mode.equals("network"))seedLegacy();
            app=startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("org.openproxysetup","org.openproxysetup.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            waitForIdleSync();require((Integer)field(app,"screen")==6,"Management mode restored");
            if(mode.equals("network")) {
                testNetworkNotice();
            } else if(mode.equals("convenience")) {
                testConvenience();
            } else if(mode.equals("deployment")) {
                testDeploymentSite();
            } else if(mode.equals("rename")){
                Method save=store().getDeclaredMethod("save",Context.class,String.class,String.class,String.class,String.class);
                save.setAccessible(true);
                String fallback="https://rename-fixture.pages.dev/admin";
                save.invoke(null,getTargetContext(),fallback,"correct-password","","保留备注");
                Object original=site("rename-fixture.pages.dev");
                runOnMainSync(()->{try{call(app,"editSite",new Class[]{original.getClass()},original);}catch(Exception e){throw new RuntimeException(e);}});
                enter("https://CUSTOM.test/admin/","correct-password");tap("验证并保存");waitDone();
                require(find(app.getWindow().getDecorView(),"custom.test  →")!=null,"Edited custom domain is immediately displayed");
                require("保留备注".equals(field(site("custom.test"),"note")),"Edited domain preserves note");
                for(Object s:sites())require(!fallback.equals(field(s,"url")),"Pages entry is replaced");
                save.invoke(null,getTargetContext(),fallback,"correct-password","",null);
                runOnMainSync(()->{try{call(app,"render",new Class[]{int.class},6);}catch(Exception e){throw new RuntimeException(e);}});
                require(find(app.getWindow().getDecorView(),"custom.test  →")!=null,"Opening fallback keeps custom domain");
                for(Object s:sites())require(!fallback.equals(field(s,"url")),"Fallback is not reintroduced");
                picture("android-custom-domain-fixed.png");
            } else if(mode.equals("prepare")){
                require(sites().size()==1,"Legacy single site migrated");
                CookieManager.getInstance().setCookie("https://alpha.test/","auth=old-valid; Path=/; Max-Age=86400; Secure");CookieManager.getInstance().flush();
                tap("＋ 添加站点");enter("alpha.test","wrong-password");
                ActivityMonitor block=addMonitor("org.openproxysetup.SiteBrowserActivity",null,false);
                tap("验证并打开后台");waitDone();
                require(sites().size()==1&&block.getHits()==0,"Wrong password with old valid cookie neither saves nor opens");removeMonitor(block);
                waitForText("密码不正确");
                picture("android-password-error.png");
                enter("alpha.test","slow-password");tap("验证并打开后台");SystemClock.sleep(50);
                runOnMainSync(app::onBackPressed);SystemClock.sleep(1400);
                require((Integer)field(app,"screen")==6&&sites().size()==1,"Cancelled verification never saves or opens");
                tap("＋ 添加站点");
                enter("alpha.test","correct-password");tap("验证并保存");waitDone();require(sites().size()==2,"First new site");
                tap("＋ 添加站点");require(input(app.getWindow().getDecorView(),false).length()==0,"Add starts with empty fields");
                enter("beta.test","correct-password");tap("验证并保存");waitDone();require(sites().size()==3,"Multiple sites");
                require(find(app.getWindow().getDecorView(),"alpha.test  →")!=null&&find(app.getWindow().getDecorView(),"beta.test  →")!=null,"Domain-only list");
                picture("android-site-list.png");
                ActivityMonitor monitor=addMonitor("org.openproxysetup.SiteBrowserActivity",null,false);int before=posts;
                tap("alpha.test  →");Activity browser=monitor.waitForActivityWithTimeout(10000);require(browser!=null&&posts>before,"Saved site freshly reverified before opening");
                require(!browser.getIntent().hasExtra("password"),"Password not injected into browser activity");
                String[] browserUa={null};runOnMainSync(()->{try{browserUa[0]=((WebView)field(browser,"web")).getSettings().getUserAgentString();}catch(Exception e){throw new RuntimeException(e);}});
                require(browserUa[0].equals(lastUa),"Auth user-agent binding");
                runOnMainSync(browser::finish);waitForIdleSync();
                Object alpha=site("alpha.test");runOnMainSync(()->{try{call(app,"editSite",new Class[]{alpha.getClass()},alpha);}catch(Exception e){throw new RuntimeException(e);}});
                enter("alpha.test","wrong-password");tap("验证并保存");waitDone();
                require(field(site("alpha.test"),"password").equals("correct-password"),"Wrong edited password does not overwrite saved password");
                tap("返回站点列表");tap("部署");require(!(Boolean)field(app,"managementMode"),"Deployment page switch");
                tap("管理");require((Boolean)field(app,"managementMode")&&sites().size()==3,"Management switch preserves sites");
                // Let Android complete the normal Activity shutdown before instrumentation ends the process.
                runOnMainSync(app::finish);
                for (int i=0;i<50&&!app.isDestroyed();i++) SystemClock.sleep(100);
                require(app.isDestroyed(),"Activity shut down before persistence test");
            } else {
                require(sites().size()==3,"Multiple sites survive process restart");
                require(field(site("alpha.test"),"password").equals("correct-password"),"Credentials survive restart");
                Object beta=site("beta.test");runOnMainSync(()->{try{call(app,"removeSite",new Class[]{beta.getClass()},beta);}catch(Exception e){throw new RuntimeException(e);}});
                boolean clicked=false;
                for(int i=0;i<60&&!clicked;i++){
                    SystemClock.sleep(100);AccessibilityNodeInfo active=getUiAutomation().getRootInActiveWindow();
                    if(active==null)continue;
                    for(AccessibilityNodeInfo node:active.findAccessibilityNodeInfosByText("移除"))
                        if("移除".contentEquals(node.getText()))clicked=node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                }
                require(clicked,"Remove confirmation");SystemClock.sleep(600);
                require(sites().size()==2&&site("alpha.test")!=null,"Delete only selected site");
                require(CookieManager.getInstance().getCookie("https://alpha.test/").contains("auth=fresh-session"),"Other site login session retained");
            }
            result.putString("result","PASS "+mode);finish(Activity.RESULT_OK,result);
        }catch(Throwable error){result.putString("result",android.util.Log.getStackTraceString(error));finish(Activity.RESULT_CANCELED,result);}
    }
}
