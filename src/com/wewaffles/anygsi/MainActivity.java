package com.wewaffles.anygsi;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.view.View;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private TextView tvRootStatus;
    private TextView tvOsStatus;
    private TextView tvImageStatus;
    private TextView tvHeaderSubtitle;
    private TextView tvImageDesc;
    private TextView tvDownloadProgress;
    private ProgressBar pbDownload;
    private TextView tvConsoleLog;
    private TextView tvLogStatus;

    private Button btnSelectImg;
    private Button btnDeleteImg;
    private Button btnBootLineage;
    private Button btnReturnOneUI;
    private Button btnBackupLauncher;
    private Button btnRestoreLauncher;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private boolean isRootGranted = false;

    // KernelSU / root execution prefix
    private String[] suCommandPrefix = new String[]{"su"};
    private static final int PICK_GSI_FILE_REQUEST = 1001;

    private static final String STAGE_DIR = "/data/lineage";
    private static final String LEGACY_STAGE_DIR = "/data/local/tmp/lineage_stage";
    private static final String SYSTEM_RAW = STAGE_DIR + "/system.raw";
    private static final String BACKUP_DIR = STAGE_DIR + "/host_backup";

    private static final String[][] ROOT_CANDIDATES = new String[][]{
        {"/data/adb/ksud", "debug", "su"},
        {"/data/adb/ksu/bin/su"},
        {"/data/user_de/0/df.root/ksud", "debug", "su"},
        {"/data/user_de/0/df.root/ksud"},
        {"/system/bin/su"},
        {"/system/xbin/su"},
        {"su"}
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        tvRootStatus = findViewById(R.id.tv_root_status);
        tvOsStatus = findViewById(R.id.tv_os_status);
        tvImageStatus = findViewById(R.id.tv_image_status);
        tvHeaderSubtitle = findViewById(R.id.tv_header_subtitle);
        tvImageDesc = findViewById(R.id.tv_image_desc);
        tvDownloadProgress = findViewById(R.id.tv_download_progress);
        pbDownload = findViewById(R.id.pb_download);
        tvConsoleLog = findViewById(R.id.tv_console_log);
        tvLogStatus = findViewById(R.id.tv_log_status);

        btnSelectImg = findViewById(R.id.btn_select_img);
        btnDeleteImg = findViewById(R.id.btn_delete_img);
        btnBootLineage = findViewById(R.id.btn_boot_lineage);
        btnReturnOneUI = findViewById(R.id.btn_return_oneui);
        btnBackupLauncher = findViewById(R.id.btn_backup_launcher);
        btnRestoreLauncher = findViewById(R.id.btn_restore_launcher);

        extractAssets();
        checkRootAndSystem();

        btnSelectImg.setOnClickListener(v -> selectGsiImage());
        btnDeleteImg.setOnClickListener(v -> confirmDeleteLineage());
        btnBootLineage.setOnClickListener(v -> bootLineage());
        btnReturnOneUI.setOnClickListener(v -> returnToOneUI());
        btnBackupLauncher.setOnClickListener(v -> backupOneUI());
        btnRestoreLauncher.setOnClickListener(v -> restoreOneUI());
    }

    @Override
    protected void onResume() {
        super.onResume();
        checkRootAndSystem();
    }

    private void appendLog(final String text) {
        mainHandler.post(() -> {
            if (tvConsoleLog != null) {
                tvConsoleLog.append(text + "\n");
                final int scrollAmount = tvConsoleLog.getLayout() != null ?
                        tvConsoleLog.getLayout().getLineTop(tvConsoleLog.getLineCount()) - tvConsoleLog.getHeight() : 0;
                if (scrollAmount > 0) {
                    tvConsoleLog.scrollTo(0, scrollAmount);
                }
            }
        });
    }

    private static String joinCommand(String[] parts) {
        if (parts == null || parts.length == 0) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < parts.length; i++) {
            if (i > 0) sb.append(' ');
            sb.append(parts[i]);
        }
        return sb.toString();
    }

    private String[] buildRootCmd(String shellScript) {
        String[] cmd = new String[suCommandPrefix.length + 2];
        System.arraycopy(suCommandPrefix, 0, cmd, 0, suCommandPrefix.length);
        cmd[suCommandPrefix.length] = "-c";
        cmd[suCommandPrefix.length + 1] = shellScript;
        return cmd;
    }

    private ProcessBuilder buildRootProcessBuilder(String shellScript) {
        return new ProcessBuilder(buildRootCmd(shellScript));
    }

    private int runRootCmdDrained(String cmd) {
        try {
            ProcessBuilder pb = buildRootProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
            while (reader.readLine() != null) {
                // drain stdout/stderr
            }
            return p.waitFor();
        } catch (Exception e) {
            return -1;
        }
    }

    private void setLogStatus(final String status) {
        mainHandler.post(() -> {
            if (tvLogStatus != null) {
                tvLogStatus.setText(status);
            }
        });
    }

    private void checkRootAndSystem() {
        executor.execute(() -> {
            try {
                File dfKsud = new File("/data/user_de/0/df.root/ksud");
                if (dfKsud.exists() && dfKsud.canExecute()) {
                    Runtime.getRuntime().exec(new String[]{dfKsud.getAbsolutePath(), "install"}).waitFor();
                }
            } catch (Exception ignored) {}

            boolean foundRoot = false;
            for (String[] candidate : ROOT_CANDIDATES) {
                try {
                    String[] testCmd = new String[candidate.length + 2];
                    System.arraycopy(candidate, 0, testCmd, 0, candidate.length);
                    testCmd[candidate.length] = "-c";
                    testCmd[candidate.length + 1] = "id";

                    Process p = Runtime.getRuntime().exec(testCmd);
                    BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
                    String line = reader.readLine();
                    int exitCode = p.waitFor();

                    if (exitCode == 0 && line != null && line.contains("uid=0")) {
                        foundRoot = true;
                        suCommandPrefix = candidate;
                        break;
                    }
                } catch (Exception ignored) {}
            }

            isRootGranted = foundRoot;
            if (isRootGranted) {
                extractAssets();
            }
            mainHandler.post(() -> {
                if (isRootGranted) {
                    tvRootStatus.setText("✓ Root: KernelSU Active (" + joinCommand(suCommandPrefix) + ")");
                    tvRootStatus.setTextColor(Color.parseColor("#A5D6A7"));
                } else {
                    tvRootStatus.setText("✗ Root: Доступ запрещен (требуется KernelSU)");
                    tvRootStatus.setTextColor(Color.parseColor("#FFB4AB"));
                }
            });

            // Check active userspace
            try {
                Process pContainer = buildRootProcessBuilder(
                    "if [ -f /gsi_mode.flag ]; then echo 'CONTAINER'; else echo 'HOST'; fi"
                ).start();
                BufferedReader cReader = new BufferedReader(new InputStreamReader(pContainer.getInputStream()));
                String cMode = cReader.readLine();
                pContainer.waitFor();

                Process pRelease = buildRootProcessBuilder("getprop ro.build.version.release").start();
                BufferedReader relReader = new BufferedReader(new InputStreamReader(pRelease.getInputStream()));
                String release = relReader.readLine();
                pRelease.waitFor();

                Process pOs = buildRootProcessBuilder("getprop ro.lineage.version").start();
                BufferedReader osReader = new BufferedReader(new InputStreamReader(pOs.getInputStream()));
                String osVer = osReader.readLine();
                pOs.waitFor();

                Process pDisp = buildRootProcessBuilder("getprop ro.build.display.id").start();
                BufferedReader dispReader = new BufferedReader(new InputStreamReader(pDisp.getInputStream()));
                String dispId = dispReader.readLine();
                pDisp.waitFor();

                boolean isGuest = "CONTAINER".equals(cMode) || (osVer != null && !osVer.trim().isEmpty());

                mainHandler.post(() -> {
                    if (isGuest) {
                        String name = (osVer != null && !osVer.trim().isEmpty())
                                ? "LineageOS " + osVer.trim()
                                : "GSI Android " + (release != null ? release.trim() : "17") + (dispId != null && !dispId.trim().isEmpty() ? " (" + dispId.trim() + ")" : "");
                        tvOsStatus.setText("Текущее пространство: " + name);
                        tvOsStatus.setTextColor(Color.parseColor("#78D9EC"));
                        if (tvHeaderSubtitle != null) {
                            tvHeaderSubtitle.setText("AnyGSI • " + ((osVer != null && !osVer.trim().isEmpty()) ? "LineageOS" : "Гостевой GSI"));
                        }
                    } else {
                        tvOsStatus.setText("Текущее пространство: Samsung One UI (Хост Android " + (release != null ? release.trim() : "17") + ")");
                        tvOsStatus.setTextColor(Color.parseColor("#FFD54F"));
                        if (tvHeaderSubtitle != null) {
                            tvHeaderSubtitle.setText("AnyGSI • One UI");
                        }
                    }
                });
            } catch (Exception e) {
                mainHandler.post(() -> tvOsStatus.setText("Текущее пространство: Ошибка сканирования"));
            }

            checkImageStatus();
        });
    }

    private void checkImageStatus() {
        executor.execute(() -> {
            try {
                String cmd = "if [ -s " + SYSTEM_RAW + " ]; then ls -lh " + SYSTEM_RAW + "; " +
                             "elif [ -s " + LEGACY_STAGE_DIR + "/system.raw ]; then ls -lh " + LEGACY_STAGE_DIR + "/system.raw; " +
                             "else echo 'MISSING'; fi";
                Process p = buildRootProcessBuilder(cmd).start();
                BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String out = reader.readLine();
                p.waitFor();

                mainHandler.post(() -> {
                    if (out != null && !out.contains("MISSING") && !out.trim().isEmpty()) {
                        String details = out.trim().replaceAll("\\s+", " ");
                        tvImageStatus.setText("Образ GSI: Готов (" + details + ")");
                        tvImageStatus.setTextColor(Color.parseColor("#A5D6A7"));
                        if (tvImageDesc != null) {
                            tvImageDesc.setText("Файл system.raw установлен. Нажмите «Запустить GSI» для переключения.");
                        }
                        btnBootLineage.setEnabled(true);
                        btnBootLineage.setAlpha(1.0f);
                        btnDeleteImg.setEnabled(true);
                    } else {
                        tvImageStatus.setText("Образ GSI: Не установлен (system.raw отсутствует)");
                        tvImageStatus.setTextColor(Color.parseColor("#FFB4AB"));
                        if (tvImageDesc != null) {
                            tvImageDesc.setText("Нажмите «Выбрать (.img)» для выбора образа GSI.");
                        }
                        btnBootLineage.setEnabled(false);
                        btnBootLineage.setAlpha(0.5f);
                        btnDeleteImg.setEnabled(false);
                    }
                });
            } catch (Exception e) {
                mainHandler.post(() -> tvImageStatus.setText("Ошибка проверки: " + e.getMessage()));
            }
        });
    }

    private void extractAssets() {
        executor.execute(() -> {
            String[] assets = {
                "switch_to_lineage.sh", "return_to_oneui.sh",
                "master_prepare.sh", "master_inner.sh",
                "restore_host.sh", "backup_host.sh",
                "zygote_exec", "watchdog_feeder", "clean_apex_info_list.xml",
                "services_patched.jar", "services_android17_patched.jar", "framework_patched.jar",
                "xr.package.map", "xr.flag.map", "xr.val", "xr.info",
                "7zz", "PermissionController_patched.apk"
            };
            File filesDir = getFilesDir();
            for (String asset : assets) {
                File target = new File(filesDir, asset);
                if (target.exists() && target.length() > 0 && ("services_patched.jar".equals(asset) || "services_android17_patched.jar".equals(asset))) {
                    continue; // Skip re-extracting services jars if already present
                }
                try (InputStream in = getAssets().open(asset);
                     OutputStream out = new FileOutputStream(target)) {
                    byte[] buffer = new byte[32768];
                    int read;
                    while ((read = in.read(buffer)) != -1) {
                        out.write(buffer, 0, read);
                    }
                    target.setExecutable(true, false);
                    target.setReadable(true, false);
                } catch (Exception e) {
                    appendLog("Ошибка распаковки " + asset + ": " + e.getMessage());
                }
            }
            if (isRootGranted) {
                try {
                    String syncCmd =
                        "mkdir -p " + STAGE_DIR + " " + BACKUP_DIR + " && " +
                        "for f in " + filesDir.getAbsolutePath() + "/*; do " +
                        "  base=$(basename \"$f\"); " +
                        "  cp -f \"$f\" \"" + STAGE_DIR + "/$base\"; " +
                        "done && " +
                        "if [ ! -e " + SYSTEM_RAW + " ] && [ -e " + LEGACY_STAGE_DIR + "/system.raw ]; then " +
                        "  ln -sf " + LEGACY_STAGE_DIR + "/system.raw " + SYSTEM_RAW + " 2>/dev/null || true; " +
                        "fi; " +
                        "cp -f " + filesDir.getAbsolutePath() + "/7zz /data/local/tmp/7zz 2>/dev/null; " +
                        "chmod 755 " + STAGE_DIR + "/*.sh " + STAGE_DIR + "/zygote_exec " + STAGE_DIR + "/watchdog_feeder " + STAGE_DIR + "/7zz /data/local/tmp/7zz 2>/dev/null";
                    runRootCmdDrained(syncCmd);
                } catch (Exception ignored) {}
            }
            appendLog("Компоненты AnyGSI проверены.");
        });
    }

    private void selectGsiImage() {
        if (!isRootGranted) {
            appendLog("ОШИБКА: Требуются root-права (KernelSU)!");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, PICK_GSI_FILE_REQUEST);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == PICK_GSI_FILE_REQUEST && resultCode == Activity.RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri != null) {
                validateAndInstallImg(uri);
            }
        }
    }

    private String queryDisplayName(Uri uri) {
        String name = null;
        if (uri.getScheme() != null && uri.getScheme().equals("content")) {
            try (Cursor cursor = getContentResolver().query(uri, null, null, null, null)) {
                if (cursor != null && cursor.moveToFirst()) {
                    int nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    if (nameIndex >= 0) {
                        name = cursor.getString(nameIndex);
                    }
                }
            } catch (Exception ignored) {}
        }
        if (name == null) {
            name = uri.getLastPathSegment();
        }
        return name;
    }

    private void validateAndInstallImg(final Uri uri) {
        final String displayName = queryDisplayName(uri);
        if (displayName == null || !displayName.toLowerCase().endsWith(".img")) {
            new AlertDialog.Builder(this)
                .setTitle("Неверный формат файла")
                .setMessage("Разрешено выбирать ТОЛЬКО файлы с расширением .img!\nВыбран: " + (displayName != null ? displayName : "неизвестно"))
                .setPositiveButton("OK", null)
                .show();
            appendLog("ОШИБКА: Разрешены только файлы .img! (" + displayName + ")");
            return;
        }

        executor.execute(() -> {
            setLogStatus("Импорт .img…");
            mainHandler.post(() -> {
                pbDownload.setVisibility(View.VISIBLE);
                pbDownload.setIndeterminate(true);
                tvDownloadProgress.setVisibility(View.VISIBLE);
                tvDownloadProgress.setText("Копирование " + displayName + " в директорию...");
                btnSelectImg.setEnabled(false);
            });

            try {
                runRootCmdDrained("mkdir -p " + STAGE_DIR + " && chmod 777 " + STAGE_DIR);
                appendLog("\n[GSI] Очистка старых данных контейнера...");
                runRootCmdDrained(wipeUserDataCmd());
                runRootCmdDrained("touch " + STAGE_DIR + "/.custom_gsi");

                File tempInCache = new File(getCacheDir(), "selected_gsi.img");
                if (tempInCache.exists()) tempInCache.delete();

                appendLog("[GSI] Копирование файла: " + displayName + "...");
                long copied = 0;
                try (InputStream in = getContentResolver().openInputStream(uri);
                     OutputStream out = new FileOutputStream(tempInCache)) {
                    byte[] buf = new byte[1048576]; // 1MB buffer
                    int r;
                    while ((r = in.read(buf)) != -1) {
                        out.write(buf, 0, r);
                        copied += r;
                    }
                    out.flush();
                }

                appendLog("✓ Файл скопирован (" + (copied / 1048576) + " МБ). Перемещение в " + SYSTEM_RAW + "...");
                runRootCmdDrained("mv -f " + tempInCache.getAbsolutePath() + " " + SYSTEM_RAW + " && chmod 644 " + SYSTEM_RAW);

                mainHandler.post(() -> {
                    pbDownload.setVisibility(View.GONE);
                    tvDownloadProgress.setText("Образ " + displayName + " успешно установлен!");
                    btnSelectImg.setEnabled(true);
                });
                setLogStatus("Готово");
                checkImageStatus();
            } catch (Exception e) {
                appendLog("Ошибка установки .img: " + e.getMessage());
                setLogStatus("Ошибка");
                mainHandler.post(() -> {
                    pbDownload.setVisibility(View.GONE);
                    tvDownloadProgress.setText("Ошибка: " + e.getMessage());
                    btnSelectImg.setEnabled(true);
                });
            }
        });
    }

    private String containerUnmountCmd() {
        return "BB=$(which busybox 2>/dev/null || echo /data/adb/ksu/bin/busybox); " +
               "[ -x \"$BB\" ] || BB=$(find /data/adb /system /data -name busybox 2>/dev/null | head -n 1); " +
               "for d in app app-staging user user_de media dalvik-cache misc/profiles data; do " +
               "  umount -l /data/$d 2>/dev/null || true; " +
               "done; " +
               "for rootfs in " + STAGE_DIR + "/rootfs " + LEGACY_STAGE_DIR + "/rootfs; do " +
               "  umount -l $rootfs/apex/* 2>/dev/null || true; " +
               "  umount -l $rootfs/* 2>/dev/null || true; " +
               "  umount -l $rootfs 2>/dev/null || true; " +
               "done; " +
               "if [ -x \"$BB\" ]; then " +
               "  for l in $($BB losetup -a 2>/dev/null | grep -E 'system\\.raw|_payload\\.img' | cut -d: -f1); do " +
               "    $BB losetup -d \"$l\" 2>/dev/null || true; " +
               "  done; " +
               "fi";
    }

    private String wipeUserDataCmd() {
        return containerUnmountCmd() + "; " +
               "rm -rf " + STAGE_DIR + "/data " + STAGE_DIR + "/rootfs " + STAGE_DIR + "/*_payload.img " + STAGE_DIR + "/temp_*.apex " +
               LEGACY_STAGE_DIR + "/data " + LEGACY_STAGE_DIR + "/rootfs; " +
               "mkdir -p " + STAGE_DIR + "/rootfs";
    }

    private void confirmDeleteLineage() {
        new AlertDialog.Builder(this)
            .setTitle("Очистить директорию?")
            .setMessage("Это действие остановит контейнер, отмонтирует loop-устройства и удалит system.raw и файлы контейнера из " + STAGE_DIR + ".")
            .setPositiveButton("Очистить", (dialog, which) -> deleteLineage())
            .setNegativeButton("Отмена", null)
            .show();
    }

    private void deleteLineage() {
        executor.execute(() -> {
            setLogStatus("Очистка…");
            appendLog("\n[ОЧИСТКА] Остановка процессов контейнера и отмонтирование...");
            try {
                String cleanupCmd =
                    "pkill -9 -f 'ctl.stop zygote' 2>/dev/null || true; " +
                    "pkill -9 -f 'ui_activator' 2>/dev/null || true; " +
                    "setprop service.bootanim.exit 0 2>/dev/null || true; " +
                    "pkill -9 -f 'zygote_exec' 2>/dev/null || true; " +
                    "pkill -9 -f 'watchdog_feeder' 2>/dev/null || true; " +
                    "pkill -9 -f 'system_server' 2>/dev/null || true; " +
                    "pkill -9 -f org.lineageos 2>/dev/null || true; " +
                    "pkill -9 -x zygote64 2>/dev/null || true; " +
                    "kill -9 $(pidof surfaceflinger) 2>/dev/null || true; " +
                    "kill -9 $(pidof bootanimation) 2>/dev/null || true; " +
                    containerUnmountCmd() + "; " +
                    "truncate -s 0 " + SYSTEM_RAW + " 2>/dev/null || true; " +
                    "rm -f " + SYSTEM_RAW + " " + STAGE_DIR + "/*.img " + STAGE_DIR + "/*.7z " + STAGE_DIR + "/*.img.tmp " + STAGE_DIR + "/.custom_gsi* " +
                    LEGACY_STAGE_DIR + "/system.raw " + LEGACY_STAGE_DIR + "/*.img; " +
                    "rm -rf " + STAGE_DIR + "/data " + STAGE_DIR + "/rootfs " + LEGACY_STAGE_DIR + "/data " + LEGACY_STAGE_DIR + "/rootfs; " +
                    "mkdir -p " + STAGE_DIR + "/rootfs; " +
                    "if [ -f " + SYSTEM_RAW + " ]; then echo 'ВНИМАНИЕ: system.raw еще занят!'; else echo 'Директория очищена, loop-устройства отмонтированы.'; fi";

                Process p = buildRootProcessBuilder(cleanupCmd).redirectErrorStream(true).start();
                BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line;
                boolean stillPresent = false;
                while ((line = reader.readLine()) != null) {
                    appendLog("  " + line);
                    if (line.contains("ВНИМАНИЕ: system.raw еще занят")) {
                        stillPresent = true;
                    }
                }
                p.waitFor();
                if (stillPresent) {
                    appendLog("✗ system.raw не удалось удалить (занят). Перезагрузите устройство и повторите.");
                    setLogStatus("Ошибка");
                } else {
                    appendLog("✓ Файлы успешно удалены, директория очищена!");
                    setLogStatus("Готово");
                }
                checkImageStatus();
            } catch (Exception e) {
                appendLog("Ошибка очистки: " + e.getMessage());
                setLogStatus("Ошибка");
            }
        });
    }

    private void bootLineage() {
        if (!isRootGranted) {
            appendLog("ОШИБКА: Требуются root-права для запуска GSI!");
            return;
        }
        appendLog("\n[СТАРТ] Подготовка к переключению на GSI...");
        setLogStatus("Переключение…");
        executor.execute(() -> {
            try {
                // 1. Verify system.raw exists
                int checkRaw = runRootCmdDrained("[ -s " + SYSTEM_RAW + " ] || [ -s " + LEGACY_STAGE_DIR + "/system.raw ]");
                if (checkRaw != 0) {
                    appendLog("ОШИБКА: Файл " + SYSTEM_RAW + " не найден или пуст! Сначала выберите образ через «Выбрать (.img)».");
                    setLogStatus("Ошибка");
                    return;
                }
                runRootCmdDrained("if [ ! -s " + SYSTEM_RAW + " ] && [ -s " + LEGACY_STAGE_DIR + "/system.raw ]; then ln -sf " + LEGACY_STAGE_DIR + "/system.raw " + SYSTEM_RAW + "; fi");

                // 2. Sync assets to stage
                File filesDir = getFilesDir();
                String syncCmd = "mkdir -p " + STAGE_DIR + " " + BACKUP_DIR + " && " +
                                 "for f in " + filesDir.getAbsolutePath() + "/*; do " +
                                 "  base=$(basename \"$f\"); " +
                                 "  cp -f \"$f\" \"" + STAGE_DIR + "/$base\"; " +
                                 "done && " +
                                 "chmod 755 " + STAGE_DIR + "/*.sh " + STAGE_DIR + "/zygote_exec " + STAGE_DIR + "/watchdog_feeder " + STAGE_DIR + "/7zz";
                runRootCmdDrained(syncCmd);

                String stageScript = STAGE_DIR + "/switch_to_lineage.sh";
                String cmd = "stageScript=" + stageScript + "; " +
                             "chmod 755 $stageScript; " +
                             "BB=$(which busybox 2>/dev/null || echo /data/adb/ksu/bin/busybox); " +
                             "[ -x \"$BB\" ] || BB=$(find /data/adb /system /data -name busybox 2>/dev/null | head -n 1); " +
                             "if [ -n \"$BB\" ] && [ -x \"$BB\" ]; then " +
                             "  $BB setsid /system/bin/sh $stageScript </dev/null >" + STAGE_DIR + "/takeover_app.log 2>&1 & " +
                             "else " +
                             "  nohup /system/bin/sh $stageScript </dev/null >" + STAGE_DIR + "/takeover_app.log 2>&1 & " +
                             "fi";
                buildRootProcessBuilder(cmd).start().waitFor();
                appendLog("Демон переключения успешно запущен. Экран переключается на GSI...");
                setLogStatus("Запущен");
            } catch (Exception e) {
                appendLog("Ошибка запуска: " + e.getMessage());
                setLogStatus("Ошибка");
            }
        });
    }

    private void returnToOneUI() {
        if (!isRootGranted) {
            appendLog("ОШИБКА: Требуются root-права для возврата в One UI!");
            return;
        }
        appendLog("\n[СТАРТ] Восстановление One UI...");
        setLogStatus("Восстановление…");
        executor.execute(() -> {
            try {
                String stageScript = STAGE_DIR + "/return_to_oneui.sh";
                String appScript = getFilesDir().getAbsolutePath() + "/return_to_oneui.sh";
                String userLog = "/storage/emulated/0/AnyGSI_restore.log";
                appendLog("[СТАРТ] Запуск возврата в One UI...");

                String runCmd = "if [ -f " + stageScript + " ]; then exec /system/bin/sh " + stageScript + " 2>&1 | tee " + userLog + "; " +
                                "elif [ -f " + appScript + " ]; then exec /system/bin/sh " + appScript + " 2>&1 | tee " + userLog + "; " +
                                "else echo 'return_to_oneui.sh не найден!'; fi";

                ProcessBuilder pb = buildRootProcessBuilder(runCmd);
                pb.redirectErrorStream(true);
                Process p = pb.start();

                BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    appendLog(line);
                }
                int exitCode = p.waitFor();

                if (exitCode != 0) {
                    appendLog("ОШИБКА: return_to_oneui.sh завершился с кодом " + exitCode + "!");
                    setLogStatus("Ошибка (" + exitCode + ")");
                } else {
                    appendLog("One UI успешно восстановлен!");
                    setLogStatus("Готово");
                }
            } catch (Exception e) {
                appendLog("Ошибка восстановления: " + e.getMessage());
                setLogStatus("Ошибка");
            }
        });
    }

    private void backupOneUI() {
        if (!isRootGranted) {
            appendLog("ОШИБКА: Требуются root-права для создания бэкапа!");
            return;
        }
        executor.execute(() -> {
            setLogStatus("Бэкап…");
            appendLog("\n[БЭКАП] Создание резервной копии рабочего стола One UI и шторки QS...");
            try {
                String stageScript = STAGE_DIR + "/backup_host.sh";
                String appScript = getFilesDir().getAbsolutePath() + "/backup_host.sh";
                String runCmd = "if [ -f " + stageScript + " ]; then /system/bin/sh " + stageScript + "; " +
                                "elif [ -f " + appScript + " ]; then /system/bin/sh " + appScript + "; " +
                                "else " +
                                "  mkdir -p /data/lineage/host_backup/databases /data/lineage/host_backup/shared_prefs && " +
                                "  cp -a /data/user/0/com.sec.android.app.launcher/databases/* /data/lineage/host_backup/databases/ 2>/dev/null; " +
                                "  cp -a /data/user/0/com.sec.android.app.launcher/shared_prefs/* /data/lineage/host_backup/shared_prefs/ 2>/dev/null; " +
                                "  [ -f /data/system/users/0/appwidgets.xml ] && cp -f /data/system/users/0/appwidgets.xml /data/lineage/host_backup/ 2>/dev/null; " +
                                "  settings get secure sysui_qs_tiles > /data/lineage/host_backup/sysui_qs_tiles.txt 2>/dev/null; " +
                                "  echo 'Fallback backup complete'; " +
                                "fi";

                ProcessBuilder pb = buildRootProcessBuilder(runCmd);
                pb.redirectErrorStream(true);
                Process p = pb.start();

                BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    appendLog("  " + line);
                }
                int exitCode = p.waitFor();
                if (exitCode == 0) {
                    appendLog("✓ Резервная копия рабочего стола и шторки QS успешно сохранена в " + BACKUP_DIR);
                    setLogStatus("Готово");
                } else {
                    appendLog("ОШИБКА бэкапа: код выхода " + exitCode);
                    setLogStatus("Ошибка (" + exitCode + ")");
                }
            } catch (Exception e) {
                appendLog("Ошибка бэкапа: " + e.getMessage());
                setLogStatus("Ошибка");
            }
        });
    }

    private void restoreOneUI() {
        if (!isRootGranted) {
            appendLog("ОШИБКА: Требуются root-права для восстановления One UI!");
            return;
        }
        executor.execute(() -> {
            setLogStatus("Восстановление…");
            appendLog("\n[ВОССТАНОВЛЕНИЕ] Запуск комплексного восстановления One UI (restore_host.sh)...");
            try {
                String stageScript = STAGE_DIR + "/restore_host.sh";
                String appScript = getFilesDir().getAbsolutePath() + "/restore_host.sh";
                String userLog = "/storage/emulated/0/AnyGSI_restore_host.log";

                String runCmd = "if [ -f " + stageScript + " ]; then exec /system/bin/sh " + stageScript + " 2>&1 | tee " + userLog + "; " +
                                "elif [ -f " + appScript + " ]; then exec /system/bin/sh " + appScript + " 2>&1 | tee " + userLog + "; " +
                                "else echo 'ОШИБКА: restore_host.sh не найден!'; fi";

                ProcessBuilder pb = buildRootProcessBuilder(runCmd);
                pb.redirectErrorStream(true);
                Process p = pb.start();

                BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    appendLog(line);
                }
                int exitCode = p.waitFor();
                if (exitCode == 0) {
                    appendLog("✓ Среда One UI (память, рабочий стол, шторка QS) успешно восстановлена!");
                    setLogStatus("Готово");
                } else {
                    appendLog("ОШИБКА восстановления: код выхода " + exitCode);
                    setLogStatus("Ошибка (" + exitCode + ")");
                }
            } catch (Exception e) {
                appendLog("Ошибка восстановления: " + e.getMessage());
                setLogStatus("Ошибка");
            }
        });
    }
}
