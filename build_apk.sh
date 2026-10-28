#!/bin/bash
set -e

# Autodetect JAVA_HOME
if [ -z "$JAVA_HOME" ]; then
    for path in "/home/lastsuns1ne/.gradle/jdks/jetbrains_s_r_o_-21-amd64-linux.2" \
                "/usr/lib/jvm/java-21-openjdk" \
                "/usr/lib/jvm/java-17-openjdk" \
                "/usr/lib/jvm/java-17-openjdk-amd64" \
                "/opt/homebrew/opt/openjdk@17" \
                "/usr/lib/jvm/default" \
                "$HOME/.gradle/jdks"/*; do
        if [ -d "$path" ] && [ -x "$path/bin/javac" ]; then
            export JAVA_HOME="$path"
            break
        fi
    done
fi

if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
    export PATH="$JAVA_HOME/bin:$PATH"
    echo "[*] Using JAVA_HOME: $JAVA_HOME"
else
    echo "[!] Warning: No dedicated javac found, using system PATH."
fi

# Autodetect ANDROID_HOME / Android SDK
if [ -z "$ANDROID_HOME" ]; then
    for sdk_path in "$HOME/Android/Sdk" \
                    "/home/lastsuns1ne/Android/Sdk" \
                    "$HOME/android-sdk" \
                    "$HOME/Library/Android/sdk"; do
        if [ -d "$sdk_path" ]; then
            export ANDROID_HOME="$sdk_path"
            break
        fi
    done
fi

if [ -z "$ANDROID_HOME" ] || [ ! -d "$ANDROID_HOME" ]; then
    echo "[!] Error: Android SDK not found! Please set ANDROID_HOME."
    exit 1
fi
echo "[*] Using ANDROID_HOME: $ANDROID_HOME"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
OUT_APK="$PROJECT_DIR/AnyGSI.apk"

# Find latest build-tools
SDK_TOOLS=$(ls -d "$ANDROID_HOME/build-tools/"* 2>/dev/null | sort -V | tail -n 1)
if [ -z "$SDK_TOOLS" ] || [ ! -x "$SDK_TOOLS/aapt2" ]; then
    echo "[!] Error: No build-tools with aapt2 found in $ANDROID_HOME/build-tools/"
    exit 1
fi
echo "[*] Using build-tools: $SDK_TOOLS"

# Find platform jar (prefer android-36 / android-37)
PLATFORM_JAR=""
for p in "$ANDROID_HOME/platforms/android-36/android.jar" \
         "$ANDROID_HOME/platforms/android-37.0/android.jar" \
         "$ANDROID_HOME/platforms/android-37/android.jar" \
         "$ANDROID_HOME/platforms/android-35/android.jar" \
         "$ANDROID_HOME/platforms/android-34/android.jar"; do
    if [ -f "$p" ]; then
        PLATFORM_JAR="$p"
        break
    fi
done

if [ -z "$PLATFORM_JAR" ]; then
    PLATFORM_JAR=$(ls "$ANDROID_HOME/platforms/"*/android.jar 2>/dev/null | sort -V | tail -n 1)
fi

if [ -z "$PLATFORM_JAR" ] || [ ! -f "$PLATFORM_JAR" ]; then
    echo "[!] Error: No android.jar platform found in $ANDROID_HOME/platforms/"
    exit 1
fi
echo "[*] Using PLATFORM_JAR: $PLATFORM_JAR"

echo "=== 1. Cleaning & preparing build directories ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gen" "$BUILD_DIR/classes" "$BUILD_DIR/dex"

cd "$PROJECT_DIR"

echo "=== 1b. Compiling native zygote_exec binary with NDK ==="
NDK_CLANG=$(ls -d "$ANDROID_HOME/ndk/"*/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang 2>/dev/null | sort -V | tail -n 1)
if [ -n "$NDK_CLANG" ] && [ -x "$NDK_CLANG" ]; then
    STRIP=$(dirname "$NDK_CLANG")/llvm-strip
    "$NDK_CLANG" -O2 -Wall src/native/zygote_exec.c -o assets/zygote_exec
    "$NDK_CLANG" -O2 -Wall -static src/native/watchdog_feeder.c -o assets/watchdog_feeder
    [ -x "$STRIP" ] && "$STRIP" assets/zygote_exec assets/watchdog_feeder
    echo "[*] Compiled and stripped assets/zygote_exec ($(wc -c < assets/zygote_exec) bytes) and assets/watchdog_feeder ($(wc -c < assets/watchdog_feeder) bytes)"
else
    echo "[!] Warning: NDK clang not found, keeping existing native binaries"
fi

echo "=== 2. Compiling resources with aapt2 ==="
"$SDK_TOOLS/aapt2" compile --dir res -o "$BUILD_DIR/compiled_res.zip"

echo "=== 3. Linking resources with aapt2 ==="
"$SDK_TOOLS/aapt2" link \
    -I "$PLATFORM_JAR" \
    --manifest AndroidManifest.xml \
    -o "$BUILD_DIR/base.apk" \
    --java "$BUILD_DIR/gen" \
    "$BUILD_DIR/compiled_res.zip" \
    -A assets

echo "=== 4. Compiling Java sources ==="
javac -source 1.8 -target 1.8 \
    -cp "$PLATFORM_JAR" \
    -d "$BUILD_DIR/classes" \
    src/com/wewaffles/anygsi/*.java \
    "$BUILD_DIR/gen/com/wewaffles/anygsi/R.java"

echo "=== 5. Generating Dalvik Executable (classes.dex) with d8 ==="
"$SDK_TOOLS/d8" \
    --lib "$PLATFORM_JAR" \
    --output "$BUILD_DIR/dex" \
    "$BUILD_DIR/classes/com/wewaffles/anygsi"/*.class

echo "=== 6. Packaging classes.dex into APK ==="
cd "$BUILD_DIR/dex"
zip -u "$BUILD_DIR/base.apk" classes.dex
cd "$PROJECT_DIR"

echo "=== 7. Aligning APK with zipalign ==="
"$SDK_TOOLS/zipalign" -v -p 4 "$BUILD_DIR/base.apk" "$BUILD_DIR/aligned.apk"

KEYSTORE="$PROJECT_DIR/keystore/debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
    mkdir -p "$PROJECT_DIR/keystore"
    keytool -genkey -v \
        -keystore "$KEYSTORE" \
        -storepass android \
        -alias androiddebugkey \
        -keypass android \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -dname "CN=AnyGSI,O=WeWaffles,C=US"
fi

echo "=== 8. Signing APK with apksigner ==="
"$SDK_TOOLS/apksigner" sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:android \
    --ks-key-alias androiddebugkey \
    --key-pass pass:android \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --v3-signing-enabled true \
    --out "$OUT_APK" \
    "$BUILD_DIR/aligned.apk"

echo "=== BUILD SUCCESSFUL ==="
echo "Output APK: $OUT_APK"
ls -la "$OUT_APK"
