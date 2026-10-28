#!/system/bin/sh
# restore_host.sh - Comprehensive One UI 9.0 Host Restoration Script
# Safely unmounts container bridges, recovers storage, fixes permissions & SELinux contexts,
# restores One UI Home screen layout and Quick Settings panel.

STAGE="/data/lineage"
[ -d "$STAGE" ] || STAGE="/data/local/tmp/lineage_stage"
BACKUP_DIR="/data/lineage/host_backup"
[ -d "$BACKUP_DIR" ] || BACKUP_DIR="/data/local/tmp/lineage_backups"

BB=$(which busybox 2>/dev/null || echo "/data/adb/ksu/bin/busybox")
[ -x "$BB" ] || BB=$(find /data/adb /system /data -name busybox 2>/dev/null | head -n 1)

echo "=== [1/8] Terminating Lingering Container Daemons & Watchdogs ==="
pkill -9 -f "ctl.stop zygote" 2>/dev/null || true
pkill -9 -f "ui_activator" 2>/dev/null || true
pkill -9 -f "zygote_exec" 2>/dev/null || true
pkill -TERM watchdog_feeder 2>/dev/null || true
sleep 0.3
pkill -9 watchdog_feeder 2>/dev/null || true
pkill -9 -f "adb_watchdog.sh" 2>/dev/null || true
pkill -9 -f "ims_watchdog.sh" 2>/dev/null || true
pkill -9 -f "app_storage_loop.sh" 2>/dev/null || true
pkill -9 -f "logcat.*gsi_boot_logcat.log" 2>/dev/null || true
pkill -9 -f org.lineageos 2>/dev/null || true
pkill -9 -x zygote64 2>/dev/null || true
pkill -9 -f "system_server" 2>/dev/null || true

echo "=== [2/8] Safely Unmounting Container Mount Points ==="
# Unmount any bind mounts over host /data directories
for d in app app-staging user user_de media dalvik-cache misc/profiles data; do
    if mount | grep -q " /data/$d "; then
        echo "  Unmounting /data/$d..."
        umount -l "/data/$d" 2>/dev/null || true
    fi
done

