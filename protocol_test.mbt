///|
fn protocol_timestamp() -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=1_700_000_100)
}

///|
fn protocol_node_id() -> @edgeweaver.NodeId raise @edgeweaver.NodeError {
  @edgeweaver.NodeId::new(value="node-protocol")
}

///|
test "common envelope carries all supported payload categories" {
  let version = @edgeweaver.ProtocolVersion::current()
  let node_id = try! protocol_node_id()
  let timestamp = try! protocol_timestamp()
  let telemetry = try! @edgeweaver.MessageEnvelope::new(
    version~,
    message_id="msg-telemetry-001",
    node_id~,
    created_at=timestamp,
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry("temperature=21.5"),
  )
  let command = try! @edgeweaver.MessageEnvelope::new(
    version~,
    message_id="msg-command-001",
    node_id~,
    created_at=timestamp,
    correlation_id=Some("request-001"),
    payload=@edgeweaver.MessagePayload::Command("restart-sensor"),
  )
  let result = try! @edgeweaver.MessageEnvelope::new(
    version~,
    message_id="msg-result-001",
    node_id~,
    created_at=timestamp,
    correlation_id=Some("request-001"),
    payload=@edgeweaver.MessagePayload::CommandResult("accepted"),
  )
  assert_eq(telemetry.version, version)
  assert_eq(telemetry.node_id, node_id)
  assert_eq(telemetry.created_at, timestamp)
  assert_eq(telemetry.correlation_id, None)
  assert_eq(
    telemetry.payload,
    @edgeweaver.MessagePayload::Telemetry("temperature=21.5"),
  )
  assert_eq(
    command.payload,
    @edgeweaver.MessagePayload::Command("restart-sensor"),
  )
  assert_eq(
    result.payload,
    @edgeweaver.MessagePayload::CommandResult("accepted"),
  )
  assert_eq(result.correlation_id, Some("request-001"))
}

///|
test "unknown protocol versions are rejected explicitly" {
  let unknown = try! @edgeweaver.ProtocolVersion::new(major=2, minor=0)
  try unknown.ensure_supported() catch {
    @edgeweaver.ProtocolError::UnsupportedVersion(version) => {
      assert_eq(version.major, 2)
      assert_eq(version.minor, 0)
    }
    _ => fail("wrong protocol error")
  } noraise {
    _ => fail("expected an unsupported version rejection")
  }
  let node_id = try! protocol_node_id()
  let timestamp = try! protocol_timestamp()
  try
    @edgeweaver.MessageEnvelope::new(
      version=unknown,
      message_id="msg-unknown-version",
      node_id~,
      created_at=timestamp,
      correlation_id=None,
      payload=@edgeweaver.MessagePayload::Telemetry("sample"),
    )
  catch {
    @edgeweaver.ProtocolError::UnsupportedVersion(_) => ()
    _ => fail("wrong protocol error")
  } noraise {
    _ => fail("expected envelope version rejection")
  }
}

///|
test "envelope validation rejects empty identifiers and payloads" {
  let version = @edgeweaver.ProtocolVersion::current()
  let node_id = try! protocol_node_id()
  let timestamp = try! protocol_timestamp()
  try
    @edgeweaver.MessageEnvelope::new(
      version~,
      message_id="",
      node_id~,
      created_at=timestamp,
      correlation_id=None,
      payload=@edgeweaver.MessagePayload::Telemetry("sample"),
    )
  catch {
    @edgeweaver.ProtocolError::EmptyMessageId => ()
    _ => fail("wrong protocol error")
  } noraise {
    _ => fail("expected an empty message ID rejection")
  }
  try
    @edgeweaver.MessageEnvelope::new(
      version~,
      message_id="msg-empty-payload",
      node_id~,
      created_at=timestamp,
      correlation_id=Some("request-002"),
      payload=@edgeweaver.MessagePayload::Command(""),
    )
  catch {
    @edgeweaver.ProtocolError::EmptyPayload => ()
    _ => fail("wrong protocol error")
  } noraise {
    _ => fail("expected an empty payload rejection")
  }
  try
    @edgeweaver.MessageEnvelope::new(
      version~,
      message_id="msg-empty-correlation",
      node_id~,
      created_at=timestamp,
      correlation_id=Some(""),
      payload=@edgeweaver.MessagePayload::CommandResult("failed"),
    )
  catch {
    @edgeweaver.ProtocolError::EmptyCorrelationId => ()
    _ => fail("wrong protocol error")
  } noraise {
    _ => fail("expected an empty correlation ID rejection")
  }
}

///|
test "negative protocol versions are invalid" {
  try @edgeweaver.ProtocolVersion::new(major=-1, minor=0) catch {
    @edgeweaver.ProtocolError::InvalidVersion => ()
    _ => fail("wrong protocol error")
  } noraise {
    _ => fail("expected an invalid version rejection")
  }
}
