///|
fn sample_timestamp() -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=1_700_000_000)
}

///|
test "node starts new with identity capabilities and timestamps" {
  let timestamp = try! sample_timestamp()
  let node = try! @edgeweaver.Node::new(
    id="node-001",
    capabilities=[
      @edgeweaver.NodeCapability::Telemetry,
      @edgeweaver.NodeCapability::PersistentStorage,
    ],
    created_at=timestamp,
  )
  assert_eq(node.id.value, "node-001")
  assert_eq(node.lifecycle, @edgeweaver.NodeLifecycle::New)
  assert_eq(node.health, @edgeweaver.NodeHealth::Unknown)
  assert_true(node.supports(capability=@edgeweaver.NodeCapability::Telemetry))
  assert_true(
    node.supports(capability=@edgeweaver.NodeCapability::PersistentStorage),
  )
  assert_false(
    node.supports(capability=@edgeweaver.NodeCapability::CommandExecution),
  )
  assert_eq(node.created_at, timestamp)
  assert_eq(node.updated_at, timestamp)
}

///|
test "node accepts enrollment online offline and retirement transitions" {
  let initial = try! sample_timestamp()
  let enrolled_at = try! @edgeweaver.Timestamp::new(unix_seconds=1_700_000_001)
  let online_at = try! @edgeweaver.Timestamp::new(unix_seconds=1_700_000_002)
  let offline_at = try! @edgeweaver.Timestamp::new(unix_seconds=1_700_000_003)
  let retired_at = try! @edgeweaver.Timestamp::new(unix_seconds=1_700_000_004)
  let node = try! @edgeweaver.Node::new(
    id="node-002",
    capabilities=[],
    created_at=initial,
  )
  let enrolled = try! node.transition(
    target=@edgeweaver.NodeLifecycle::Enrolled,
    at=enrolled_at,
  )
  let online = try! enrolled.transition(
    target=@edgeweaver.NodeLifecycle::Online,
    at=online_at,
  )
  let offline = try! online.transition(
    target=@edgeweaver.NodeLifecycle::Offline,
    at=offline_at,
  )
  let retired = try! offline.transition(
    target=@edgeweaver.NodeLifecycle::Retired,
    at=retired_at,
  )
  assert_eq(retired.lifecycle, @edgeweaver.NodeLifecycle::Retired)
  assert_eq(retired.updated_at, retired_at)
}

///|
test "node rejects illegal transitions and stale timestamps" {
  let initial = try! sample_timestamp()
  let node = try! @edgeweaver.Node::new(
    id="node-003",
    capabilities=[],
    created_at=initial,
  )
  try
    node.transition(target=@edgeweaver.NodeLifecycle::Online, at=initial)
  catch {
    @edgeweaver.NodeError::InvalidTransition(message) =>
      inspect(message, content="lifecycle transition is not allowed")
    _ => fail("wrong node error")
  } noraise {
    _ => fail("expected an illegal transition")
  }
  let older = try! @edgeweaver.Timestamp::new(unix_seconds=1_699_999_999)
  try
    node.transition(target=@edgeweaver.NodeLifecycle::Enrolled, at=older)
  catch {
    @edgeweaver.NodeError::InvalidTimestamp => ()
    _ => fail("wrong node error")
  } noraise {
    _ => fail("expected a stale timestamp rejection")
  }
}

///|
test "retired node cannot receive health updates" {
  let initial = try! sample_timestamp()
  let retired_at = try! @edgeweaver.Timestamp::new(unix_seconds=1_700_000_001)
  let node = try! @edgeweaver.Node::new(
    id="node-004",
    capabilities=[],
    created_at=initial,
  )
  let retired = try! node.transition(
    target=@edgeweaver.NodeLifecycle::Retired,
    at=retired_at,
  )
  try
    retired.record_health(health=@edgeweaver.NodeHealth::Healthy, at=retired_at)
  catch {
    @edgeweaver.NodeError::InvalidHealthUpdate => ()
    _ => fail("wrong node error")
  } noraise {
    _ => fail("expected a retired health update rejection")
  }
}

///|
test "node identity and timestamp constructors reject invalid input" {
  let timestamp = try! sample_timestamp()
  try @edgeweaver.NodeId::new(value="") catch {
    @edgeweaver.NodeError::EmptyNodeId => ()
    _ => fail("wrong node error")
  } noraise {
    _ => fail("expected an empty ID rejection")
  }
  try @edgeweaver.Timestamp::new(unix_seconds=-1) catch {
    @edgeweaver.NodeError::InvalidTimestamp => ()
    _ => fail("wrong node error")
  } noraise {
    _ => fail("expected a negative timestamp rejection")
  }
  try
    @edgeweaver.Node::new(id="", capabilities=[], created_at=timestamp)
  catch {
    @edgeweaver.NodeError::EmptyNodeId => ()
    _ => fail("wrong node error")
  } noraise {
    _ => fail("expected an empty node ID rejection")
  }
}
