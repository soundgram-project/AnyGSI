#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/watchdog.h>
#include <signal.h>

static int g_fd = -1;

void handle_signal(int sig) {
    if (g_fd >= 0) {
        // Magic close: writing 'V' instructs Linux watchdog driver to stop
        write(g_fd, "V", 1);
        close(g_fd);
        g_fd = -1;
    }
    exit(0);
}

int main(int argc, char **argv) {
    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);

    int fd = -1;
    // Retry opening /dev/watchdog in case host system_server is still releasing it
    for (int i = 0; i < 50; i++) {
        fd = open("/dev/watchdog", O_WRONLY);
        if (fd >= 0) break;
        fd = open("/dev/watchdog0", O_WRONLY);
        if (fd >= 0) break;
        usleep(200000); // 200ms
    }

    if (fd < 0) {
        fprintf(stderr, "[watchdog_feeder] FATAL: Failed to open /dev/watchdog or /dev/watchdog0\n");
        return 1;
    }

    g_fd = fd;
    printf("[watchdog_feeder] Petting watchdog on fd %d every 5s\n", fd);
    fflush(stdout);

    while (1) {
        int dummy = 0;
        if (ioctl(fd, WDIOC_KEEPALIVE, &dummy) < 0) {
            write(fd, "\0", 1);
        }
        sleep(5);
    }

    return 0;
}
