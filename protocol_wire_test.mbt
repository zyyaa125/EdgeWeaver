///|
test "wire format round trips all eight message categories" {
  let at = try! @edgeweaver.Timestamp::new(unix_seconds=40)
  let node_id = try! @edgeweaver.NodeId::new(value="wire-node")
  let event = try! @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id="wire-event",
    node_id~,
    created_at=at,
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("sample=1"),
  )
  let config = try! @edgeweaver.ConfigSnapshot::new(
    version=try! @edgeweaver.ConfigVersion::new(value=1),
    content="mode=safe",
    created_at=at,
  )
  let messages : Array[@edgeweaver.WireMessage] = [
    @edgeweaver.WireMessage::Handshake([
      @edgeweaver.TransportCapability::EventReplay,
    ]),
    @edgeweaver.WireMessage::Enroll(
      "wire-node",
      [@edgeweaver.NodeCapability::Telemetry],
      at,
    ),
    @edgeweaver.WireMessage::Heartbeat(
      "wire-node",
      @edgeweaver.NodeHealth::Healthy,
      at,
    ),
    @edgeweaver.WireMessage::ConfigUpdate("wire-node", config),
    @edgeweaver.WireMessage::Command("wire-node", "cmd-1", "read", at),
    @edgeweaver.WireMessage::EventReplay(event),
    @edgeweaver.WireMessage::Receipt(
      "wire-event",
      @edgeweaver.WireAckStatus::Duplicate,
    ),
    @edgeweaver.WireMessage::ErrorResponse("invalid", "bad request"),
  ]
  for message in messages {
    let frame = @edgeweaver.WireFrame::{
      version: @edgeweaver.ProtocolVersion::current(),
      message,
    }
    let encoded = try! @edgeweaver.encode_wire(frame)
    let decoded = try! @edgeweaver.decode_wire(encoded)
    assert_eq(try! @edgeweaver.encode_wire(decoded), encoded)
  }
}

///|
test "wire decoder rejects unknown type, invalid payload and version" {
  for
    content in [
      "{\"version\":{\"major\":1,\"minor\":0},\"message\":{\"Future\":[]}}", "{\"version\":{\"major\":1,\"minor\":0}}",
    ] {
    try @edgeweaver.decode_wire(content) catch {
      @edgeweaver.WireError::InvalidData => ()
      _ => fail("wrong malformed wire error")
    } noraise {
      _ => fail("malformed wire accepted")
    }
  }
  let at = try! @edgeweaver.Timestamp::new(unix_seconds=1)
  let invalid = @edgeweaver.WireFrame::{
    version: @edgeweaver.ProtocolVersion::current(),
    message: @edgeweaver.WireMessage::Heartbeat(
      "",
      @edgeweaver.NodeHealth::Healthy,
      at,
    ),
  }
  try @edgeweaver.decode_wire(@json.to_json(invalid).stringify()) catch {
    @edgeweaver.WireError::InvalidData => ()
    _ => fail("wrong invalid payload error")
  } noraise {
    _ => fail("empty identity accepted")
  }
  let future = @edgeweaver.WireFrame::{
    version: try! @edgeweaver.ProtocolVersion::new(major=2, minor=0),
    message: @edgeweaver.WireMessage::ErrorResponse("code", "reason"),
  }
  try @edgeweaver.decode_wire(@json.to_json(future).stringify()) catch {
    @edgeweaver.WireError::UnsupportedVersion => ()
    _ => fail("wrong version error")
  } noraise {
    _ => fail("future version accepted")
  }
}

///|
test "wire decoder rejects unknown object fields" {
  for
    content in [
      "{\"version\":{\"major\":1,\"minor\":0},\"message\":{\"ErrorResponse\":[\"code\",\"reason\"]},\"future\":true}",
      "{\"version\":{\"major\":1,\"minor\":0,\"future\":7},\"message\":{\"ErrorResponse\":[\"code\",\"reason\"]}}",
    ] {
    try @edgeweaver.decode_wire(content) catch {
      @edgeweaver.WireError::InvalidData => ()
      _ => fail("wrong unknown field error")
    } noraise {
      _ => fail("unknown wire field accepted")
    }
  }
}

///|
test "wire decoder rejects frames beyond the fixed size limit" {
  let oversized = "x".repeat(@edgeweaver.wire_max_bytes() + 1)
  try @edgeweaver.decode_wire(oversized) catch {
    @edgeweaver.WireError::TooLarge => ()
    _ => fail("wrong wire size error")
  } noraise {
    _ => fail("oversized frame accepted")
  }
}
