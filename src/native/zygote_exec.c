#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <errno.h>

extern char **environ;

static const char DEFAULT_BOOTCLASSPATH[] =
    "/apex/com.android.art/javalib/core-oj.jar:"
    "/apex/com.android.art/javalib/core-libart.jar:"
    "/apex/com.android.art/javalib/okhttp.jar:"
    "/apex/com.android.art/javalib/bouncycastle.jar:"
    "/apex/com.android.art/javalib/apache-xml.jar:"
    "/system/framework/framework.jar:"
    "/system/framework/framework-graphics.jar:"
    "/system/framework/framework-location.jar:"
    "/system/framework/ext.jar:"
    "/system/framework/telephony-common.jar:"
    "/system/framework/voip-common.jar:"
    "/system/framework/ims-common.jar:"
    "/system/framework/framework-ondeviceintelligence-platform.jar:"
    "/system/framework/framework-telecom.jar:"
    "/apex/com.android.telephonycore/javalib/framework-telecom.jar:"
    "/apex/com.android.i18n/javalib/core-icu4j.jar:"
    "/apex/com.android.adservices/javalib/framework-adservices.jar:"
    "/apex/com.android.adservices/javalib/framework-sdksandbox.jar:"
    "/apex/com.android.appsearch/javalib/framework-appsearch.jar:"
    "/apex/com.android.bt/javalib/framework-bluetooth.jar:"
    "/apex/com.android.configinfrastructure/javalib/framework-configinfrastructure.jar:"
    "/apex/com.android.conscrypt/javalib/conscrypt.jar:"
    "/apex/com.android.conscrypt/javalib/framework-conscrypt-nsc.jar:"
    "/apex/com.android.crashrecovery/javalib/framework-crashrecovery.jar:"
    "/apex/com.android.devicelock/javalib/framework-devicelock.jar:"
    "/apex/com.android.extservices/javalib/android.ext.adservices.jar:"
    "/apex/com.android.healthfitness/javalib/framework-healthfitness.jar:"
    "/apex/com.android.ipsec/javalib/android.net.ipsec.ike.jar:"
    "/apex/com.android.media/javalib/updatable-media.jar:"
    "/apex/com.android.mediaprovider/javalib/framework-mediaprovider.jar:"
    "/apex/com.android.mediaprovider/javalib/framework-pdf.jar:"
    "/apex/com.android.mediaprovider/javalib/framework-pdf-v.jar:"
    "/apex/com.android.mediaprovider/javalib/framework-photopicker.jar:"
    "/apex/com.android.nfcservices/javalib/framework-nfc.jar:"
    "/apex/com.android.npumanager/javalib/framework-npumanager.jar:"
    "/apex/com.android.ondevicepersonalization/javalib/framework-ondevicepersonalization.jar:"
    "/apex/com.android.os.statsd/javalib/framework-statsd.jar:"
    "/apex/com.android.permission/javalib/framework-permission.jar:"
    "/apex/com.android.permission/javalib/framework-permission-s.jar:"
    "/apex/com.android.profiling/javalib/framework-anomaly-detector.jar:"
    "/apex/com.android.profiling/javalib/framework-profiling.jar:"
    "/apex/com.android.scheduling/javalib/framework-scheduling.jar:"
    "/apex/com.android.sdkext/javalib/framework-sdkextensions.jar:"
    "/apex/com.android.telephonycore/javalib/framework-telephony.jar:"
    "/apex/com.android.tethering/javalib/framework-connectivity.jar:"
    "/apex/com.android.tethering/javalib/framework-connectivity-b.jar:"
    "/apex/com.android.tethering/javalib/framework-connectivity-t.jar:"
    "/apex/com.android.tethering/javalib/framework-tethering.jar:"
    "/apex/com.android.tethering/javalib/framework-nearby.jar:"
    "/apex/com.android.uprobestats/javalib/framework-uprobestats.jar:"
    "/apex/com.android.uwb/javalib/framework-ranging.jar:"
    "/apex/com.android.uwb/javalib/framework-uwb.jar:"
    "/apex/com.android.virt/javalib/framework-virtualization.jar:"
    "/apex/com.android.webapp/javalib/framework-webapp.jar:"
    "/apex/com.android.wifi/javalib/framework-wifi.jar";

