package org.openproxysetup;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

public final class OAuthCallbackActivity extends Activity {
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Uri callback = getIntent().getData();
        if (Intent.ACTION_VIEW.equals(getIntent().getAction()) && new CloudflareOAuth(this).matchesPending(callback)) {
            startActivity(new Intent(this, MainActivity.class).setAction(Intent.ACTION_VIEW).setData(callback)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP));
        }
        finish();
    }
}
