///|
test "native loopback exchanges framed messages and times out" {
  let listener = try! listen(0)
  let port = listener.port()
  assert_true(port > 0)
  let client = try! connect(port, timeout_ms=500)
  let server = try! listener.accept(timeout_ms=500)
  let request = @edgeweaver.WireFrame::{
    version: @edgeweaver.ProtocolVersion::current(),
    message: @edgeweaver.WireMessage::Handshake([
      @edgeweaver.TransportCapability::EventReplay,
    ]),
  }
  client.send(request)
  match (try! server.receive()).message {
    @edgeweaver.WireMessage::Handshake(capabilities) =>
      assert_eq(capabilities.length(), 1)
    _ => fail("wrong request frame")
  }
  let response = @edgeweaver.WireFrame::{
    version: @edgeweaver.ProtocolVersion::current(),
    message: @edgeweaver.WireMessage::Receipt(
      "event-1",
      @edgeweaver.WireAckStatus::Accepted,
    ),
  }
  server.send(response)
  match (try! client.receive()).message {
    @edgeweaver.WireMessage::Receipt(id, _) => assert_eq(id, "event-1")
    _ => fail("wrong response frame")
  }
  try server.receive() catch {
    NetworkError::ReadFailed => ()
    _ => fail("wrong timeout error")
  } noraise {
    _ => fail("idle socket read succeeded")
  }
  client.close()
  server.close()
  listener.close()
}

///|
test "native pause rejects unbounded reconnect waits" {
  for milliseconds in [-1, 10001] {
    try pause(milliseconds) catch {
      NetworkError::InvalidTimeout => ()
      _ => fail("wrong delay validation error")
    } noraise {
      _ => fail("unbounded pause accepted")
    }
  }
}
