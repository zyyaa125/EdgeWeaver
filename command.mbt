///|
/// Errors raised while creating or advancing a command.
pub(all) suberror CommandError {
  EmptyCommandId
  EmptyAction
  InvalidExpiry
  InvalidTimestamp
  InvalidTransition(String)
  EmptyResultMessage
  InvalidResultState
} derive(Debug, Eq)

///|
/// A stable idempotency key for one command request.
pub(all) struct CommandId {
  value : String
} derive(Debug, Eq)

///|
/// Creates a non-empty command identifier.
pub fn CommandId::new(value~ : String) -> CommandId raise CommandError {
  if value == "" {
    raise CommandError::EmptyCommandId
  }
  { value, }
}

///|
/// The operation requested by a command.
pub(all) enum CommandAction {
  ApplyConfig(ConfigVersion)
  ReadTelemetry
  Execute(String)
} derive(Debug, Eq)

///|
/// Lifecycle states for one command request.
pub(all) enum CommandState {
  Pending
  Accepted
  Running
  Succeeded
  Failed
  Expired
  Rejected
} derive(Debug, Eq)

///|
/// Terminal information attached to a completed command.
pub(all) struct CommandResult {
  state : CommandState
  message : String
  completed_at : Timestamp
} derive(Debug, Eq)

///|
/// Creates a result for a terminal command state.
pub fn CommandResult::new(
  state~ : CommandState,
  message~ : String,
  completed_at~ : Timestamp,
) -> CommandResult raise CommandError {
  if !is_terminal(state) {
    raise CommandError::InvalidResultState
  }
  if message == "" {
    raise CommandError::EmptyResultMessage
  }
  { state, message, completed_at, }
}

///|
/// A command with an explicit expiry and an auditable result.
pub(all) struct Command {
  id : CommandId
  node_id : NodeId
  action : CommandAction
  issued_at : Timestamp
  expires_at : Timestamp
  updated_at : Timestamp
  state : CommandState
  result : CommandResult?
} derive(Debug, Eq)

///|
/// Creates a pending command with a non-decreasing expiry deadline.
pub fn Command::new(
  id~ : CommandId,
  node_id~ : NodeId,
  action~ : CommandAction,
  issued_at~ : Timestamp,
  expires_at~ : Timestamp,
) -> Command raise CommandError {
  if expires_at.unix_seconds < issued_at.unix_seconds {
    raise CommandError::InvalidExpiry
  }
  match action {
    CommandAction::Execute(name) if name == "" =>
      raise CommandError::EmptyAction
    _ => ()
  }
  {
    id,
    node_id,
    action,
    issued_at,
    expires_at,
    updated_at: issued_at,
    state: CommandState::Pending,
    result: None,
  }
}

///|
/// Reports whether two commands refer to the same idempotent request.
pub fn Command::same_identity(self : Command, other~ : Command) -> Bool {
  self.id == other.id
}

///|
/// Moves a pending command into the accepted state.
pub fn Command::accept(
  self : Command,
  at~ : Timestamp,
) -> Command raise CommandError {
  self.advance(target=CommandState::Accepted, at~, result=None)
}

///|
/// Moves an accepted command into the running state.
pub fn Command::start(
  self : Command,
  at~ : Timestamp,
) -> Command raise CommandError {
  self.advance(target=CommandState::Running, at~, result=None)
}

///|
/// Completes a running command successfully.
pub fn Command::succeed(
  self : Command,
  at~ : Timestamp,
  message~ : String,
) -> Command raise CommandError {
  let result = CommandResult::new(
    state=CommandState::Succeeded,
    message~,
    completed_at=at,
  )
  self.advance(target=CommandState::Succeeded, at~, result=Some(result))
}

///|
/// Completes a running command with a failure result.
pub fn Command::fail(
  self : Command,
  at~ : Timestamp,
  message~ : String,
) -> Command raise CommandError {
  let result = CommandResult::new(
    state=CommandState::Failed,
    message~,
    completed_at=at,
  )
  self.advance(target=CommandState::Failed, at~, result=Some(result))
}

///|
/// Rejects a pending command before execution begins.
pub fn Command::reject(
  self : Command,
  at~ : Timestamp,
  reason~ : String,
) -> Command raise CommandError {
  let result = CommandResult::new(
    state=CommandState::Rejected,
    message=reason,
    completed_at=at,
  )
  self.advance(target=CommandState::Rejected, at~, result=Some(result))
}

///|
/// Expires a non-terminal command once its deadline has been reached.
pub fn Command::expire(
  self : Command,
  at~ : Timestamp,
) -> Command raise CommandError {
  if at.unix_seconds < self.expires_at.unix_seconds {
    raise CommandError::InvalidTransition("command has not reached its expiry")
  }
  let result = CommandResult::new(
    state=CommandState::Expired,
    message="command expired",
    completed_at=at,
  )
  self.advance(target=CommandState::Expired, at~, result=Some(result))
}

///|
fn Command::advance(
  self : Command,
  target~ : CommandState,
  at~ : Timestamp,
  result~ : CommandResult?,
) -> Command raise CommandError {
  if at.unix_seconds < self.updated_at.unix_seconds {
    raise CommandError::InvalidTimestamp
  }
  if target != CommandState::Expired &&
    at.unix_seconds > self.expires_at.unix_seconds {
    raise CommandError::InvalidTransition("command deadline has passed")
  }
  if !can_command_transition(self.state, target) {
    raise CommandError::InvalidTransition(
      "command lifecycle transition is not allowed",
    )
  }
  {
    id: self.id,
    node_id: self.node_id,
    action: self.action,
    issued_at: self.issued_at,
    expires_at: self.expires_at,
    updated_at: at,
    state: target,
    result,
  }
}

///|
fn can_command_transition(from : CommandState, to : CommandState) -> Bool {
  match (from, to) {
    (CommandState::Pending, CommandState::Accepted) => true
    (CommandState::Pending, CommandState::Rejected) => true
    (CommandState::Pending, CommandState::Expired) => true
    (CommandState::Accepted, CommandState::Running) => true
    (CommandState::Accepted, CommandState::Expired) => true
    (CommandState::Running, CommandState::Succeeded) => true
    (CommandState::Running, CommandState::Failed) => true
    (CommandState::Running, CommandState::Expired) => true
    _ => false
  }
}

///|
fn is_terminal(state : CommandState) -> Bool {
  match state {
    CommandState::Succeeded
    | CommandState::Failed
    | CommandState::Expired
    | CommandState::Rejected => true
    _ => false
  }
}
