///|
fn policy_time(
  seconds : Int32,
) -> @edgeweaver.Timestamp raise @edgeweaver.NodeError {
  @edgeweaver.Timestamp::new(unix_seconds=seconds)
}

///|
fn policy_allowlist() -> @edgeweaver.CommandAllowlist {
  try! @edgeweaver.CommandAllowlist::new(actions=[
    @edgeweaver.AllowedAction::Execute("restart"),
  ])
}

///|
test "offline rule fires once and then returns the safe default" {
  let rule = try! @edgeweaver.AutonomyRule::new(
    id="restart-after-outage",
    condition=@edgeweaver.PolicyCondition::OfflineFor(60),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(10),
    valid_until=try! policy_time(200),
    max_triggers=1,
  )
  let engine = try! @edgeweaver.AutonomyEngine::new(
    allowlist=policy_allowlist(),
    rules=[rule],
  )
  let context = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Offline,
    health=@edgeweaver.NodeHealth::Healthy,
    offline_for=60,
  )
  match engine.evaluate(context~, at=try! policy_time(100)) {
    @edgeweaver.PolicyDecision::Execute(id, action) => {
      assert_eq(id, "restart-after-outage")
      assert_eq(action, @edgeweaver.CommandAction::Execute("restart"))
    }
    _ => fail("expected bounded offline action")
  }
  assert_eq(
    engine.evaluate(context~, at=try! policy_time(101)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
}

///|
test "policy only acts in offline validity and known health states" {
  let rule = try! @edgeweaver.AutonomyRule::new(
    id="repair-unhealthy",
    condition=@edgeweaver.PolicyCondition::HealthIs(
      @edgeweaver.NodeHealth::Unhealthy,
    ),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(20),
    valid_until=try! policy_time(30),
    max_triggers=2,
  )
  let engine = try! @edgeweaver.AutonomyEngine::new(
    allowlist=policy_allowlist(),
    rules=[rule],
  )
  let unhealthy = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Offline,
    health=@edgeweaver.NodeHealth::Unhealthy,
    offline_for=10,
  )
  assert_eq(
    engine.evaluate(context=unhealthy, at=try! policy_time(19)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
  match engine.evaluate(context=unhealthy, at=try! policy_time(20)) {
    @edgeweaver.PolicyDecision::Execute(_, _) => ()
    _ => fail("expected unhealthy action")
  }
  match engine.evaluate(context=unhealthy, at=try! policy_time(21)) {
    @edgeweaver.PolicyDecision::Execute(_, _) => ()
    _ => fail("expected second bounded action")
  }
  assert_eq(
    engine.evaluate(context=unhealthy, at=try! policy_time(22)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
  let online = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Online,
    health=@edgeweaver.NodeHealth::Unhealthy,
    offline_for=100,
  )
  assert_eq(
    engine.evaluate(context=online, at=try! policy_time(25)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
  let unknown_health = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Offline,
    health=@edgeweaver.NodeHealth::Unknown,
    offline_for=100,
  )
  assert_eq(
    engine.evaluate(context=unknown_health, at=try! policy_time(25)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
}

///|
test "policy validation enforces allowlist and rule bounds" {
  try
    @edgeweaver.AutonomyRule::new(
      id="",
      condition=@edgeweaver.PolicyCondition::OfflineFor(1),
      action=@edgeweaver.CommandAction::Execute("restart"),
      valid_from=try! policy_time(1),
      valid_until=try! policy_time(2),
      max_triggers=1,
    )
  catch {
    @edgeweaver.PolicyError::EmptyRuleId => ()
    _ => fail("wrong empty rule error")
  } noraise {
    _ => fail("expected empty rule rejection")
  }
  try
    @edgeweaver.AutonomyRule::new(
      id="bad-window",
      condition=@edgeweaver.PolicyCondition::OfflineFor(1),
      action=@edgeweaver.CommandAction::Execute("restart"),
      valid_from=try! policy_time(3),
      valid_until=try! policy_time(2),
      max_triggers=1,
    )
  catch {
    @edgeweaver.PolicyError::InvalidWindow => ()
    _ => fail("wrong window error")
  } noraise {
    _ => fail("expected invalid window rejection")
  }
  try
    @edgeweaver.AutonomyRule::new(
      id="bad-budget",
      condition=@edgeweaver.PolicyCondition::OfflineFor(-1),
      action=@edgeweaver.CommandAction::Execute("restart"),
      valid_from=try! policy_time(1),
      valid_until=try! policy_time(2),
      max_triggers=0,
    )
  catch {
    @edgeweaver.PolicyError::InvalidMaxTriggers => ()
    _ => fail("wrong budget error")
  } noraise {
    _ => fail("expected invalid budget rejection")
  }

  let unauthorized_rule = try! @edgeweaver.AutonomyRule::new(
    id="unauthorized",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("shutdown"),
    valid_from=try! policy_time(1),
    valid_until=try! policy_time(2),
    max_triggers=1,
  )
  try
    @edgeweaver.AutonomyEngine::new(allowlist=policy_allowlist(), rules=[
      unauthorized_rule,
    ])
  catch {
    @edgeweaver.PolicyError::ActionNotAllowed(
      @edgeweaver.CommandAction::Execute(name)
    ) => assert_eq(name, "shutdown")
    _ => fail("wrong policy allowlist error")
  } noraise {
    _ => fail("expected unauthorized policy rejection")
  }
}

///|
test "policy trigger budgets survive checkpoint restore" {
  let rule = try! @edgeweaver.AutonomyRule::new(
    id="restart-once",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(1),
    valid_until=try! policy_time(100),
    max_triggers=1,
  )
  let engine = try! @edgeweaver.AutonomyEngine::new(
    allowlist=policy_allowlist(),
    rules=[rule],
  )
  let context = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Offline,
    health=@edgeweaver.NodeHealth::Healthy,
    offline_for=1,
  )
  let _ = engine.evaluate(context~, at=try! policy_time(10))
  let checkpoint = engine.checkpoint()
  let restored = try! @edgeweaver.AutonomyEngine::restore(
    allowlist=policy_allowlist(),
    rules=checkpoint,
  )
  assert_eq(
    restored.evaluate(context~, at=try! policy_time(11)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
}

///|
test "policy rejects repeated evaluation and clock rollback after restore" {
  let first = try! @edgeweaver.AutonomyRule::new(
    id="first",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(1),
    valid_until=try! policy_time(100),
    max_triggers=2,
  )
  let second = try! @edgeweaver.AutonomyRule::new(
    id="second",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(1),
    valid_until=try! policy_time(100),
    max_triggers=2,
  )
  let engine = try! @edgeweaver.AutonomyEngine::new(
    allowlist=policy_allowlist(),
    rules=[first, second],
  )
  let context = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Offline,
    health=@edgeweaver.NodeHealth::Healthy,
    offline_for=5,
  )
  match engine.evaluate(context~, at=try! policy_time(10)) {
    @edgeweaver.PolicyDecision::Execute(id, _) => assert_eq(id, "first")
    _ => fail("first rule did not take priority")
  }
  let restored = try! @edgeweaver.AutonomyEngine::restore(
    allowlist=policy_allowlist(),
    rules=engine.checkpoint(),
  )
  assert_eq(
    restored.evaluate(context~, at=try! policy_time(10)),
    @edgeweaver.PolicyDecision::SafeDefault,
  )
  try restored.evaluate(context~, at=try! policy_time(9)) catch {
    @edgeweaver.PolicyError::InvalidTimestamp => ()
    _ => fail("wrong clock rollback error")
  } noraise {
    _ => fail("clock rollback accepted")
  }
  assert_eq(restored.checkpoint()[0].fired_count, 1)
  assert_eq(restored.checkpoint()[1].fired_count, 0)
}

///|
test "policy restore rejects counter reset and version mismatch" {
  let rule = try! @edgeweaver.AutonomyRule::new(
    id="bounded",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(1),
    valid_until=try! policy_time(10),
    max_triggers=1,
  )
  rule.fired_count = 2
  try
    @edgeweaver.AutonomyEngine::restore(allowlist=policy_allowlist(), rules=[
      rule,
    ])
  catch {
    @edgeweaver.PolicyError::InvalidCheckpoint => ()
    _ => fail("wrong counter error")
  } noraise {
    _ => fail("overdrawn trigger budget accepted")
  }
  let future = try! @edgeweaver.AutonomyRule::new(
    id="future",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(1),
    valid_until=try! policy_time(10),
    max_triggers=1,
  )
  let changed : @edgeweaver.AutonomyRule = {
    id: future.id,
    condition: future.condition,
    action: future.action,
    valid_from: future.valid_from,
    valid_until: future.valid_until,
    max_triggers: future.max_triggers,
    fired_count: 0,
    policy_version: 2,
    last_evaluated_at: None,
  }
  try
    @edgeweaver.AutonomyEngine::restore(allowlist=policy_allowlist(), rules=[
      changed,
    ])
  catch {
    @edgeweaver.PolicyError::UnsupportedPolicyVersion => ()
    _ => fail("wrong policy version error")
  } noraise {
    _ => fail("unknown policy version accepted")
  }
}

///|
test "offline action is withheld when budget persistence fails" {
  let rule = try! @edgeweaver.AutonomyRule::new(
    id="persist-first",
    condition=@edgeweaver.PolicyCondition::OfflineFor(1),
    action=@edgeweaver.CommandAction::Execute("restart"),
    valid_from=try! policy_time(1),
    valid_until=try! policy_time(20),
    max_triggers=1,
  )
  let engine = try! @edgeweaver.AutonomyEngine::new(
    allowlist=policy_allowlist(),
    rules=[rule],
  )
  let context = try! @edgeweaver.AutonomyContext::new(
    lifecycle=@edgeweaver.NodeLifecycle::Offline,
    health=@edgeweaver.NodeHealth::Healthy,
    offline_for=2,
  )
  try
    engine.evaluate_durable(context~, at=try! policy_time(10), persist=_rules => {
      false
    })
  catch {
    @edgeweaver.PolicyError::PersistenceFailed => ()
    _ => fail("wrong budget save error")
  } noraise {
    _ => fail("action returned without durable budget")
  }
  assert_eq(engine.checkpoint()[0].fired_count, 1)
}
