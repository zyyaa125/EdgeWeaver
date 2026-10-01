///|
fn command_time(
  seconds : Int,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
fn command_node() -> @edgeweaver.NodeId raise @edgeweaver.NodeError {
  @edgeweaver.NodeId::new(value="node-command")
}

///|
test "configuration versions and snapshots are comparable" {
  let first_version = try! @edgeweaver.ConfigVersion::new(value=1)
  let second_version = try! @edgeweaver.ConfigVersion::new(value=2)
  let first = try! @edgeweaver.ConfigSnapshot::new(
    version=first_version,
    content="mode=standby",
    created_at=try! command_time(100),
  )
  let second = try! @edgeweaver.ConfigSnapshot::new(
    version=second_version,
    content="mode=active",
    created_at=try! command_time(101),
  )
  assert_true(second.supersedes(previous=first))
  assert_false(first.supersedes(previous=second))
  try @edgeweaver.ConfigVersion::new(value=0) catch {
    @edgeweaver.ConfigError::InvalidVersion => ()
    _ => fail("wrong configuration error")
  } noraise {
    _ => fail("expected an invalid configuration version")
  }
}

///|
test "command lifecycle records a successful result" {
  let id = try! @edgeweaver.CommandId::new(value="command-001")
  let node_id = try! command_node()
  let action = @edgeweaver.CommandAction::ReadTelemetry
  let issued = try! command_time(100)
  let expires = try! command_time(110)
  let accepted_at = try! command_time(101)
  let started_at = try! command_time(102)
  let completed_at = try! command_time(103)
  let command = try! @edgeweaver.Command::new(
    id~,
    node_id~,
    action~,
    issued_at=issued,
    expires_at=expires,
  )
  let accepted = try! command.accept(at=accepted_at)
  let running = try! accepted.start(at=started_at)
  let succeeded = try! running.succeed(
    at=completed_at,
    message="telemetry read",
  )
  assert_eq(succeeded.state, @edgeweaver.CommandState::Succeeded)
  assert_eq(succeeded.updated_at, completed_at)
  match succeeded.result {
    Some(result) => {
      assert_eq(result.state, @edgeweaver.CommandState::Succeeded)
      assert_eq(result.message, "telemetry read")
      assert_eq(result.completed_at, completed_at)
    }
    None => fail("expected a command result")
  }
}

///|
test "command IDs define duplicate request identity" {
  let first_id = try! @edgeweaver.CommandId::new(value="duplicate-001")
  let second_id = try! @edgeweaver.CommandId::new(value="duplicate-001")
  let node_id = try! command_node()
  let issued = try! command_time(200)
  let expires = try! command_time(210)
  let first = try! @edgeweaver.Command::new(
    id=first_id,
    node_id~,
    action=@edgeweaver.CommandAction::Execute("sync"),
    issued_at=issued,
    expires_at=expires,
  )
  let second = try! @edgeweaver.Command::new(
    id=second_id,
    node_id~,
    action=@edgeweaver.CommandAction::Execute("sync"),
    issued_at=issued,
    expires_at=expires,
  )
  assert_true(first.same_identity(other=second))
}

///|
test "command lifecycle rejects illegal transitions and stale results" {
  let id = try! @edgeweaver.CommandId::new(value="command-002")
  let node_id = try! command_node()
  let command = try! @edgeweaver.Command::new(
    id~,
    node_id~,
    action=@edgeweaver.CommandAction::Execute("restart"),
    issued_at=try! command_time(300),
    expires_at=try! command_time(305),
  )
  try command.start(at=try! command_time(301)) catch {
    @edgeweaver.CommandError::InvalidTransition(message) =>
      inspect(message, content="command lifecycle transition is not allowed")
    _ => fail("wrong command error")
  } noraise {
    _ => fail("expected an illegal command transition")
  }
  try
    @edgeweaver.CommandResult::new(
      state=@edgeweaver.CommandState::Running,
      message="not terminal",
      completed_at=try! command_time(301),
    )
  catch {
    @edgeweaver.CommandError::InvalidResultState => ()
    _ => fail("wrong command error")
  } noraise {
    _ => fail("expected a non-terminal result rejection")
  }
}

///|
test "command expiry records a terminal result" {
  let command = try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value="command-003"),
    node_id=try! command_node(),
    action=@edgeweaver.CommandAction::ApplyConfig(
      try! @edgeweaver.ConfigVersion::new(value=3),
    ),
    issued_at=try! command_time(400),
    expires_at=try! command_time(405),
  )
  try command.expire(at=try! command_time(404)) catch {
    @edgeweaver.CommandError::InvalidTransition(message) =>
      inspect(message, content="command has not reached its expiry")
    _ => fail("wrong command error")
  } noraise {
    _ => fail("expected an early expiry rejection")
  }
  let expired = try! command.expire(at=try! command_time(405))
  assert_eq(expired.state, @edgeweaver.CommandState::Expired)
  assert_true(expired.result is Some(_))
}
