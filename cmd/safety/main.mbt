///|
suberror SafetyDemoError {
  InvalidArguments
  UnexpectedState
}

///|
fn main raise {
  let args = @env.args()
  if args.length() != 3 || args[2] == "" {
    println("usage: moon run cmd/safety -- write|resume <execution-path>")
    raise SafetyDemoError::InvalidArguments
  }
  let node = make_node()
  let allowlist = @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("restart"),
  ])
  let command = make_command(node.id)
  match args[1] {
    "write" => write_uncertain(args[2], node, allowlist, command)
    "resume" => resume_uncertain(args[2], node, allowlist, command)
    _ => raise SafetyDemoError::InvalidArguments
  }
}

///|
fn at(value : Int32) -> @edgeweaver.Timestamp raise {
  @edgeweaver.Timestamp::new(unix_seconds=value)
}

///|
fn make_node() -> @edgeweaver.Node raise {
  let fresh = @edgeweaver.Node::new(
    id="safety-demo-node",
    capabilities=[@edgeweaver.NodeCapability::CommandExecution],
    created_at=at(1),
  )
  fresh
  .transition(target=@edgeweaver.NodeLifecycle::Enrolled, at=at(2))
  .transition(target=@edgeweaver.NodeLifecycle::Online, at=at(3))
}

///|
fn make_command(node_id : @edgeweaver.NodeId) -> @edgeweaver.Command raise {
  @edgeweaver.Command::new(
    id=@edgeweaver.CommandId::new(value="safety-demo-command"),
    node_id~,
    action=@edgeweaver.CommandAction::Execute("restart"),
    issued_at=at(5),
    expires_at=at(50),
  )
}

///|
fn write_uncertain(
  path : String,
  node : @edgeweaver.Node,
  allowlist : @edgeweaver.CommandAllowlist,
  command : @edgeweaver.Command,
) -> Unit raise {
  let executor = @edgeweaver.EdgeExecutor::new(node~, allowlist~)
  let mut saves = 0
  let mut calls = 0
  try
    executor.execute_durable(
      command~,
      at=at(10),
      persist=checkpoint => {
        saves = saves + 1
        if saves > 1 {
          false
        } else {
          let mut saved = true
          @disk.save_execution_records(path, node~, allowlist~, checkpoint~) catch {
            _ => saved = false
          }
          saved
        }
      },
      runner=_action => {
        calls = calls + 1
        @edgeweaver.ExecutionResult::Succeeded("simulated side effect")
      },
    )
  catch {
    @edgeweaver.EdgeError::PersistenceFailed => ()
    error => raise error
  } noraise {
    _ => raise SafetyDemoError::UnexpectedState
  }
  if saves != 2 || calls != 1 {
    raise SafetyDemoError::UnexpectedState
  }
  println("uncertain execution saved; runner_calls=" + calls.to_string())
}

///|
fn resume_uncertain(
  path : String,
  node : @edgeweaver.Node,
  allowlist : @edgeweaver.CommandAllowlist,
  command : @edgeweaver.Command,
) -> Unit raise {
  let executor = @disk.load_execution_checkpoint(path, node, allowlist)
  let mut calls = 0
  let record = executor.execute_durable(
    command~,
    at=at(11),
    persist=_checkpoint => true,
    runner=_action => {
      calls = calls + 1
      @edgeweaver.ExecutionResult::Succeeded("unexpected repeat")
    },
  )
  if calls != 0 || record.status != @edgeweaver.ExecutionStatus::InProgress {
    raise SafetyDemoError::UnexpectedState
  }
  println("restored uncertain execution; runner_calls=" + calls.to_string())
}
