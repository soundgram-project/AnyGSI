#!/system/bin/sh
# backup_host.sh - Comprehensive One UI Host Layout & Quick Settings Backup Script
# Creates a full snapshot in /data/lineage/host_backup

BACKUP_DIR="/data/lineage/host_backup"
mkdir -p "$BACKUP_DIR"

echo "=== [1/5] Backing up One UI Home databases & preferences ==="
LAUNCHER_PKG="com.sec.android.app.launcher"
LAUNCHER_DATA="/data/user/0/$LAUNCHER_PKG"

if [ -d "$LAUNCHER_DATA/databases" ]; then
    mkdir -p "$BACKUP_DIR/databases"
    cp -a "$LAUNCHER_DATA/databases"/* "$BACKUP_DIR/databases/" 2>/dev/null || true
    echo "  Launcher databases backed up."
fi

if [ -d "$LAUNCHER_DATA/shared_prefs" ]; then
    mkdir -p "$BACKUP_DIR/shared_prefs"
    cp -a "$LAUNCHER_DATA/shared_prefs"/* "$BACKUP_DIR/shared_prefs/" 2>/dev/null || true
    echo "  Launcher shared_prefs backed up."
fi

echo "=== [2/5] Backing up appwidgets.xml ==="
if [ -f /data/system/users/0/appwidgets.xml ]; then
    cp -f /data/system/users/0/appwidgets.xml "$BACKUP_DIR/appwidgets.xml" 2>/dev/null || true
    echo "  /data/system/users/0/appwidgets.xml backed up."
fi

echo "=== [3/5] Backing up Quick Settings tiles ==="
QS_TILES=$(settings get secure sysui_qs_tiles 2>/dev/null)
if [ -n "$QS_TILES" ] && [ "$QS_TILES" != "null" ]; then
    echo "$QS_TILES" > "$BACKUP_DIR/sysui_qs_tiles.txt"
    echo "  sysui_qs_tiles saved: $QS_TILES"
fi

echo "=== [4/5] Backing up settings XMLs ==="
for s_xml in settings_secure.xml settings_system.xml; do
    if [ -f "/data/system/users/0/$s_xml" ]; then
        cp -f "/data/system/users/0/$s_xml" "$BACKUP_DIR/$s_xml" 2>/dev/null || true
        echo "  /data/system/users/0/$s_xml backed up."
    fi
done

echo "=== [5/5] Recording launcher identity ==="
LAUNCHER_UID=$(grep "^$LAUNCHER_PKG " /data/system/packages.list 2>/dev/null | awk '{print $2}')
[ -n "$LAUNCHER_UID" ] || LAUNCHER_UID=$(stat -c %u "$LAUNCHER_DATA" 2>/dev/null || echo 10160)
echo "$LAUNCHER_UID" > "$BACKUP_DIR/launcher_uid.txt"
echo "  Launcher UID recorded: $LAUNCHER_UID"

# Also maintain fallback copy in legacy directory if present
if [ -d "/data/local/tmp/lineage_backups" ]; then
    cp -a "$BACKUP_DIR"/* /data/local/tmp/lineage_backups/ 2>/dev/null || true
fi

chmod -R 700 "$BACKUP_DIR" 2>/dev/null || true
echo "=== ONE UI HOST BACKUP COMPLETED: $BACKUP_DIR ==="
