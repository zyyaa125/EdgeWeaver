///|
fn delivery_time(
  seconds : Int,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
fn delivery_plane() -> @edgeweaver.ControlPlane {
  let plane = @edgeweaver.ControlPlane::new()
  let _ = try! plane.enroll(
    request=try! @edgeweaver.EnrollmentRequest::new(
      version=@edgeweaver.ProtocolVersion::current(),
      node_id="node-delivery",
      capabilities=[@edgeweaver.NodeCapability::CommandExecution],
      at=try! delivery_time(10),
    ),
  )
  plane
}

///|
test "control delivers only newer configuration versions" {
  let plane = delivery_plane()
  let node_id = try! @edgeweaver.NodeId::new(value="node-delivery")
  let first = try! @edgeweaver.ConfigSnapshot::new(
    version=try! @edgeweaver.ConfigVersion::new(value=1),
    content="mode=standby",
    created_at=try! delivery_time(20),
  )
  let first_delivery = try! plane.deliver_config(
    node_id~,
    snapshot=first,
    at=try! delivery_time(21),
  )
  assert_eq(first_delivery.snapshot.version.value, 1)
  let second = try! @edgeweaver.ConfigSnapshot::new(
    version=try! @edgeweaver.ConfigVersion::new(value=2),
    content="mode=active",
    created_at=try! delivery_time(30),
  )
  let second_delivery = try! plane.deliver_config(
    node_id~,
    snapshot=second,
    at=try! delivery_time(31),
  )
  assert_eq(second_delivery.snapshot.version.value, 2)
  assert_eq(second_delivery.delivered_at.unix_seconds, 31)
  match plane.config(node_id~) {
    Some(delivery) => assert_eq(delivery.snapshot.content, "mode=active")
    None => fail("expected delivered configuration")
  }
  try
    plane.deliver_config(node_id~, snapshot=first, at=try! delivery_time(32))
  catch {
    @edgeweaver.ControlError::StaleConfig(version) =>
      assert_eq(version.value, 2)
    _ => fail("wrong stale configuration error")
  } noraise {
    _ => fail("expected stale configuration rejection")
  }
}

///|
test "control tracks command delivery and completion result" {
  let plane = delivery_plane()
  let node_id = try! @edgeweaver.NodeId::new(value="node-delivery")
  let config_version = try! @edgeweaver.ConfigVersion::new(value=2)
  let command = try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value="command-001"),
    node_id~,
    action=@edgeweaver.CommandAction::ApplyConfig(config_version),
    issued_at=try! delivery_time(20),
    expires_at=try! delivery_time(100),
  )
  let pending = try! plane.deliver_command(node_id~, command~)
  assert_eq(pending.state, @edgeweaver.CommandState::Pending)
  let accepted = try! plane.update_command(
    command_id=pending.id,
    update=@edgeweaver.CommandUpdate::Accept,
    at=try! delivery_time(30),
  )
  let running = try! plane.update_command(
    command_id=accepted.id,
    update=@edgeweaver.CommandUpdate::Start,
    at=try! delivery_time(40),
  )
  let completed = try! plane.update_command(
    command_id=running.id,
    update=@edgeweaver.CommandUpdate::Succeed("configuration applied"),
    at=try! delivery_time(50),
  )
  assert_eq(completed.state, @edgeweaver.CommandState::Succeeded)
  match completed.result {
    Some(result) => assert_eq(result.message, "configuration applied")
    None => fail("expected command result")
  }
  match plane.command(command_id=completed.id) {
    Some(command) =>
      assert_eq(command.state, @edgeweaver.CommandState::Succeeded)
    None => fail("expected tracked command")
  }
  try plane.deliver_command(node_id~, command~) catch {
    @edgeweaver.ControlError::DuplicateCommand(command_id) =>
      assert_eq(command_id.value, "command-001")
    _ => fail("wrong duplicate command error")
  } noraise {
    _ => fail("expected duplicate command rejection")
  }
}

///|
test "control rejects command target mismatch and invalid lifecycle update" {
  let plane = delivery_plane()
  let node_id = try! @edgeweaver.NodeId::new(value="node-delivery")
  let other_id = try! @edgeweaver.NodeId::new(value="node-other")
  let command = try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value="command-mismatch"),
    node_id=other_id,
    action=@edgeweaver.CommandAction::ReadTelemetry,
    issued_at=try! delivery_time(20),
    expires_at=try! delivery_time(100),
  )
  try plane.deliver_command(node_id~, command~) catch {
    @edgeweaver.ControlError::CommandTargetMismatch(command_id) =>
      assert_eq(command_id.value, "command-mismatch")
    _ => fail("wrong command target error")
  } noraise {
    _ => fail("expected command target mismatch")
  }

  let valid = try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value="command-invalid"),
    node_id~,
    action=@edgeweaver.CommandAction::ReadTelemetry,
    issued_at=try! delivery_time(20),
    expires_at=try! delivery_time(100),
  )
  let pending = try! plane.deliver_command(node_id~, command=valid)
  try
    plane.update_command(
      command_id=pending.id,
      update=@edgeweaver.CommandUpdate::Succeed("too early"),
      at=try! delivery_time(30),
    )
  catch {
    @edgeweaver.ControlError::CommandTransition(
      @edgeweaver.CommandError::InvalidTransition(_)
    ) => ()
    _ => fail("wrong command transition error")
  } noraise {
    _ => fail("expected invalid command transition")
  }

  let missing_id = try! @edgeweaver.CommandId::new(value="command-missing")
  try
    plane.update_command(
      command_id=missing_id,
      update=@edgeweaver.CommandUpdate::Accept,
      at=try! delivery_time(30),
    )
  catch {
    @edgeweaver.ControlError::UnknownCommand(command_id) =>
      assert_eq(command_id.value, "command-missing")
    _ => fail("wrong unknown command error")
  } noraise {
    _ => fail("expected unknown command rejection")
  }
}

///|
test "control records command expiry" {
  let plane = delivery_plane()
  let node_id = try! @edgeweaver.NodeId::new(value="node-delivery")
  let command = try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value="command-expire"),
    node_id~,
    action=@edgeweaver.CommandAction::ReadTelemetry,
    issued_at=try! delivery_time(20),
    expires_at=try! delivery_time(40),
  )
  let pending = try! plane.deliver_command(node_id~, command~)
  let expired = try! plane.update_command(
    command_id=pending.id,
    update=@edgeweaver.CommandUpdate::Expire,
    at=try! delivery_time(40),
  )
  assert_eq(expired.state, @edgeweaver.CommandState::Expired)
  assert_true(expired.result is Some(_))
}