static const char DEFAULT_DEX2OATBOOTCLASSPATH[] =
    "/apex/com.android.art/javalib/core-oj.jar:"
    "/apex/com.android.art/javalib/core-libart.jar:"
    "/apex/com.android.art/javalib/okhttp.jar:"
    "/apex/com.android.art/javalib/bouncycastle.jar:"
    "/apex/com.android.art/javalib/apache-xml.jar:"
    "/system/framework/framework.jar:"
    "/system/framework/framework-graphics.jar:"
    "/system/framework/framework-location.jar:"
    "/system/framework/ext.jar:"
    "/system/framework/telephony-common.jar:"
    "/system/framework/voip-common.jar:"
    "/system/framework/ims-common.jar:"
    "/system/framework/framework-ondeviceintelligence-platform.jar:"
    "/system/framework/framework-telecom.jar:"
    "/apex/com.android.telephonycore/javalib/framework-telecom.jar:"
    "/apex/com.android.i18n/javalib/core-icu4j.jar";

static const char DEFAULT_SYSTEMSERVERCLASSPATH[] =
    "/system/framework/com.android.location.provider.jar:"
    "/system/framework/services.jar:"
    "/system/framework/org.lineageos.platform.jar:"
    "/apex/com.android.adservices/javalib/service-adservices.jar:"
    "/apex/com.android.adservices/javalib/service-sdksandbox.jar:"
    "/apex/com.android.appsearch/javalib/service-appsearch.jar:"
    "/apex/com.android.art/javalib/service-art.jar:"
    "/apex/com.android.compos/javalib/service-compos.jar:"
    "/apex/com.android.configinfrastructure/javalib/service-configinfrastructure.jar:"
    "/apex/com.android.crashrecovery/javalib/service-crashrecovery.jar:"
    "/apex/com.android.healthfitness/javalib/service-healthfitness.jar:"
    "/apex/com.android.media/javalib/service-media-s.jar:"
    "/apex/com.android.ondevicepersonalization/javalib/service-ondevicepersonalization.jar:"
    "/apex/com.android.permission/javalib/service-permission.jar:"
    "/apex/com.android.rkpd/javalib/service-rkp.jar:"
    "/apex/com.android.telephonycore/javalib/service-telecom.jar:"
    "/apex/com.android.uprobestats/javalib/service-uprobestats-bridge.jar:"
    "/apex/com.android.virt/javalib/service-virtualization.jar";

static const char DEFAULT_STANDALONE_SYSTEMSERVER_JARS[] =
    "/apex/com.android.bt/javalib/service-bluetooth.jar:"
    "/apex/com.android.devicelock/javalib/service-devicelock.jar:"
    "/apex/com.android.healthfitness/javalib/service-healthfitness.jar:"
    "/apex/com.android.os.statsd/javalib/service-statsd.jar:"
    "/apex/com.android.profiling/javalib/service-profiling.jar:"
    "/apex/com.android.scheduling/javalib/service-scheduling.jar:"
    "/apex/com.android.telephonycore/javalib/service-telephony.jar:"
    "/apex/com.android.tethering/javalib/service-connectivity.jar:"
    "/apex/com.android.uprobestats/javalib/service-uprobestats.jar:"
    "/apex/com.android.uwb/javalib/service-ranging.jar:"
    "/apex/com.android.uwb/javalib/service-uwb.jar:"
    "/apex/com.android.webapp/javalib/service-webapp.jar:"
    "/apex/com.android.wifi/javalib/service-wifi.jar";

static void expand_path(const char *in, char *out, size_t out_size) {
    out[0] = '\0';
    const char *p = in;
    while (*p && strlen(out) + 1 < out_size) {
        if (strncmp(p, "${ANDROID_ART_ROOT}", 19) == 0) {
            strncat(out, "/apex/com.android.art", out_size - strlen(out) - 1);
            p += 19;
        } else if (strncmp(p, "$ANDROID_ART_ROOT", 17) == 0) {
            strncat(out, "/apex/com.android.art", out_size - strlen(out) - 1);
            p += 17;
        } else if (strncmp(p, "${ANDROID_I18N_ROOT}", 20) == 0) {
            strncat(out, "/apex/com.android.i18n", out_size - strlen(out) - 1);
            p += 20;
        } else if (strncmp(p, "$ANDROID_I18N_ROOT", 18) == 0) {
            strncat(out, "/apex/com.android.i18n", out_size - strlen(out) - 1);
            p += 18;
        } else if (strncmp(p, "${ANDROID_TZDATA_ROOT}", 22) == 0) {
            strncat(out, "/apex/com.android.tzdata", out_size - strlen(out) - 1);
            p += 22;
        } else if (strncmp(p, "$ANDROID_TZDATA_ROOT", 20) == 0) {
            strncat(out, "/apex/com.android.tzdata", out_size - strlen(out) - 1);
            p += 20;
        } else {
            size_t len = strlen(out);
            if (len + 1 < out_size) {
                out[len] = *p;
                out[len + 1] = '\0';
            }
            p++;
        }
    }
}

