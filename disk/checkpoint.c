#include <moonbit.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

#define EDGEWEAVER_MAX_CHECKPOINT (16u * 1024u * 1024u)

static int edgeweaver_valid_path(moonbit_bytes_t path) {
  size_t length = Moonbit_array_length(path);
  return length > 0 && strlen((const char *)path) == length;
}

#ifdef _WIN32
static wchar_t *edgeweaver_utf8_path(const char *path) {
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1,
                                   NULL, 0);
  if (length == 0 || (size_t)length > SIZE_MAX / sizeof(wchar_t)) {
    return NULL;
  }
  wchar_t *wide = (wchar_t *)malloc((size_t)length * sizeof(wchar_t));
  if (wide == NULL || MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path,
                                         -1, wide, length) == 0) {
    free(wide);
    return NULL;
  }
  return wide;
}
#endif

MOONBIT_FFI_EXPORT int32_t edgeweaver_checkpoint_write(
    moonbit_bytes_t path, moonbit_bytes_t data) {
  if (!edgeweaver_valid_path(path)) {
    return 0;
  }
  size_t path_len = strlen((const char *)path);
  size_t data_len = Moonbit_array_length(data);
  if (path_len == 0 || data_len == 0 || data_len > EDGEWEAVER_MAX_CHECKPOINT ||
      path_len > SIZE_MAX - 5) {
    return 0;
  }
  char *temporary = (char *)malloc(path_len + 5);
  if (temporary == NULL) {
    return 0;
  }
  memcpy(temporary, path, path_len);
  memcpy(temporary + path_len, ".tmp", 5);
#ifdef _WIN32
  wchar_t *wide_temporary = edgeweaver_utf8_path(temporary);
  wchar_t *wide_path = edgeweaver_utf8_path((const char *)path);
  if (wide_temporary == NULL || wide_path == NULL) {
    free(wide_temporary);
    free(wide_path);
    free(temporary);
    return 0;
  }
  FILE *file = _wfopen(wide_temporary, L"wb");
#else
  FILE *file = fopen(temporary, "wb");
#endif
  if (file == NULL) {
#ifdef _WIN32
    free(wide_temporary);
    free(wide_path);
#endif
    free(temporary);
    return 0;
  }
  int ok = fwrite(data, 1, data_len, file) == data_len && fflush(file) == 0;
  if (ok) {
#ifdef _WIN32
    ok = _commit(_fileno(file)) == 0;
#else
    ok = fsync(fileno(file)) == 0;
#endif
  }
  if (fclose(file) != 0) {
    ok = 0;
  }
  if (ok) {
#ifdef _WIN32
    ok = MoveFileExW(wide_temporary, wide_path,
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
    ok = rename(temporary, (const char *)path) == 0;
#endif
  }
  if (!ok) {
#ifdef _WIN32
    _wremove(wide_temporary);
#else
    remove(temporary);
#endif
  }
#ifdef _WIN32
  free(wide_temporary);
  free(wide_path);
#endif
  free(temporary);
  return ok ? 1 : 0;
}

MOONBIT_FFI_EXPORT int32_t edgeweaver_file_status(moonbit_bytes_t path) {
  if (!edgeweaver_valid_path(path)) {
    return -1;
  }
#ifdef _WIN32
  wchar_t *wide_path = edgeweaver_utf8_path((const char *)path);
  if (wide_path == NULL) {
    return -1;
  }
  errno = 0;
  FILE *file = _wfopen(wide_path, L"rb");
  free(wide_path);
#else
  errno = 0;
  FILE *file = fopen((const char *)path, "rb");
#endif
  if (file != NULL) {
    fclose(file);
    return 1;
  }
  return errno == ENOENT ? 0 : -1;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t edgeweaver_checkpoint_read(
    moonbit_bytes_t path) {
  if (!edgeweaver_valid_path(path)) {
    return moonbit_make_bytes(0, 0);
  }
#ifdef _WIN32
  wchar_t *wide_path = edgeweaver_utf8_path((const char *)path);
  if (wide_path == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  FILE *file = _wfopen(wide_path, L"rb");
  free(wide_path);
#else
  FILE *file = fopen((const char *)path, "rb");
#endif
  if (file == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  if (fseek(file, 0, SEEK_END) != 0) {
    fclose(file);
    return moonbit_make_bytes(0, 0);
  }
  long size = ftell(file);
  if (size <= 0 || (unsigned long)size > EDGEWEAVER_MAX_CHECKPOINT ||
      fseek(file, 0, SEEK_SET) != 0) {
    fclose(file);
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)size, 0);
  int ok = fread(result, 1, (size_t)size, file) == (size_t)size;
  if (fclose(file) != 0) {
    ok = 0;
  }
  if (!ok) {
    moonbit_decref(result);
    return moonbit_make_bytes(0, 0);
  }
  return result;
}

MOONBIT_FFI_EXPORT int32_t edgeweaver_checkpoint_remove(moonbit_bytes_t path) {
  if (!edgeweaver_valid_path(path)) return 0;
#ifdef _WIN32
  wchar_t *wide_path = edgeweaver_utf8_path((const char *)path);
  if (wide_path == NULL) return 0;
  int result = _wremove(wide_path) == 0;
  free(wide_path);
  return result;
#else
  return remove((const char *)path) == 0;
#endif
}
