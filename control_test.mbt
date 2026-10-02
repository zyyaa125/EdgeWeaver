///|
fn control_time(
  seconds : Int,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
test "enrollment and heartbeat update the registered node lifecycle" {
  let plane = @edgeweaver.ControlPlane::new()
  let enrolled = try! plane.enroll(
    request=try! @edgeweaver.EnrollmentRequest::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id="node-control",
      capabilities=[
        @edgeweaver.NodeCapability::Telemetry,
        @edgeweaver.NodeCapability::CommandExecution,
      ],
      at=try! control_time(10),
    ),
  )
  assert_eq(enrolled.lifecycle, @edgeweaver.NodeLifecycle::Enrolled)
  assert_eq(enrolled.health, @edgeweaver.NodeHealth::Unknown)
  assert_true(
    enrolled.supports(capability=@edgeweaver.NodeCapability::Telemetry),
  )

  let online = try! plane.receive_heartbeat(
    heartbeat=try! @edgeweaver.Heartbeat::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id="node-control",
      health=@edgeweaver.NodeHealth::Healthy,
      at=try! control_time(20),
    ),
  )
  assert_eq(online.lifecycle, @edgeweaver.NodeLifecycle::Online)
  assert_eq(online.health, @edgeweaver.NodeHealth::Healthy)
  assert_eq(online.updated_at.unix_seconds, 20)

  let offline = try! plane.mark_offline(
    node_id=online.id,
    at=try! control_time(30),
  )
  assert_eq(offline.lifecycle, @edgeweaver.NodeLifecycle::Offline)

  let recovered = try! plane.receive_heartbeat(
    heartbeat=try! @edgeweaver.Heartbeat::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id="node-control",
      health=@edgeweaver.NodeHealth::Degraded,
      at=try! control_time(40),
    ),
  )
  assert_eq(recovered.lifecycle, @edgeweaver.NodeLifecycle::Online)
  assert_eq(recovered.health, @edgeweaver.NodeHealth::Degraded)
  match plane.lookup(node_id=recovered.id) {
    Some(node) => assert_eq(node.updated_at.unix_seconds, 40)
    None => fail("expected enrolled node in registry")
  }
}

///|
test "control rejects invalid identity protocol and duplicate enrollment" {
  try
    @edgeweaver.EnrollmentRequest::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id="",
      capabilities=[],
      at=try! control_time(1),
    )
  catch {
    @edgeweaver.ControlError::EmptyNodeId => ()
    _ => fail("wrong control error")
  } noraise {
    _ => fail("expected empty node ID rejection")
  }

  let plane = @edgeweaver.ControlPlane::new()
  let request = try! @edgeweaver.EnrollmentRequest::new(
    version=@edgeweaver.ProtocolVersion::current(),
    node_id="node-duplicate",
    capabilities=[],
    at=try! control_time(2),
  )
  let _ = try! plane.enroll(request~)
  try plane.enroll(request~) catch {
    @edgeweaver.ControlError::DuplicateNode(node_id) =>
      assert_eq(node_id.value, "node-duplicate")
    _ => fail("wrong duplicate enrollment error")
  } noraise {
    _ => fail("expected duplicate enrollment rejection")
  }

  let unsupported = try! @edgeweaver.EnrollmentRequest::new(
    version=try! @edgeweaver.ProtocolVersion::new(major=2, minor=0),
    node_id="node-unsupported",
    capabilities=[],
    at=try! control_time(3),
  )
  try plane.enroll(request=unsupported) catch {
    @edgeweaver.ControlError::UnsupportedProtocol(version) => {
      assert_eq(version.major, 2)
      assert_eq(version.minor, 0)
    }
    _ => fail("wrong protocol rejection")
  } noraise {
    _ => fail("expected unsupported protocol rejection")
  }
}

///|
test "heartbeat rejects unknown and stale observations" {
  let plane = @edgeweaver.ControlPlane::new()
  let unknown = try! @edgeweaver.Heartbeat::new(
    version=@edgeweaver.ProtocolVersion::current(),
    node_id="node-missing",
    health=@edgeweaver.NodeHealth::Healthy,
    at=try! control_time(10),
  )
  try plane.receive_heartbeat(heartbeat=unknown) catch {
    @edgeweaver.ControlError::UnknownNode(node_id) =>
      assert_eq(node_id.value, "node-missing")
    _ => fail("wrong unknown node error")
  } noraise {
    _ => fail("expected unknown node rejection")
  }

  let _ = try! plane.enroll(
    request=try! @edgeweaver.EnrollmentRequest::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id="node-stale",
      capabilities=[],
      at=try! control_time(20),
    ),
  )
  let _ = try! plane.receive_heartbeat(
    heartbeat=try! @edgeweaver.Heartbeat::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id="node-stale",
      health=@edgeweaver.NodeHealth::Healthy,
      at=try! control_time(30),
    ),
  )
  let stale = try! @edgeweaver.Heartbeat::new(
    version=@edgeweaver.ProtocolVersion::current(),
    node_id="node-stale",
    health=@edgeweaver.NodeHealth::Degraded,
    at=try! control_time(29),
  )
  try plane.receive_heartbeat(heartbeat=stale) catch {
    @edgeweaver.ControlError::StaleHeartbeat => ()
    _ => fail("wrong stale heartbeat error")
  } noraise {
    _ => fail("expected stale heartbeat rejection")
  }
}