// Filters and merges classpath entries so that ONLY readable files present on disk are retained.
// Merges env var value with default_val to ensure modular APEX jars are NEVER omitted.
// Automatically deduplicates entries and expands placeholders like ${ANDROID_ART_ROOT}.
static void sanitize_classpath(const char *env_var, const char *default_val) {
    const char *source = getenv(env_var);
    size_t alloc_sz = (source ? strlen(source) : 0) + (default_val ? strlen(default_val) : 0) + 8192;
    char *copy = malloc(alloc_sz);
    if (!copy) return;
    copy[0] = '\0';

    if (source && *source) {
        strcat(copy, source);
    }
    if (default_val && *default_val) {
        if (copy[0]) strcat(copy, ":");
        strcat(copy, default_val);
    }

    for (char *c = copy; *c; c++) {
        if (*c == '\r' || *c == '\n') *c = '\0';
    }

    char *buf = malloc(alloc_sz);
    if (!buf) {
        free(copy);
        return;
    }
    buf[0] = '\0';

    char expanded[1024];
    char *saveptr = NULL;
    char *token = strtok_r(copy, ":", &saveptr);
    int first = 1;
    while (token) {
        if (*token) {
            expand_path(token, expanded, sizeof(expanded));
            if (access(expanded, R_OK) == 0) {
                // Check if already in buf
                char probe[1100];
                snprintf(probe, sizeof(probe), ":%s:", expanded);
                char *wrapped = malloc(strlen(buf) + 3);
                int already_present = 0;
                if (wrapped) {
                    sprintf(wrapped, ":%s:", buf);
                    if (strstr(wrapped, probe) != NULL) {
                        already_present = 1;
                    }
                    free(wrapped);
                }
                if (!already_present) {
                    if (!first) {
                        strcat(buf, ":");
                    }
                    strcat(buf, expanded);
                    first = 0;
                }
            }
        }
        token = strtok_r(NULL, ":", &saveptr);
    }

    if (buf[0]) {
        setenv(env_var, buf, 1);
        FILE *log = fopen("/data/zygote_exec.log", "a");
        if (log) {
            fprintf(log, "[zygote_exec] %s=%s\n", env_var, buf);
            fclose(log);
        }
    }
    free(buf);
    free(copy);
}

// Sets up a UNIX domain stream socket on path, chowns to root:system, and sets target_fd
static int setup_socket(const char *path, int target_fd) {
    unlink(path);

    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0) {
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(s);
        return -1;
    }

    if (listen(s, 16) < 0) {
        close(s);
        return -1;
    }

    if (s != target_fd) {
        if (dup2(s, target_fd) < 0) {
            close(s);
            return -1;
        }
        close(s);
    }

    fchmod(target_fd, 0660);
    chmod(path, 0660);
    fchown(target_fd, 0, 1000); // root:system
    chown(path, 0, 1000);

    // Clear FD_CLOEXEC so socket stays open across execve into app_process64
    int flags = fcntl(target_fd, F_GETFD);
    if (flags >= 0) {
        fcntl(target_fd, F_SETFD, flags & ~FD_CLOEXEC);
    }

    return target_fd;
}

