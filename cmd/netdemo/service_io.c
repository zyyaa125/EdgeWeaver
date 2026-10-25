#include <moonbit.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#ifndef _WIN32
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static int valid_path(moonbit_bytes_t path) {
  size_t length = Moonbit_array_length(path);
  return length > 1 && strlen((const char *)path) == length &&
         ((const char *)path)[0] == '/';
}
#endif

MOONBIT_FFI_EXPORT moonbit_bytes_t edgeweaver_service_read_config(
    moonbit_bytes_t path) {
#ifdef _WIN32
  (void)path;
  return moonbit_make_bytes(0, 0);
#else
  if (!valid_path(path)) return moonbit_make_bytes(0, 0);
  int fd = open((const char *)path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) return moonbit_make_bytes(0, 0);
  struct stat st;
  if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) ||
      (st.st_uid != 0 && st.st_uid != geteuid()) ||
      (st.st_mode & 022) != 0 || st.st_size <= 0 || st.st_size > 4096) {
    close(fd);
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)st.st_size, 0);
  size_t read_total = 0;
  while (read_total < (size_t)st.st_size) {
    ssize_t n = read(fd, result + read_total, (size_t)st.st_size - read_total);
    if (n <= 0) {
      moonbit_decref(result);
      close(fd);
      return moonbit_make_bytes(0, 0);
    }
    read_total += (size_t)n;
  }
  if (close(fd) != 0) {
    moonbit_decref(result);
    return moonbit_make_bytes(0, 0);
  }
  return result;
#endif
}

MOONBIT_FFI_EXPORT int32_t edgeweaver_service_check_dir(
    moonbit_bytes_t path) {
#ifdef _WIN32
  (void)path;
  return 0;
#else
  if (!valid_path(path)) return 0;
  struct stat st;
  if (lstat((const char *)path, &st) != 0) return 0;
  return S_ISDIR(st.st_mode) && st.st_uid == geteuid() &&
         (st.st_mode & 077) == 0;
#endif
}

MOONBIT_FFI_EXPORT void edgeweaver_service_exit(int32_t code) {
  exit(code);
}

MOONBIT_FFI_EXPORT void edgeweaver_service_unbuffer_stdout(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
}
