#!/system/bin/sh
BB=$(which busybox 2>/dev/null || echo "/data/adb/ksu/bin/busybox")
[ -x "$BB" ] || BB=$(find /data/adb /system /data -name busybox 2>/dev/null | head -n 1)

echo "[Pivoted Root] Preparing pivot..."
cd /data/local/tmp/lineage_stage/rootfs
$BB mount --make-rprivate /
if ! $BB pivot_root . postinstall; then
    echo "[Pivoted Root] Fallback: bind mounting rootfs onto itself..."
    $BB mount --bind . .
    if ! $BB pivot_root . postinstall; then
        echo "[Pivoted Root] FATAL: pivot_root failed completely! Aborting."
        exit 1
    fi
fi
$BB mount -t proc proc /proc

export PATH=/system/bin:/system/xbin

echo "[Pivoted Root] Setting up /data_mirror and /data/data mounts for Zygote isolation..."
$BB mount --bind /data/user/0 /data/data 2>/dev/null || true
$BB mount -t tmpfs tmpfs /data_mirror 2>/dev/null || true
mkdir -p /data_mirror/data_de/null/0 /data_mirror/data_ce/null/0 /data_mirror/cur_profiles /data_mirror/ref_profiles
chmod -R 777 /data_mirror
$BB mount --bind /data/user_de/0 /data_mirror/data_de/null/0 2>/dev/null || true
$BB mount --bind /data/user/0 /data_mirror/data_ce/null/0 2>/dev/null || true
mkdir -p /data/misc/profiles/cur /data/misc/profiles/ref
$BB mount --bind /data/misc/profiles/cur /data_mirror/cur_profiles 2>/dev/null || true
$BB mount --bind /data/misc/profiles/ref /data_mirror/ref_profiles 2>/dev/null || true

echo "[Pivoted Root] Setting up /data/media and emulated storage..."
mkdir -p /data/media/0/Android /data/media/0/Pictures/Screenshots /data/media/0/Download /data/media/0/DCIM /data/media/0/Documents
chmod 0775 /data/media/0/Pictures /data/media/0/Download /data/media/0/DCIM /data/media/0/Documents 2>/dev/null || true
chown 1023:1023 /data/media/0/Pictures /data/media/0/Download /data/media/0/DCIM /data/media/0/Documents 2>/dev/null || true
$BB mount -t tmpfs tmpfs /storage 2>/dev/null || true
mkdir -p /storage/emulated/0
$BB mount --bind /data/media/0 /storage/emulated/0 2>/dev/null || true
mkdir -p /mnt/user/0
$BB mount -t tmpfs tmpfs /mnt/user/0 2>/dev/null || true
mkdir -p /mnt/user/0/emulated
$BB mount --bind /data/media/0 /mnt/user/0/emulated 2>/dev/null || true

echo "[Pivoted Root] Preserving /metadata/aconfig storage for GSI..."
mkdir -p /metadata/aconfig/flags /metadata/aconfig/maps /metadata/aconfig/boot 2>/dev/null || true
chmod -R 775 /metadata/aconfig 2>/dev/null || true
chown -R root:system /metadata/aconfig 2>/dev/null || true

# Pre-populate /metadata/aconfig/maps and /metadata/aconfig/boot from GSI partition images
for part in system system_ext product vendor; do
    src="/$part/etc/aconfig"
    [ -d "$src" ] || src="/system/$part/etc/aconfig"
    [ -d "$src" ] || src="/system/product/etc/aconfig"
    if [ -d "$src" ]; then
        cp -f "$src/package.map" "/metadata/aconfig/maps/${part}.package.map" 2>/dev/null || true
        cp -f "$src/flag.map" "/metadata/aconfig/maps/${part}.flag.map" 2>/dev/null || true
        cp -f "$src/flag.val" "/metadata/aconfig/boot/${part}.val" 2>/dev/null || true
        cp -f "$src/flag.info" "/metadata/aconfig/boot/${part}.info" 2>/dev/null || true
    fi
done

