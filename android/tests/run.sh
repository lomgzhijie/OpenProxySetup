#!/usr/bin/env bash
set -euo pipefail

app_apk=$1
test_key=$2
work=$3
sdk_tools="$ANDROID_HOME/build-tools/$ANDROID_SDK_BUILD_TOOLS_VERSION"
android_jar="$ANDROID_HOME/platforms/android-35/android.jar"
jdk_bin="$JAVA_HOME_17_X64/bin"
export JAVA_HOME="$JAVA_HOME_17_X64"

adb install -r "$app_apk"

install_test() {
    local package=$1 class=$2
    local dir="$work/$class"
    mkdir -p "$dir/classes" "$dir/dex"
    cat >"$dir/AndroidManifest.xml" <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$package">
    <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="30" />
    <application />
    <instrumentation android:name=".$class" android:targetPackage="org.openproxysetup" />
</manifest>
EOF
    "$jdk_bin/javac" --release 8 -encoding UTF-8 -cp "$android_jar" -d "$dir/classes" "android/tests/$class.java"
    "$jdk_bin/jar" cf "$dir/classes.jar" -C "$dir/classes" .
    "$sdk_tools/d8" --lib "$android_jar" --min-api 26 --output "$dir/dex" "$dir/classes.jar"
    "$sdk_tools/aapt2" link -I "$android_jar" --manifest "$dir/AndroidManifest.xml" -o "$dir/unsigned.apk"
    "$jdk_bin/jar" uf "$dir/unsigned.apk" -C "$dir/dex" classes.dex
    "$sdk_tools/zipalign" -f 4 "$dir/unsigned.apk" "$dir/aligned.apk"
    "$sdk_tools/apksigner" sign --ks "$test_key" --ks-pass pass:android --ks-key-alias ops-test \
        --out "$dir/test.apk" "$dir/aligned.apk"
    adb install -r "$dir/test.apk"
}

run_test() {
    local expected=$1
    shift
    local output
    output=$(adb shell am instrument -w "$@" | tr -d '\r')
    printf '%s\n' "$output" | sed '/^INSTRUMENTATION_STATUS: shot_/d'
    [[ "$output" == *"INSTRUMENTATION_RESULT: result=PASS $expected"* ]]
}

install_test org.openproxysetup.oauthtest OAuthFlow
run_test PKCE org.openproxysetup.oauthtest/.OAuthFlow

install_test org.openproxysetup.sitetest MultiSiteFlow
for mode in deployment prepare persist; do
    run_test "$mode" -e mode "$mode" org.openproxysetup.sitetest/.MultiSiteFlow
done
