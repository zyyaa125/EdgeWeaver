///|
#borrow(path)
extern "c" fn remove_test_file(path : Bytes) -> Int32 = "edgeweaver_checkpoint_remove"

///|
fn safety_test_time(value : Int32) -> @edgeweaver.Timestamp {
  try! @edgeweaver.Timestamp::new(unix_seconds=value)
}

///|
test "native execution checkpoint restores uncertain state and rejects corruption" {
  let path = "edgeweaver-execution-test-checkpoint.json"
  let created = safety_test_time(1)
  let node = try! @edgeweaver.Node::new(
    id="safety-node",
    capabilities=[@edgeweaver.NodeCapability::CommandExecution],
    created_at=created,
  )
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("restart"),
  ])
  let command = try! @edgeweaver.Command::new(
    id=try! @edgeweaver.CommandId::new(value="safety-command"),
    node_id=node.id,
    action=@edgeweaver.CommandAction::Execute("restart"),
    issued_at=safety_test_time(2),
    expires_at=safety_test_time(20),
  )
  let running = try! (try! command.accept(at=safety_test_time(3))).start(
    at=safety_test_time(4),
  )
  let checkpoint = @edgeweaver.ExecutionCheckpoint::{
    records: [
      {
        command: running,
        status: @edgeweaver.ExecutionStatus::InProgress,
        message: "",
        started_at: safety_test_time(4),
        completed_at: None,
      },
    ],
  }
  save_execution_records(path, node~, allowlist~, checkpoint~)
  let loaded = load_execution_checkpoint(path, node, allowlist)
  assert_eq(loaded.records()[0].status, @edgeweaver.ExecutionStatus::InProgress)
  assert_eq(loaded.records()[0].command.id.value, "safety-command")
  assert_eq(write_checkpoint_bytes(@utf8.encode(path), @utf8.encode("{")), 1)
  try load_execution_checkpoint(path, node, allowlist) catch {
    DiskCheckpointError::InvalidData => ()
    _ => fail("wrong damaged execution file error")
  } noraise {
    _ => fail("damaged execution file accepted")
  }
  assert_eq(remove_test_file(@utf8.encode(path)), 1)
}

///|
test "native policy checkpoint keeps trigger budget after restart" {
  let path = "edgeweaver-policy-test-checkpoint.json"
  let allowlist = try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("restart"),
  ])
  let rule = try! @edgeweaver.AutonomyRule::new(
    id="bounded-restart",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=safety_test_time(1),
    valid_until=safety_test_time(100),
    max_triggers=1,
  )
  let engine = try! @edgeweaver.AutonomyEngine::new(allowlist~, rules=[rule])
  let context = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Offline,
    health=@edgeweaver.NodeHealth::Healthy,
    offline_for=2,
  )
  let _ = engine.evaluate(context~, at=safety_test_time(10))
  save_policy_rules(path, allowlist~, rules=engine.checkpoint())
  let restored = load_policy_checkpoint(path, allowlist)
  assert_eq(restored.checkpoint()[0].fired_count, 1)
  assert_eq(
    restored.evaluate(context~, at=safety_test_time(11)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
  assert_eq(remove_test_file(@utf8.encode(path)), 1)
}