# Pre-populate APEX aconfig maps so modular packages resolve correctly
for amap in /apex/*/etc/aconfig/package.map; do
    [ -f "$amap" ] || continue
    adir=$(dirname $(dirname "$amap"))
    mname=$(basename "$adir" | cut -d@ -f1)
    cp -f "$adir/etc/aconfig/package.map" "/metadata/aconfig/maps/${mname}.package.map" 2>/dev/null || true
    cp -f "$adir/etc/aconfig/flag.map" "/metadata/aconfig/maps/${mname}.flag.map" 2>/dev/null || true
    cp -f "$adir/etc/aconfig/flag.val" "/metadata/aconfig/boot/${mname}.val" 2>/dev/null || true
    cp -f "$adir/etc/aconfig/flag.info" "/metadata/aconfig/boot/${mname}.info" 2>/dev/null || true
done

# Populate synthetic xr aconfig package to satisfy AppOpsManager if present
for ext in package.map flag.map; do
    [ -f "/data/xr.$ext" ] && cp -f "/data/xr.$ext" "/metadata/aconfig/maps/xr.$ext" 2>/dev/null || true
done
for ext in val info; do
    [ -f "/data/xr.$ext" ] && cp -f "/data/xr.$ext" "/metadata/aconfig/boot/xr.$ext" 2>/dev/null || true
done

if [ -x /system/bin/aconfigd-system ]; then
    /system/bin/aconfigd-system early-platform-init 2>/dev/null || true
    /system/bin/aconfigd-system platform-init 2>/dev/null || true
fi

chmod -R 755 /metadata/aconfig 2>/dev/null || true
chmod 644 /metadata/aconfig/maps/* /metadata/aconfig/boot/* 2>/dev/null || true
chown -R root:system /metadata/aconfig 2>/dev/null || true

echo "[Pivoted Root] Rootfs successfully activated as /"
touch /gsi_mode.flag 2>/dev/null || true
if [ -f /system/etc/preloaded-classes ] && [ -s /system/etc/preloaded-classes ]; then
    mkdir -p /data/etc
    echo "# Cleared preloaded-classes for guest GSI" > /data/etc/preloaded-classes
    $BB mount --bind /data/etc/preloaded-classes /system/etc/preloaded-classes 2>/dev/null || true
    echo "[Pivoted Root] Sanitized preloaded-classes verified."
fi
echo "[Pivoted Root] Testing /dev/null resolution:"
exec 8< /dev/null
echo -n "FD 8: "
$BB readlink /proc/$$/fd/8
exec 8<&-

echo "[Pivoted Root] Testing su availability:"
su -c id || echo "su check non-fatal"

echo "[Pivoted Root] Starting LineageOS SurfaceFlinger..."
# sf.log used to grow without bound: the guest's RenderEngine dumps LLVM IR for
# every shader it compiles ("Global Value @fullLiteral...") and got to 300+ MB in
# ~3 minutes, filling /data. SurfaceFlinger's real diagnostics go through logcat,
# so stderr can be dropped.
/system/bin/surfaceflinger > /dev/null 2>&1 &
SF_PID=$!
echo "[Pivoted Root] SurfaceFlinger PID: $SF_PID"
sleep 2

echo "[Pivoted Root] Starting LineageOS BootAnimation..."
setprop service.bootanim.exit 0
/system/bin/bootanimation > /data/anim.log 2>&1 &
ANIM_PID=$!
echo "[Pivoted Root] BootAnimation PID: $ANIM_PID"
sleep 1

echo "[Pivoted Root] Starting LineageOS Vold..."
/system/bin/vold --blkid_context=u:r:blkid:s0 --blkid_untrusted_context=u:r:blkid_untrusted:s0 --fsck_context=u:r:fsck:s0 --fsck_untrusted_context=u:r:fsck_untrusted:s0 > /data/vold.log 2>&1 &
VOLD_PID=$!
echo "[Pivoted Root] Vold PID: $VOLD_PID"
sleep 1

# Wifi. switch_to_lineage.sh stops the host wificond; the guest's own registers
# IWificond before WifiService initialises, and drives Samsung's wifi HAL (which
# is still registered by host init) with matching AIDL.
echo "[Pivoted Root] Starting LineageOS wificond..."
/system/bin/wificond > /data/wificond.log 2>&1 &
WIFICOND_PID=$!
echo "[Pivoted Root] wificond PID: $WIFICOND_PID"
sleep 1

# Overlay idmaps. idmap2 refuses the GSI's product overlays because framework-res
# does not declare the targeted resources as overlayable, so OMS ends up with no
# idmap at all and silently ignores every overlay: gesture navigation never
# applies (navbar stays 3-button) and the SystemUI accent overlays do nothing.
# Build the nav-bar idmap ourselves, before zygote can cache the empty overlay.
NAV_IDMAP="/data/resource-cache/system@product@overlay@NavigationBarModeGestural@NavigationBarModeGesturalOverlay.apk@idmap"
NAV_OV="/system/product/overlay/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk"
mkdir -p /data/resource-cache
if [ ! -s "$NAV_IDMAP" ] && [ -f "$NAV_OV" ]; then
    echo "[Pivoted Root] Generating gesture-nav overlay idmap..."
    /system/bin/idmap2 create --target-apk-path /system/framework/framework-res.apk \
        --overlay-apk-path "$NAV_OV" --idmap-path "$NAV_IDMAP" --ignore-overlayable \
        > /data/idmap.log 2>&1 \
        && chmod 644 "$NAV_IDMAP" && chown system:system "$NAV_IDMAP" \
        && echo "[Pivoted Root] idmap OK ($(wc -c < "$NAV_IDMAP") bytes)" \
        || echo "[Pivoted Root] idmap FAILED: $(head -n1 /data/idmap.log 2>/dev/null)"
fi

# Newly installed apps have no data directories (the guest has no installd), and
# zygote kills their first launch with "Failed to mount /data_mirror/...". This
# sweep creates them while Lineage runs, so Play Store/Aurora installs become
# launchable within ~15 s.
if [ -x /system/bin/setsid ]; then
    setsid /system/bin/sh /data/local/tmp/app_storage_loop.sh < /dev/null > /dev/null 2>&1 &
else
    /system/bin/sh /data/local/tmp/app_storage_loop.sh < /dev/null > /dev/null 2>&1 &
fi
echo "[Pivoted Root] App storage sweeper started..."

# Unset host Samsung classpath variables so foreign Knox/Samsung jars aren't forced into guest Zygote
unset BOOTCLASSPATH DEX2OATBOOTCLASSPATH SYSTEMSERVERCLASSPATH STANDALONE_SYSTEMSERVER_JARS

# First try derive_classpath (the canonical Android way to query mounted APEXes and partitions)
DERIVE_CP=""
for dc in /apex/com.android.sdkext/bin/derive_classpath /system/bin/derive_classpath; do
    if [ -x "$dc" ]; then
        DERIVE_CP="$dc"
        break
    fi
done
if [ -n "$DERIVE_CP" ]; then
    echo "[Pivoted Root] Running $DERIVE_CP..."
    mkdir -p /data/system/environ
    "$DERIVE_CP" /data/system/environ/classpath 2>/dev/null || true
    if [ -f /data/system/environ/classpath ]; then
        echo "[Pivoted Root] Reading computed classpath from /data/system/environ/classpath..."
        while read -r cmd var val; do
            if [ "$cmd" = "export" ] && [ -n "$var" ] && [ -n "$val" ]; then
                clean_val=$(echo "$val" | sed 's/:[^:]*samsung[^:]*//g' | sed 's/:[^:]*knox[^:]*//g')
                export "$var=$clean_val"
            fi
        done < /data/system/environ/classpath
    fi
