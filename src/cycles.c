#include <linux/perf_event.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <cycles.h>

static int fd = -1;

int cycles_init(void) {
    struct perf_event_attr pe;
    memset(&pe, 0, sizeof(pe));
    pe.type = PERF_TYPE_HARDWARE;
    pe.size = sizeof(pe);
    pe.config = PERF_COUNT_HW_CPU_CYCLES;
    pe.disabled = 1;
    pe.exclude_kernel = 1;
    pe.exclude_hv = 1;
    fd = (int) syscall(SYS_perf_event_open, &pe, 0, -1, -1, 0);
    return fd >= 0;
}

void cycles_start(void) {
    if (fd < 0) return;
    ioctl(fd, PERF_EVENT_IOC_RESET, 0);
    ioctl(fd, PERF_EVENT_IOC_ENABLE, 0);
}

long long cycles_stop(void) {
    long long count = -1;
    if (fd < 0) return -1;
    ioctl(fd, PERF_EVENT_IOC_DISABLE, 0);
    if (read(fd, &count, sizeof(count)) != sizeof(count)) return -1;
    return count;
}
