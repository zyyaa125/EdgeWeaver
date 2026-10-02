///|
/// Errors raised while defining or evaluating bounded autonomy rules.
pub(all) suberror PolicyError {
  EmptyRuleId
  EmptyAction
  InvalidWindow
  InvalidMaxTriggers
  InvalidOfflineDuration
  InvalidTimestamp
  DuplicateRuleId(String)
  ActionNotAllowed(CommandAction)
} derive(Debug, Eq)

///|
/// Conditions that can trigger a local offline rule.
pub(all) enum PolicyCondition {
  OfflineFor(Int)
  HealthIs(NodeHealth)
} derive(Debug, Eq)

///|
/// A bounded local action with a validity window and trigger budget.
pub(all) struct AutonomyRule {
  id : String
  condition : PolicyCondition
  action : CommandAction
  valid_from : Timestamp
  valid_until : Timestamp
  max_triggers : Int
  mut fired_count : Int
} derive(Debug, Eq)

///|
/// Creates a validated offline autonomy rule.
pub fn AutonomyRule::new(
  id~ : String,
  condition~ : PolicyCondition,
  action~ : CommandAction,
  valid_from~ : Timestamp,
  valid_until~ : Timestamp,
  max_triggers~ : Int,
) -> AutonomyRule raise PolicyError {
  if id == "" {
    raise PolicyError::EmptyRuleId
  }
  if valid_until.unix_seconds < valid_from.unix_seconds {
    raise PolicyError::InvalidWindow
  }
  if max_triggers <= 0 {
    raise PolicyError::InvalidMaxTriggers
  }
  match condition {
    PolicyCondition::OfflineFor(seconds) if seconds < 0 =>
      raise PolicyError::InvalidOfflineDuration
    _ => ()
  }
  match action {
    CommandAction::Execute(name) if name == "" => raise PolicyError::EmptyAction
    _ => ()
  }
  {
    id,
    condition,
    action,
    valid_from,
    valid_until,
    max_triggers,
    fired_count: 0,
  }
}

///|
/// The observations available to the offline policy engine.
pub(all) struct AutonomyContext {
  lifecycle : NodeLifecycle
  health : NodeHealth
  offline_for : Int
} derive(Debug, Eq)

///|
/// Creates a validated policy evaluation context.
pub fn AutonomyContext::new(
  lifecycle~ : NodeLifecycle,
  health~ : NodeHealth,
  offline_for~ : Int,
) -> AutonomyContext raise PolicyError {
  if offline_for < 0 {
    raise PolicyError::InvalidOfflineDuration
  }
  { lifecycle, health, offline_for, }
}

///|
/// The safe result when no bounded rule may run.
pub(all) enum PolicyDecision {
  SafeDefault
  Execute(String, CommandAction)
} derive(Debug, Eq)

///|
/// Stateful evaluator for a node's offline autonomy rules.
pub(all) struct AutonomyEngine {
  allowlist : CommandAllowlist
  mut rules : Array[AutonomyRule]
} derive(Debug, Eq)

///|
/// Creates an evaluator and verifies every rule is allowlisted.
pub fn AutonomyEngine::new(
  allowlist~ : CommandAllowlist,
  rules~ : Array[AutonomyRule],
) -> AutonomyEngine raise PolicyError {
  for i in 0..<rules.length() {
    let rule = rules[i]
    if !allowlist.allows(action=rule.action) {
      raise PolicyError::ActionNotAllowed(rule.action)
    }
    for j in 0..<i {
      if rules[j].id == rule.id {
        raise PolicyError::DuplicateRuleId(rule.id)
      }
    }
  }
  { allowlist, rules: copy_rules(rules), }
}

///|
/// Evaluates rules in declaration order and consumes one trigger budget.
///
/// The engine only acts while the node is offline and health is known. Expired,
/// exhausted, or non-matching rules fall through to the safe default.
pub fn AutonomyEngine::evaluate(
  self : AutonomyEngine,
  context~ : AutonomyContext,
  at~ : Timestamp,
) -> PolicyDecision raise PolicyError {
  if at.unix_seconds < 0 {
    raise PolicyError::InvalidTimestamp
  }
  if context.offline_for < 0 {
    return PolicyDecision::SafeDefault
  }
  if context.lifecycle != NodeLifecycle::Offline ||
    context.health == NodeHealth::Unknown {
    return PolicyDecision::SafeDefault
  }
  for index in 0..<self.rules.length() {
    let rule = self.rules[index]
    if rule.fired_count >= rule.max_triggers {
      continue
    }
    if at.unix_seconds < rule.valid_from.unix_seconds ||
      at.unix_seconds > rule.valid_until.unix_seconds {
      continue
    }
    if !condition_matches(rule.condition, context) {
      continue
    }
    self.rules[index].fired_count = rule.fired_count + 1
    return PolicyDecision::Execute(rule.id, rule.action)
  }
  PolicyDecision::SafeDefault
}

///|
/// Captures trigger budgets for persistence across process restarts.
pub fn AutonomyEngine::checkpoint(self : AutonomyEngine) -> Array[AutonomyRule] {
  copy_rules(self.rules)
}

///|
/// Restores an evaluator from persisted rule counters.
pub fn AutonomyEngine::restore(
  allowlist~ : CommandAllowlist,
  rules~ : Array[AutonomyRule],
) -> AutonomyEngine raise PolicyError {
  AutonomyEngine::new(allowlist~, rules~)
}

///|
fn condition_matches(
  condition : PolicyCondition,
  context : AutonomyContext,
) -> Bool {
  match condition {
    PolicyCondition::OfflineFor(seconds) => context.offline_for >= seconds
    PolicyCondition::HealthIs(health) => context.health == health
  }
}

///|
fn copy_rules(rules : Array[AutonomyRule]) -> Array[AutonomyRule] {
  let copy : Array[AutonomyRule] = []
  for rule in rules {
    copy.push({
      id: rule.id,
      condition: rule.condition,
      action: rule.action,
      valid_from: rule.valid_from,
      valid_until: rule.valid_until,
      max_triggers: rule.max_triggers,
      fired_count: rule.fired_count,
    })
  }
  copy
}
