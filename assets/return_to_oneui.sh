#!/system/bin/sh
# Return to One UI / Safe State Restoration
STAGE="/data/lineage"
[ -d "$STAGE" ] || STAGE="/data/local/tmp/lineage_stage"
APP_FILES="/data/user/0/com.wewaffles.anygsi/files"
[ -d "$APP_FILES" ] || APP_FILES="/data/user/0/com.wewaffles.onelineage/files"

echo "=== [1/2] Executing restore_host.sh ==="
if [ -f "$STAGE/restore_host.sh" ]; then
    /system/bin/sh "$STAGE/restore_host.sh"
elif [ -f "$APP_FILES/restore_host.sh" ]; then
    /system/bin/sh "$APP_FILES/restore_host.sh"
else
    echo "Warning: restore_host.sh not found, performing fallback unmount..."
    for d in app app-staging user user_de dalvik-cache misc/profiles data; do
        umount -l "/data/$d" 2>/dev/null || true
    done
    umount -l "$STAGE/rootfs"/* 2>/dev/null || true
    umount -l "$STAGE/rootfs" 2>/dev/null || true
fi

echo "=== [2/2] Starting One UI Display & Host Services ==="
setprop ctl.start surfaceflinger
setprop ctl.start zygote
setprop ctl.start audioserver
setprop ctl.start cameraserver
for svc in media media.extractor media.metrics wificond; do
    setprop ctl.start $svc 2>/dev/null || true
done

am force-stop com.sec.android.app.launcher 2>/dev/null || true
am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || true

setenforce 1 2>/dev/null || true
echo "SELinux mode: $(getenforce 2>/dev/null || echo unknown)"
echo "One UI returned successfully."
