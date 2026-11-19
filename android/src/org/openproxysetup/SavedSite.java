package org.openproxysetup;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONObject;
import org.json.JSONArray;
import java.util.ArrayList;
import java.util.List;

/** Device-local credentials. Keys never leave Android Keystore; backup is disabled. */
final class SavedSite {
    private static final String ALIAS = "ops.saved-site.v1";
    private static SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(ALIAS)) return (SecretKey) store.getKey(ALIAS, null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
    static final class Site {
        final String url,password;
        Site(String url,String password){this.url=url;this.password=password;}
    }
    static List<Site> all(Context context)throws Exception {
        JSONObject data=read(context);List<Site> sites=new ArrayList<>();
        if(data==null)return sites;
        JSONArray rows=data.optJSONArray("sites");
        if(rows==null)rows=new JSONArray().put(data); // v1 single-site migration, encrypted format unchanged.
        for(int i=0;i<rows.length();i++){
            JSONObject row=rows.getJSONObject(i);String url=SiteAuth.adminUrl(row.optString("url"));
            if(url!=null&&sites.stream().noneMatch(s->s.url.equals(url)))sites.add(new Site(url,row.optString("password")));
        }
        return sites;
    }
    static void save(Context context,String url,String password)throws Exception {save(context,url,password,"");}
    static void save(Context context,String url,String password,String previousUrl)throws Exception {
        List<Site> sites=all(context);sites.removeIf(s->s.url.equals(url)||s.url.equals(previousUrl));
        sites.add(0,new Site(url,password));write(context,sites);
    }
    static void remove(Context context,String url)throws Exception {
        List<Site> sites=all(context);sites.removeIf(s->s.url.equals(url));write(context,sites);
    }
    private static void write(Context context,List<Site> sites)throws Exception {
        JSONArray rows=new JSONArray();
        for(Site site:sites)rows.put(new JSONObject().put("url",site.url).put("password",site.password));
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] plain = new JSONObject().put("version",2).put("sites",rows).toString().getBytes(StandardCharsets.UTF_8);
        byte[] encrypted;
        try { encrypted = cipher.doFinal(plain); } finally { java.util.Arrays.fill(plain, (byte)0); }
        boolean saved = context.getSharedPreferences("saved_site", Context.MODE_PRIVATE).edit()
                .putString("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .putString("data", Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit();
        if (!saved) throw new java.io.IOException("Unable to save site");
    }
    static JSONObject read(Context context) throws Exception {
        android.content.SharedPreferences prefs = context.getSharedPreferences("saved_site", Context.MODE_PRIVATE);
        String data = prefs.getString("data", null);
        if (data == null) return null;
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)));
        byte[] plain = cipher.doFinal(Base64.decode(data, Base64.NO_WRAP));
        try { return new JSONObject(new String(plain, StandardCharsets.UTF_8)); }
        finally { java.util.Arrays.fill(plain, (byte)0); }
    }
    static void clear(Context context) throws Exception {
        if (!context.getSharedPreferences("saved_site", Context.MODE_PRIVATE).edit().clear().commit())
            throw new java.io.IOException("Unable to clear site");
    }
}
