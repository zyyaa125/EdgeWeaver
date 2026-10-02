///|
fn policy_time(
  seconds : Int,
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