fi

# Load remaining native environment variables from GSI init.environ.rc if present
for env_file in /init.environ.rc /system/etc/init/hw/init.environ.rc /system/init.environ.rc; do
    if [ -f "$env_file" ]; then
        echo "[Pivoted Root] Checking GSI environment from $env_file..."
        while read -r cmd var val; do
            if [ "$cmd" = "export" ] && [ -n "$var" ] && [ -n "$val" ]; then
                eval "cur_val=\$$var"
                if [ -z "$cur_val" ]; then
                    export "$var=$val"
                fi
            fi
        done < "$env_file"
        break
    fi
done

if [ -f /system/framework/org.lineageos.platform.jar ] && ! echo "$SYSTEMSERVERCLASSPATH" | grep -q 'org.lineageos.platform.jar'; then
    export SYSTEMSERVERCLASSPATH="${SYSTEMSERVERCLASSPATH:+$SYSTEMSERVERCLASSPATH:}/system/framework/org.lineageos.platform.jar"
fi

echo "[Pivoted Root] Cleaning stale sockets..."
rm -f /dev/socket/zygote /dev/socket/zygote_secondary /dev/socket/usap_pool_primary 2>/dev/null || true

echo "[Pivoted Root] Launching LineageOS Zygote & SystemServer via zygote_exec (supervised)..."
setprop sys.user.0.ce_available true 2>/dev/null || true
while true; do
    rm -f /dev/socket/zygote /dev/socket/zygote_secondary /dev/socket/usap_pool_primary 2>/dev/null || true
    /data/zygote_exec
    RET=$?
    echo "[Pivoted Root] zygote_exec exited with code $RET at $(date)"
    chmod -R 777 /data/system/dropbox 2>/dev/null || true
    chmod 666 /data/gsi_boot_logcat.log 2>/dev/null || true
    sleep 2
done
