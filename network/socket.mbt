///|
/// Localhost-only native socket failures.
pub(all) suberror NetworkError {
  InvalidPort
  InvalidTimeout
  ListenFailed
  AcceptFailed
  ConnectFailed
  ReadFailed
  WriteFailed
  InvalidFrame
} derive(Debug, Eq)

///|
pub extend NetworkError with @debug.Debug::{to_repr}

///|
pub extend NetworkError with Eq::{not_equal, equal}

///|
#borrow(data)
extern "c" fn socket_write(handle : Int64, data : Bytes) -> Int32 = "edgeweaver_socket_write"

///|
extern "c" fn socket_read(handle : Int64) -> Bytes = "edgeweaver_socket_read"

///|
extern "c" fn socket_listen(port : Int32) -> Int64 = "edgeweaver_socket_listen"

///|
extern "c" fn socket_bound_port(handle : Int64) -> Int32 = "edgeweaver_socket_bound_port"

///|
extern "c" fn socket_accept(handle : Int64, timeout_ms : Int32) -> Int64 = "edgeweaver_socket_accept"

///|
extern "c" fn socket_connect(port : Int32, timeout_ms : Int32) -> Int64 = "edgeweaver_socket_connect"

///|
extern "c" fn socket_close(handle : Int64) -> Unit = "edgeweaver_socket_close"

///|
/// A single native TCP socket with bounded frame I/O.
pub struct Socket {
  mut handle : Int64
}

///|
/// A listening socket bound only to 127.0.0.1.
pub struct Listener {
  mut handle : Int64
}

///|
pub fn listen(port : Int32) -> Listener raise NetworkError {
  if port < 0 || port > 65535 {
    raise NetworkError::InvalidPort
  }
  let handle = socket_listen(port)
  if handle < 0 {
    raise NetworkError::ListenFailed
  }
  { handle, }
}

///|
/// Returns the selected local port, including an ephemeral port for listen(0).
pub fn Listener::port(self : Listener) -> Int32 {
  socket_bound_port(self.handle)
}

///|
pub fn Listener::accept(
  self : Listener,
  timeout_ms~ : Int32,
) -> Socket raise NetworkError {
  if timeout_ms <= 0 {
    raise NetworkError::InvalidTimeout
  }
  let handle = socket_accept(self.handle, timeout_ms)
  if handle < 0 {
    raise NetworkError::AcceptFailed
  }
  { handle, }
}

///|
pub fn connect(port : Int32, timeout_ms~ : Int32) -> Socket raise NetworkError {
  if port <= 0 || port > 65535 {
    raise NetworkError::InvalidPort
  }
  if timeout_ms <= 0 {
    raise NetworkError::InvalidTimeout
  }
  let handle = socket_connect(port, timeout_ms)
  if handle < 0 {
    raise NetworkError::ConnectFailed
  }
  { handle, }
}

///|
pub fn Socket::send(
  self : Socket,
  frame : @edgeweaver.WireFrame,
) -> Unit raise NetworkError {
  let text = @edgeweaver.encode_wire(frame) catch {
    _ => raise NetworkError::InvalidFrame
  }
  if socket_write(self.handle, @utf8.encode(text)) != 1 {
    raise NetworkError::WriteFailed
  }
}

///|
pub fn Socket::receive(
  self : Socket,
) -> @edgeweaver.WireFrame raise NetworkError {
  let bytes = socket_read(self.handle)
  if bytes.length() == 0 {
    raise NetworkError::ReadFailed
  }
  let text = @utf8.decode(bytes) catch { _ => raise NetworkError::InvalidFrame }
  @edgeweaver.decode_wire(text) catch {
    _ => raise NetworkError::InvalidFrame
  }
}

///|
pub fn Socket::close(self : Socket) -> Unit {
  if self.handle >= 0 {
    socket_close(self.handle)
    self.handle = -1
  }
}

///|
pub fn Listener::close(self : Listener) -> Unit {
  if self.handle >= 0 {
    socket_close(self.handle)
    self.handle = -1
  }
}