int main(int argc, char **argv) {
    setpgid(0, 0);

    // 1. Basic Android system environment variables
    if (!getenv("PATH")) setenv("PATH", "/system/bin:/system/xbin", 1);
    if (!getenv("ANDROID_ROOT")) setenv("ANDROID_ROOT", "/system", 1);
    if (!getenv("ANDROID_DATA")) setenv("ANDROID_DATA", "/data", 1);
    if (!getenv("ANDROID_STORAGE")) setenv("ANDROID_STORAGE", "/storage", 1);
    if (!getenv("ANDROID_ART_ROOT")) setenv("ANDROID_ART_ROOT", "/apex/com.android.art", 1);
    if (!getenv("ANDROID_I18N_ROOT")) setenv("ANDROID_I18N_ROOT", "/apex/com.android.i18n", 1);
    if (!getenv("ANDROID_TZDATA_ROOT")) setenv("ANDROID_TZDATA_ROOT", "/apex/com.android.tzdata", 1);
    if (!getenv("ANDROID_ASSETS")) setenv("ANDROID_ASSETS", "/system/app", 1);
    if (!getenv("EXTERNAL_STORAGE")) setenv("EXTERNAL_STORAGE", "/sdcard", 1);
    if (!getenv("ASEC_MOUNTPOINT")) setenv("ASEC_MOUNTPOINT", "/mnt/asec", 1);

    // 2. Classpath sanitization:
    // If set by init.environ.rc, sanitize and verify files on disk.
    // If not set, fallback to default list and filter existing files.
    sanitize_classpath("BOOTCLASSPATH", DEFAULT_BOOTCLASSPATH);
    sanitize_classpath("DEX2OATBOOTCLASSPATH", DEFAULT_DEX2OATBOOTCLASSPATH);
    sanitize_classpath("SYSTEMSERVERCLASSPATH", DEFAULT_SYSTEMSERVERCLASSPATH);
    sanitize_classpath("STANDALONE_SYSTEMSERVER_JARS", DEFAULT_STANDALONE_SYSTEMSERVER_JARS);

    // 3. Ensure dalvik-cache directories exist with mode 0711 (required by app_main.cpp maybeCreateDalvikCache)
    mkdir("/data/dalvik-cache", 0711);
    chmod("/data/dalvik-cache", 0711);
    chown("/data/dalvik-cache", 0, 0);
    mkdir("/data/dalvik-cache/arm64", 0711);
    chmod("/data/dalvik-cache/arm64", 0711);
    chown("/data/dalvik-cache/arm64", 0, 0);

    // 4. Setup Zygote control sockets (fd 3 = zygote, fd 4 = usap_pool_primary)
    mkdir("/dev/socket", 0755);
    chmod("/dev/socket", 0755);

    if (setup_socket("/dev/socket/zygote", 3) < 0) {
        int err_fd = open("/data/zygote_err.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (err_fd >= 0) {
            dprintf(err_fd, "FATAL: Failed to setup /dev/socket/zygote: %s\n", strerror(errno));
            close(err_fd);
        }
        return 1;
    }
    setenv("ANDROID_SOCKET_zygote", "3", 1);
    unlink("/dev/socket/zygote_secondary");
    symlink("/dev/socket/zygote", "/dev/socket/zygote_secondary");

    if (setup_socket("/dev/socket/usap_pool_primary", 4) < 0) {
        int err_fd = open("/data/zygote_err.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (err_fd >= 0) {
            dprintf(err_fd, "FATAL: Failed to setup /dev/socket/usap_pool_primary: %s\n", strerror(errno));
            close(err_fd);
        }
        return 1;
    }
    setenv("ANDROID_SOCKET_usap_pool_primary", "4", 1);

    // 4. Stdio redirection:
    // CRITICAL: Zygote FileDescriptorTable enforces that standard fds 0, 1, 2 point to /dev/null!
    // If fd 1 or 2 point to a regular file, Zygote aborts with "open file descriptor not on whitelist".
    int null_fd = open("/dev/null", O_RDWR);
    if (null_fd >= 0) {
        dup2(null_fd, 0);
        dup2(null_fd, 1);
        dup2(null_fd, 2);
        if (null_fd > 2) {
            close(null_fd);
        }
    }

    // 5. Close any leftover fds >= 5
    for (int fd = 5; fd < 256; fd++) {
        close(fd);
    }

    // 6. Launch app_process64
    char *args64_jit[] = {
        "zygote64",
        "-Xzygote",
        "-Xforcejitzygote",
        "/system/bin",
        "--zygote",
        "--start-system-server",
        "--socket-name=zygote",
        NULL
    };
    execve("/system/bin/app_process64", args64_jit, environ);

    // If -Xforcejitzygote failed, try without it
    char *args64_nojit[] = {
        "zygote64",
        "-Xzygote",
        "/system/bin",
        "--zygote",
        "--start-system-server",
        "--socket-name=zygote",
        NULL
    };
    execve("/system/bin/app_process64", args64_nojit, environ);

    // If 64-bit app_process64 is not found, try 32-bit app_process
    char *args32_jit[] = {
        "zygote",
        "-Xzygote",
        "-Xforcejitzygote",
        "/system/bin",
        "--zygote",
        "--start-system-server",
        "--socket-name=zygote",
        NULL
    };
    execve("/system/bin/app_process", args32_jit, environ);

    char *args32_nojit[] = {
        "zygote",
        "-Xzygote",
        "/system/bin",
        "--zygote",
        "--start-system-server",
        "--socket-name=zygote",
        NULL
    };
    execve("/system/bin/app_process", args32_nojit, environ);

    // If all execve calls failed, record error to /data/zygote_err.log
    int err = errno;
    int err_fd = open("/data/zygote_err.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (err_fd >= 0) {
        dprintf(err_fd, "FATAL: execve(/system/bin/app_process64) failed: %s (%d)\n", strerror(err), err);
        close(err_fd);
    }

    return 1;
}
