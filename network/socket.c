#include <moonbit.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "Ws2_32.lib")
typedef SOCKET ew_socket;
#define EW_INVALID INVALID_SOCKET
#define ew_close closesocket
static int ew_init(void) {
  WSADATA data;
  return WSAStartup(MAKEWORD(2, 2), &data) == 0;
}
#else
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
typedef int ew_socket;
#define EW_INVALID (-1)
#define ew_close close
static int ew_init(void) { return 1; }
#endif

#define EW_MAX_FRAME 65536u

static int64_t ew_handle(ew_socket socket) {
  return socket == EW_INVALID ? -1 : (int64_t)(uintptr_t)socket;
}

static ew_socket ew_socket_of(int64_t handle) {
  return (ew_socket)(uintptr_t)handle;
}

static int ew_wait(ew_socket socket, int timeout_ms, int writing) {
  fd_set set;
  FD_ZERO(&set);
  FD_SET(socket, &set);
  struct timeval timeout = { timeout_ms / 1000, (timeout_ms % 1000) * 1000 };
  if (writing) {
    return select((int)(socket + 1), NULL, &set, NULL, &timeout) == 1;
  }
  return select((int)(socket + 1), &set, NULL, NULL, &timeout) == 1;
}

static int ew_set_timeout(ew_socket socket, int timeout_ms) {
#ifdef _WIN32
  DWORD value = (DWORD)timeout_ms;
  return setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, (const char *)&value,
                    sizeof(value)) == 0 &&
         setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, (const char *)&value,
                    sizeof(value)) == 0;
#else
  struct timeval value = { timeout_ms / 1000, (timeout_ms % 1000) * 1000 };
  return setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &value,
                    sizeof(value)) == 0 &&
         setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &value,
                    sizeof(value)) == 0;
#endif
}

MOONBIT_FFI_EXPORT int64_t edgeweaver_socket_listen(int32_t port) {
  if (!ew_init() || port < 0 || port > 65535) return -1;
  ew_socket listener = socket(AF_INET, SOCK_STREAM, 0);
  if (listener == EW_INVALID) return -1;
  int reuse = 1;
  setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, (const char *)&reuse,
             sizeof(reuse));
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(listener, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
      listen(listener, 8) != 0) {
    ew_close(listener);
    return -1;
  }
  return ew_handle(listener);
}

MOONBIT_FFI_EXPORT int32_t edgeweaver_socket_bound_port(int64_t raw) {
  if (raw < 0) return -1;
  struct sockaddr_in addr;
#ifdef _WIN32
  int length = sizeof(addr);
#else
  socklen_t length = sizeof(addr);
#endif
  if (getsockname(ew_socket_of(raw), (struct sockaddr *)&addr,
                  &length) != 0) return -1;
  return (int32_t)ntohs(addr.sin_port);
}

MOONBIT_FFI_EXPORT int64_t edgeweaver_socket_accept(int64_t raw,
                                                     int32_t timeout_ms) {
  if (raw < 0 || timeout_ms <= 0) return -1;
  ew_socket listener = ew_socket_of(raw);
  if (!ew_wait(listener, timeout_ms, 0)) return -1;
  ew_socket client = accept(listener, NULL, NULL);
  if (client == EW_INVALID) return -1;
  if (!ew_set_timeout(client, timeout_ms)) {
    ew_close(client);
    return -1;
  }
  return ew_handle(client);
}

MOONBIT_FFI_EXPORT int64_t edgeweaver_socket_connect(int32_t port,
                                                      int32_t timeout_ms) {
  if (!ew_init() || port <= 0 || port > 65535 || timeout_ms <= 0) return -1;
  ew_socket client = socket(AF_INET, SOCK_STREAM, 0);
  if (client == EW_INVALID) return -1;
#ifdef _WIN32
  u_long nonblocking = 1;
  if (ioctlsocket(client, FIONBIO, &nonblocking) != 0) {
#else
  int flags = fcntl(client, F_GETFL, 0);
  if (flags < 0 || fcntl(client, F_SETFL, flags | O_NONBLOCK) != 0) {
#endif
    ew_close(client);
    return -1;
  }
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  int result = connect(client, (struct sockaddr *)&addr, sizeof(addr));
  if (result != 0) {
#ifdef _WIN32
    if (WSAGetLastError() != WSAEWOULDBLOCK) {
#else
    if (errno != EINPROGRESS) {
#endif
      ew_close(client);
      return -1;
    }
    if (!ew_wait(client, timeout_ms, 1)) {
      ew_close(client);
      return -1;
    }
    int error = 0;
#ifdef _WIN32
    int error_size = sizeof(error);
#else
    socklen_t error_size = sizeof(error);
#endif
    if (getsockopt(client, SOL_SOCKET, SO_ERROR, (char *)&error,
                   &error_size) != 0 || error != 0) {
      ew_close(client);
      return -1;
    }
  }
#ifdef _WIN32
  nonblocking = 0;
  if (ioctlsocket(client, FIONBIO, &nonblocking) != 0) {
#else
  if (fcntl(client, F_SETFL, flags) != 0) {
#endif
    ew_close(client);
    return -1;
  }
  if (!ew_set_timeout(client, timeout_ms)) {
    ew_close(client);
    return -1;
  }
  return ew_handle(client);
}

static int ew_send_exact(ew_socket socket, const unsigned char *data,
                         size_t length) {
  size_t sent = 0;
  while (sent < length) {
#ifdef MSG_NOSIGNAL
    int flags = MSG_NOSIGNAL;
#else
    int flags = 0;
#endif
    int chunk = send(socket, (const char *)data + sent,
                     (int)(length - sent), flags);
    if (chunk <= 0) return 0;
    sent += (size_t)chunk;
  }
  return 1;
}

static int ew_read_exact(ew_socket socket, unsigned char *data, size_t length) {
  size_t received = 0;
  while (received < length) {
    int chunk = recv(socket, (char *)data + received,
                     (int)(length - received), 0);
    if (chunk <= 0) return 0;
    received += (size_t)chunk;
  }
  return 1;
}

MOONBIT_FFI_EXPORT int32_t edgeweaver_socket_write(int64_t raw,
                                                    moonbit_bytes_t data) {
  if (raw < 0) return 0;
  size_t length = Moonbit_array_length(data);
  if (length == 0 || length > EW_MAX_FRAME) return 0;
  unsigned char header[4] = {
      (unsigned char)(length >> 24), (unsigned char)(length >> 16),
      (unsigned char)(length >> 8), (unsigned char)length };
  ew_socket socket = ew_socket_of(raw);
  return ew_send_exact(socket, header, 4) &&
         ew_send_exact(socket, data, length);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t edgeweaver_socket_read(int64_t raw) {
  if (raw < 0) return moonbit_make_bytes(0, 0);
  ew_socket socket = ew_socket_of(raw);
  unsigned char header[4];
  if (!ew_read_exact(socket, header, 4)) return moonbit_make_bytes(0, 0);
  uint32_t length = ((uint32_t)header[0] << 24) |
                    ((uint32_t)header[1] << 16) |
                    ((uint32_t)header[2] << 8) | header[3];
  if (length == 0 || length > EW_MAX_FRAME) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  if (!ew_read_exact(socket, result, length)) {
    moonbit_decref(result);
    return moonbit_make_bytes(0, 0);
  }
  return result;
}

MOONBIT_FFI_EXPORT void edgeweaver_socket_close(int64_t raw) {
  if (raw >= 0) ew_close(ew_socket_of(raw));
}
