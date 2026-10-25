///|
suberror ServiceError {
  InvalidConfig
  InvalidDataDirectory
  WrongRole
} derive(Debug)

///|
struct ServiceConfig {
  format : Int32
  role : String
  data_dir : String
  port : Int32
  timeout_ms : Int32
  poll_ms : Int32
} derive(FromJson)

///|
pub extend ServiceConfig with @json.FromJson::{from_json}

///|
#borrow(path)
extern "c" fn service_read_config(path : Bytes) -> Bytes = "edgeweaver_service_read_config"

///|
#borrow(path)
extern "c" fn service_check_dir(path : Bytes) -> Int32 = "edgeweaver_service_check_dir"

///|
extern "c" fn service_exit(code : Int32) -> Unit = "edgeweaver_service_exit"

///|
extern "c" fn service_unbuffer_stdout() -> Unit = "edgeweaver_service_unbuffer_stdout"

///|
fn report_service_error(error : Error) -> Unit {
  match error {
    ServiceError::InvalidConfig => {
      println("service startup error: invalid config")
      service_exit(2)
    }
    ServiceError::WrongRole => {
      println("service startup error: role mismatch")
      service_exit(2)
    }
    ServiceError::InvalidDataDirectory => {
      println("service startup error: unsafe data directory")
      service_exit(2)
    }
    _ => {
      println("service runtime error")
      service_exit(3)
    }
  }
}

///|
fn parse_service_config(
  text : String,
  expected_role : String,
) -> ServiceConfig raise ServiceError {
  let json = @json.parse(text) catch { _ => raise ServiceError::InvalidConfig }
  let config : ServiceConfig = @json.from_json(json) catch {
    _ => raise ServiceError::InvalidConfig
  }
  if config.role != expected_role {
    raise ServiceError::WrongRole
  }
  if config.format != 1 ||
    config.port <= 0 ||
    config.port > 65535 ||
    config.timeout_ms < 100 ||
    config.timeout_ms > 300000 ||
    config.poll_ms < 1000 ||
    config.poll_ms > 10000 ||
    !config.data_dir.has_prefix("/".view()) ||
    config.data_dir == "/" ||
    config.data_dir.contains("..".view()) ||
    config.data_dir.contains("\n".view()) {
    raise ServiceError::InvalidConfig
  }
  config
}

///|
fn load_service_config(
  path : String,
  expected_role : String,
) -> ServiceConfig raise ServiceError {
  let bytes = service_read_config(@utf8.encode(path))
  if bytes.length() == 0 {
    raise ServiceError::InvalidConfig
  }
  let text = @utf8.decode(bytes) catch {
    _ => raise ServiceError::InvalidConfig
  }
  let config = parse_service_config(text, expected_role)
  if service_check_dir(@utf8.encode(config.data_dir)) != 1 ||
    service_check_dir(@utf8.encode(config.data_dir + "/events")) != 1 {
    raise ServiceError::InvalidDataDirectory
  }
  config
}

///|
fn run_control_service(config_path : String) -> Unit raise {
  let config = load_service_config(config_path, "control")
  let receipt_path = config.data_dir + "/events/receipts.json"
  let listener = @network.listen(config.port)
  let control = @edgeweaver.ControlPlane::new()
  println("control ready on 127.0.0.1:" + config.port.to_string())
  while true {
    let socket = listener.accept(timeout_ms=config.timeout_ms) catch {
      @network.NetworkError::AcceptTimeout => continue
      error => raise error
    }
    serve_session(socket, control, receipt_path) catch {
      _ => println("control session rejected")
    }
    socket.close()
  }
}

///|
fn run_node_service(config_path : String) -> Unit raise {
  let config = load_service_config(config_path, "node")
  let checkpoint_path = config.data_dir + "/events/checkpoint.json"
  println("node replay service ready")
  while true {
    match @disk.load_checkpoint_if_exists(checkpoint_path) {
      Some(store) if store.pending_count() > 0 =>
        drain_events(config.port, checkpoint_path, config.timeout_ms) catch {
          NetworkDemoError::ReconnectExhausted => println("node sync deferred")
          error => raise error
        }
      _ => ()
    }
    @network.pause(config.poll_ms)
  }
}
