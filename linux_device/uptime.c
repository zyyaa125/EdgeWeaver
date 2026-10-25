#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

MOONBIT_FFI_EXPORT int32_t edgeweaver_linux_host_supported(void) {
#ifdef __linux__
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t edgeweaver_linux_read_uptime(void) {
#ifdef __linux__
  FILE *file = fopen("/proc/uptime", "r");
  if (file == NULL) return -1;
  long long seconds = -1;
  int parsed = fscanf(file, "%lld", &seconds);
  int closed = fclose(file);
  if (parsed != 1 || closed != 0 || seconds < 0 || seconds > INT32_MAX) {
    return -1;
  }
  return (int32_t)seconds;
#else
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int32_t edgeweaver_linux_unix_now(void) {
#ifdef __linux__
  time_t now = time(NULL);
  if (now < 0 || (uint64_t)now > INT32_MAX) return -1;
  return (int32_t)now;
#else
  return -1;
#endif
}
