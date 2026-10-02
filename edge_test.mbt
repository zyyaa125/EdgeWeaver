///|
fn edge_time(
  seconds : Int,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
fn edge_node(
  capabilities : Array[@edgeweaver.NodeCapability],
) -> @edgeweaver.Node {
  let created = try! edge_time(1)
  let node = try! @edgeweaver.Node::new(
    id="node-edge",
    capabilities~,
    created_at=created,
  )
  let enrolled = try! node.transition(
    target=@edgeweaver.NodeLifecycle::Enrolled,
    at=try! edge_time(2),
  )
  try! enrolled.transition(
    target=@edgeweaver.NodeLifecycle::Online,
    at=try! edge_time(3),
  )
}

///|
fn edge_command(
  id : String,
  node_id : @edgeweaver.NodeId,
  action : @edgeweaver.CommandAction,
) -> @edgeweaver.Command {
  try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value=id),
    node_id~,
    action~,
    issued_at=try! edge_time(5),
    expires_at=try! edge_time(50),
  )
}

///|
test "edge executor runs an allowlisted command once" {
  let node = edge_node([@edgeweaver.NodeCapability::CommandExecution])
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("reboot"),
  ])
  let executor = @edgeweaver.EdgeExecutor::new(node~, allowlist~)
  let command = edge_command(
    "command-reboot",
    node.id,
    @edgeweaver.CommandAction::Execute("reboot"),
  )
  let mut calls = 0
  let first = try! executor.execute(command~, at=try! edge_time(10), runner=_action => {
    calls = calls + 1
    @edgeweaver.ExecutionResult::Succeeded("reboot complete")
  })
  assert_eq(calls, 1)
  assert_eq(first.status, @edgeweaver.ExecutionStatus::Succeeded)
  assert_eq(first.command.state, @edgeweaver.CommandState::Succeeded)
  assert_eq(first.message, "reboot complete")
  let repeated = try! executor.execute(command~, at=try! edge_time(11), runner=_action => {
    calls = calls + 1
    @edgeweaver.ExecutionResult::Succeeded("should not run")
  })
  assert_eq(calls, 1)
  assert_eq(repeated, first)
}

///|
test "edge executor persists failed command results" {
  let node = edge_node([@edgeweaver.NodeCapability::CommandExecution])
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("reboot"),
  ])
  let executor = @edgeweaver.EdgeExecutor::new(node~, allowlist~)
  let command = edge_command(
    "command-failed",
    node.id,
    @edgeweaver.CommandAction::Execute("reboot"),
  )
  let mut calls = 0
  let failed = try! executor.execute(command~, at=try! edge_time(10), runner=_action => {
    calls = calls + 1
    @edgeweaver.ExecutionResult::Failed("device busy")
  })
  assert_eq(calls, 1)
  assert_eq(failed.status, @edgeweaver.ExecutionStatus::Failed)
  assert_eq(failed.command.state, @edgeweaver.CommandState::Failed)
  assert_eq(failed.message, "device busy")
  let retried = try! executor.execute(command~, at=try! edge_time(11), runner=_action => {
    calls = calls + 1
    @edgeweaver.ExecutionResult::Succeeded("should not run")
  })
  assert_eq(calls, 1)
  assert_eq(retried, failed)
}

