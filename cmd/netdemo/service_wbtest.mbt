///|
test "service config validates role paths and bounded timings" {
  let good = "{\"format\":1,\"role\":\"node\",\"data_dir\":\"/tmp/edgeweaver-node\",\"port\":19077,\"timeout_ms\":500,\"poll_ms\":1000}"
  let config = try! parse_service_config(good, "node")
  assert_eq(config.port, 19077)
  assert_eq(config.data_dir, "/tmp/edgeweaver-node")
  try parse_service_config(good, "control") catch {
    ServiceError::WrongRole => ()
    _ => fail("wrong role error")
  } noraise {
    _ => fail("wrong role accepted")
  }
  for
    invalid in [
      "{\"format\":2,\"role\":\"node\",\"data_dir\":\"/tmp/edgeweaver-node\",\"port\":19077,\"timeout_ms\":500,\"poll_ms\":1000}",
      "{\"format\":1,\"role\":\"node\",\"data_dir\":\"../escape\",\"port\":19077,\"timeout_ms\":500,\"poll_ms\":1000}",
      "{\"format\":1,\"role\":\"node\",\"data_dir\":\"/tmp/edgeweaver-node\",\"port\":0,\"timeout_ms\":500,\"poll_ms\":1000}",
      "{\"format\":1,\"role\":\"node\",\"data_dir\":\"/tmp/edgeweaver-node\",\"port\":19077,\"timeout_ms\":50,\"poll_ms\":1000}",
      "{\"format\":1,\"role\":\"node\",\"data_dir\":\"/tmp/edgeweaver-node\",\"port\":19077,\"timeout_ms\":500,\"poll_ms\":100000}",
      "{\"format\":1,\"role\":\"node\",\"data_dir\":\"/tmp/edgeweaver-node\",\"port\":19077}",
    ] {
    try parse_service_config(invalid, "node") catch {
      ServiceError::InvalidConfig => ()
      _ => fail("wrong config error")
    } noraise {
      _ => fail("invalid config accepted")
    }
  }
}
