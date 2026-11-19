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
    static void save(Context context, String url, String password) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] plain = new JSONObject().put("url", url).put("password", password).toString().getBytes(StandardCharsets.UTF_8);
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