///|
test "edge executor enforces allowlist and node capabilities" {
  let node = edge_node([@edgeweaver.NodeCapability::CommandExecution])
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("reboot"),
    @edgeweaver.AllowedAction::ReadTelemetry,
  ])
  let executor = @edgeweaver.EdgeExecutor::new(node~, allowlist~)
  let denied = edge_command(
    "command-shutdown",
    node.id,
    @edgeweaver.CommandAction::Execute("shutdown"),
  )
  try
    executor.execute(command=denied, at=try! edge_time(10), runner=_action => {
      @edgeweaver.ExecutionResult::Succeeded("unexpected")
    })
  catch {
    @edgeweaver.EdgeError::ActionNotAllowed(
      @edgeweaver.CommandAction::Execute(name)
    ) => assert_eq(name, "shutdown")
    _ => fail("wrong allowlist error")
  } noraise {
    _ => fail("expected allowlist rejection")
  }

  let telemetry = edge_command(
    "command-telemetry",
    node.id,
    @edgeweaver.CommandAction::ReadTelemetry,
  )
  try
    executor.execute(command=telemetry, at=try! edge_time(10), runner=_action => {
      @edgeweaver.ExecutionResult::Succeeded("sample")
    })
  catch {
    @edgeweaver.EdgeError::MissingCapability(capability) =>
      assert_eq(capability, @edgeweaver.NodeCapability::Telemetry)
    _ => fail("wrong capability error")
  } noraise {
    _ => fail("expected capability rejection")
  }

  try
    @edgeweaver.CommandAllowlist::new(actions=[
      @edgeweaver.AllowedAction::Execute(""),
    ])
  catch {
    @edgeweaver.EdgeError::EmptyAllowlistedAction => ()
    _ => fail("wrong allowlist construction error")
  } noraise {
    _ => fail("expected empty allowlist action rejection")
  }
}

///|
test "restored in-progress execution is not repeated" {
  let node = edge_node([@edgeweaver.NodeCapability::CommandExecution])
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("reboot"),
  ])
  let command = edge_command(
    "command-running",
    node.id,
    @edgeweaver.CommandAction::Execute("reboot"),
  )
  let accepted = try! command.accept(at=try! edge_time(8))
  let running = try! accepted.start(at=try! edge_time(9))
  let checkpoint : @edgeweaver.ExecutionCheckpoint = {
    records: [
      {
        command: running,
        status: @edgeweaver.ExecutionStatus::InProgress,
        message: "",
        started_at: try! edge_time(9),
        completed_at: None,
      },
    ],
  }
  let executor = @edgeweaver.EdgeExecutor::restore(
    node~,
    allowlist~,
    checkpoint~,
  )
  let mut calls = 0
  let record = try! executor.execute(command=running, at=try! edge_time(10), runner=_action => {
    calls = calls + 1
    @edgeweaver.ExecutionResult::Succeeded("should not run")
  })
  assert_eq(calls, 0)
  assert_eq(record.status, @edgeweaver.ExecutionStatus::InProgress)
  assert_eq(record.command.state, @edgeweaver.CommandState::Running)
}

///|
test "edge executor rejects wrong target and expired command" {
  let node = edge_node([@edgeweaver.NodeCapability::CommandExecution])
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("reboot"),
  ])
  let executor = @edgeweaver.EdgeExecutor::new(node~, allowlist~)
  let other_id = try! @edgeweaver.NodeId::new(value="node-other")
  let wrong_target = edge_command(
    "command-target",
    other_id,
    @edgeweaver.CommandAction::Execute("reboot"),
  )
  try
    executor.execute(command=wrong_target, at=try! edge_time(10), runner=_action => {
      @edgeweaver.ExecutionResult::Succeeded("unexpected")
    })
  catch {
    @edgeweaver.EdgeError::CommandTargetMismatch(command_id) =>
      assert_eq(command_id.value, "command-target")
    _ => fail("wrong target error")
  } noraise {
    _ => fail("expected target mismatch")
  }

  let expired = try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value="command-expired"),
    node_id=node.id,
    action=@edgeweaver.CommandAction::Execute("reboot"),
    issued_at=try! edge_time(5),
    expires_at=try! edge_time(9),
  )
  try
    executor.execute(command=expired, at=try! edge_time(10), runner=_action => {
      @edgeweaver.ExecutionResult::Succeeded("unexpected")
    })
  catch {
    @edgeweaver.EdgeError::ExpiredCommand(command_id) =>
      assert_eq(command_id.value, "command-expired")
    _ => fail("wrong expiry error")
  } noraise {
    _ => fail("expected expired command rejection")
  }
}