# Unmount container rootfs and payload mounts
for stage_path in "$STAGE" "/data/lineage" "/data/local/tmp/lineage_stage"; do
    if [ -d "$stage_path/rootfs" ]; then
        umount -l "$stage_path/rootfs/apex"/* 2>/dev/null || true
        umount -l "$stage_path/rootfs"/* 2>/dev/null || true
        while mount | grep -q "$stage_path/rootfs"; do
            umount -l "$stage_path/rootfs" 2>/dev/null || true
            sleep 0.1
        done
    fi
done

# Unmount emulated storage mounts from container
umount -l /storage/emulated 2>/dev/null || true
umount -l /mnt/user/0/emulated 2>/dev/null || true

# Detach loop devices for system.raw
if [ -n "$BB" ] && [ -x "$BB" ]; then
    for l in $($BB losetup -a 2>/dev/null | grep -E "system\.raw|_payload\.img" | cut -d: -f1); do
        echo "  Detaching loop device: $l"
        $BB losetup -d "$l" 2>/dev/null || true
    done
fi

echo "=== [3/8] Restoring Installation Directory Permissions ==="
chown system:system /data /data/app /data/app-staging /data/local /data/local/tmp 2>/dev/null || true
chmod 0771 /data /data/app /data/app-staging 2>/dev/null || true
echo "  /data, /data/app, /data/app-staging restored to system:system 0771."

echo "=== [4/8] Restoring Internal Storage Ownership & Modes ==="
chown -R media_rw:media_rw /data/media/0 2>/dev/null || chown -R 1023:1023 /data/media/0 2>/dev/null || true
chown media_rw:ext_data_rw /data/media/0/Android/data 2>/dev/null || chown 1023:1078 /data/media/0/Android/data 2>/dev/null || true
chown media_rw:ext_obb_rw /data/media/0/Android/obb 2>/dev/null || chown 1023:1079 /data/media/0/Android/obb 2>/dev/null || true
chmod 2771 /data/media/0/Android/data /data/media/0/Android/obb /data/media/0/Android/media 2>/dev/null || true
echo "  /data/media/0 internal storage permissions restored."

echo "=== [5/8] Aligning App Storage Directories & Cleaning Orphans ==="
if [ -f /data/system/packages.list ]; then
    realigned_count=0
    while read -r pkg auid rest; do
        case "$auid" in ''|*[!0-9]*) continue ;; esac
        # /data/media/0/Android/data/<pkg> -> UID:ext_data_rw (2770)
        if [ -d "/data/media/0/Android/data/$pkg" ]; then
            chown -R "$auid:ext_data_rw" "/data/media/0/Android/data/$pkg" 2>/dev/null || \
                chown -R "$auid:1078" "/data/media/0/Android/data/$pkg" 2>/dev/null || true
            chmod 2770 "/data/media/0/Android/data/$pkg" 2>/dev/null || true
            realigned_count=$((realigned_count + 1))
        fi
        # /data/media/0/Android/media/<pkg> -> UID:media_rw (2770)
        if [ -d "/data/media/0/Android/media/$pkg" ]; then
            chown -R "$auid:media_rw" "/data/media/0/Android/media/$pkg" 2>/dev/null || \
                chown -R "$auid:1023" "/data/media/0/Android/media/$pkg" 2>/dev/null || true
            chmod 2770 "/data/media/0/Android/media/$pkg" 2>/dev/null || true
        fi
        # /data/media/0/Android/obb/<pkg> -> UID:ext_obb_rw (2770)
        if [ -d "/data/media/0/Android/obb/$pkg" ]; then
            chown -R "$auid:ext_obb_rw" "/data/media/0/Android/obb/$pkg" 2>/dev/null || \
                chown -R "$auid:1079" "/data/media/0/Android/obb/$pkg" 2>/dev/null || true
            chmod 2770 "/data/media/0/Android/obb/$pkg" 2>/dev/null || true
        fi
    done < /data/system/packages.list
    echo "  Realigned $realigned_count package media directories."

    # Remove orphaned GSI package directories not in host packages.list
    orphans_removed=0
    for kind_dir in /data/media/0/Android/data /data/media/0/Android/media /data/media/0/Android/obb; do
        [ -d "$kind_dir" ] || continue
        for app_dir in "$kind_dir"/*; do
            [ -d "$app_dir" ] || continue
            pkg_name=$(basename "$app_dir")
            if ! grep -q "^$pkg_name " /data/system/packages.list 2>/dev/null; then
                echo "  Removing orphaned GSI directory: $app_dir"
                rm -rf "$app_dir" 2>/dev/null || true
                orphans_removed=$((orphans_removed + 1))
            fi
        done
    done
    echo "  Cleaned $orphans_removed orphaned package directories."
else
    echo "  Warning: /data/system/packages.list not found, skipping package media scan."
fi

echo "=== [6/8] Restoring One UI Home Screen Layout & Quick Settings ==="
LAUNCHER_PKG="com.sec.android.app.launcher"
LAUNCHER_DATA="/data/user/0/$LAUNCHER_PKG"

# Determine exact launcher UID from packages.list
LAUNCHER_UID=$(grep "^$LAUNCHER_PKG " /data/system/packages.list 2>/dev/null | awk '{print $2}')
[ -n "$LAUNCHER_UID" ] || LAUNCHER_UID=$(stat -c %u "$LAUNCHER_DATA" 2>/dev/null || echo 10160)
LAUNCHER_GID="$LAUNCHER_UID"

# Force-stop One UI Home launcher
am force-stop "$LAUNCHER_PKG" 2>/dev/null || true

if [ -d "$BACKUP_DIR" ]; then
    # 1. Restore databases
    if [ -d "$BACKUP_DIR/databases" ]; then
        mkdir -p "$LAUNCHER_DATA/databases"
        cp -a "$BACKUP_DIR/databases"/* "$LAUNCHER_DATA/databases/" 2>/dev/null || true
        echo "  Restored launcher databases from $BACKUP_DIR/databases"
    elif [ -f "$BACKUP_DIR/launcher.db" ] || [ -f "$BACKUP_DIR/appOrder.db" ]; then
        mkdir -p "$LAUNCHER_DATA/databases"
        cp -a "$BACKUP_DIR"/*.db* "$LAUNCHER_DATA/databases/" 2>/dev/null || true
        echo "  Restored launcher database files from $BACKUP_DIR"
    fi

    # 2. Restore shared_prefs
    if [ -d "$BACKUP_DIR/shared_prefs" ]; then
        mkdir -p "$LAUNCHER_DATA/shared_prefs"
        cp -a "$BACKUP_DIR/shared_prefs"/* "$LAUNCHER_DATA/shared_prefs/" 2>/dev/null || true
        echo "  Restored launcher shared_prefs from $BACKUP_DIR/shared_prefs"
    fi

    # 3. Restore appwidgets.xml
    if [ -f "$BACKUP_DIR/appwidgets.xml" ]; then
        cp -f "$BACKUP_DIR/appwidgets.xml" /data/system/users/0/appwidgets.xml 2>/dev/null || true
        chown system:system /data/system/users/0/appwidgets.xml 2>/dev/null || true
        chmod 0600 /data/system/users/0/appwidgets.xml 2>/dev/null || true
        echo "  Restored /data/system/users/0/appwidgets.xml"
    fi

    # 4. Set accurate ownership and permissions
    if [ -d "$LAUNCHER_DATA/databases" ]; then
        chown -R "${LAUNCHER_UID}:${LAUNCHER_GID}" "$LAUNCHER_DATA/databases" 2>/dev/null || true
        chmod 771 "$LAUNCHER_DATA/databases" 2>/dev/null || true
        chmod 660 "$LAUNCHER_DATA/databases"/* 2>/dev/null || true
    fi
    if [ -d "$LAUNCHER_DATA/shared_prefs" ]; then
        chown -R "${LAUNCHER_UID}:${LAUNCHER_GID}" "$LAUNCHER_DATA/shared_prefs" 2>/dev/null || true
        chmod 771 "$LAUNCHER_DATA/shared_prefs" 2>/dev/null || true
        chmod 660 "$LAUNCHER_DATA/shared_prefs"/* 2>/dev/null || true
    fi

    # 5. Apply restorecon to launcher data
    restorecon -FR "$LAUNCHER_DATA" 2>/dev/null || true
    echo "  One UI Home launcher files restored with UID $LAUNCHER_UID:$LAUNCHER_GID"

    # 6. Restore Quick Settings tiles
    if [ -f "$BACKUP_DIR/sysui_qs_tiles.txt" ]; then
        QS_TILES=$(cat "$BACKUP_DIR/sysui_qs_tiles.txt" 2>/dev/null | tr -d '\r\n')
        if [ -n "$QS_TILES" ] && [ "$QS_TILES" != "null" ]; then
            settings put secure sysui_qs_tiles "$QS_TILES" 2>/dev/null || true
            echo "  Restored Quick Settings tiles: $QS_TILES"
        fi
    fi

    # 7. Restore settings_secure.xml / settings_system.xml if present
    for s_xml in settings_secure.xml settings_system.xml; do
        if [ -f "$BACKUP_DIR/$s_xml" ]; then
            cp -f "$BACKUP_DIR/$s_xml" "/data/system/users/0/$s_xml" 2>/dev/null || true
            chown system:system "/data/system/users/0/$s_xml" 2>/dev/null || true
            chmod 0600 "/data/system/users/0/$s_xml" 2>/dev/null || true
            echo "  Restored /data/system/users/0/$s_xml"
        fi
    done
else
    echo "  Notice: Backup directory $BACKUP_DIR not found. Skipping file restore."
fi

# 8. Restart launcher and systemui to update UI immediately
echo "  Restarting com.android.systemui and com.sec.android.app.launcher..."
killall com.android.systemui 2>/dev/null || pkill -9 -f com.android.systemui 2>/dev/null || true
am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || true

echo "=== [7/8] Applying Mandatory SELinux restorecon -FR on Host Trees ==="
restorecon -FR /data/media 2>/dev/null || true
restorecon -FR /data/app 2>/dev/null || true
restorecon -FR /data/app-staging 2>/dev/null || true
restorecon -FR /data/system/users/0 2>/dev/null || true
echo "  restorecon completed on /data/media, /data/app, /data/app-staging, /data/system/users/0."

echo "=== [8/8] Restarting MediaProvider Modules & Restoring Storage Mount ==="
am force-stop com.google.android.providers.media.module 2>/dev/null || true
am force-stop com.android.providers.media.module 2>/dev/null || true
pkill -9 -f "android.process.media" 2>/dev/null || true
pkill -9 -f "providers.media" 2>/dev/null || true

mkdir -p /storage/emulated/0 2>/dev/null || true
if ! mount | grep -q " /storage/emulated/0 "; then
    mount --bind /data/media/0 /storage/emulated/0 2>/dev/null || true
fi

# Restore SELinux enforcing mode
setenforce 1 2>/dev/null || true
echo "  SELinux mode: $(getenforce 2>/dev/null || echo unknown)"
echo "=== ONE UI HOST RESTORATION COMPLETED SUCCESSFULLY ==="
