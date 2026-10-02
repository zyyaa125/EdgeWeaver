///|
/// Errors raised while dispatching an edge command.
pub(all) suberror EdgeError {
  EmptyAllowlistedAction
  InvalidTimestamp
  NodeNotReady(NodeLifecycle)
  RetiredNode(NodeId)
  CommandTargetMismatch(CommandId)
  ActionNotAllowed(CommandAction)
  MissingCapability(NodeCapability)
  ExpiredCommand(CommandId)
  CommandNotExecutable(CommandState)
  ExecutionInProgress(CommandId)
  EmptyResultMessage
  CommandTransition(CommandError)
} derive(Debug, Eq)

///|
/// An operation explicitly permitted on an edge node.
pub(all) enum AllowedAction {
  ApplyConfig
  ReadTelemetry
  Execute(String)
} derive(Debug, Eq)

///|
/// The local command allowlist for one node.
pub(all) struct CommandAllowlist {
  actions : Array[AllowedAction]
} derive(Debug, Eq)

///|
/// Creates an allowlist and rejects an empty executable name.
pub fn CommandAllowlist::new(
  actions~ : Array[AllowedAction],
) -> CommandAllowlist raise EdgeError {
  for action in actions {
    match action {
      AllowedAction::Execute(name) if name == "" =>
        raise EdgeError::EmptyAllowlistedAction
      _ => ()
    }
  }
  { actions, }
}

///|
/// Reports whether an action is explicitly allowed.
pub fn CommandAllowlist::allows(
  self : CommandAllowlist,
  action~ : CommandAction,
) -> Bool {
  for allowed in self.actions {
    match (allowed, action) {
      (AllowedAction::ApplyConfig, CommandAction::ApplyConfig(_)) => return true
      (AllowedAction::ReadTelemetry, CommandAction::ReadTelemetry) =>
        return true
      (AllowedAction::Execute(expected), CommandAction::Execute(actual)) if expected ==
        actual => return true
      _ => ()
    }
  }
  false
}

///|
/// Result produced by the local action adapter.
pub(all) enum ExecutionResult {
  Succeeded(String)
  Failed(String)
} derive(Debug, Eq)

///|
/// Durable status for one command execution attempt.
pub(all) enum ExecutionStatus {
  InProgress
  Succeeded
  Failed
} derive(Debug, Eq)

///|
/// A persisted execution record used to make retries idempotent.
pub(all) struct ExecutionRecord {
  command : Command
  status : ExecutionStatus
  message : String
  started_at : Timestamp
  completed_at : Timestamp?
} derive(Debug, Eq)

///|
/// A checkpoint that can be persisted and restored across process restarts.
pub(all) struct ExecutionCheckpoint {
  records : Array[ExecutionRecord]
} derive(Debug, Eq)

///|
/// Local command dispatcher for one enrolled node.
pub(all) struct EdgeExecutor {
  node : Node
  allowlist : CommandAllowlist
  mut records : Array[ExecutionRecord]
} derive(Debug, Eq)

///|
/// Creates an empty executor for a node and its explicit allowlist.
pub fn EdgeExecutor::new(
  node~ : Node,
  allowlist~ : CommandAllowlist,
) -> EdgeExecutor {
  { node, allowlist, records: [], }
}

///|
/// Restores an executor with previously persisted execution records.
pub fn EdgeExecutor::restore(
  node~ : Node,
  allowlist~ : CommandAllowlist,
  checkpoint~ : ExecutionCheckpoint,
) -> EdgeExecutor {
  { node, allowlist, records: copy_execution_records(checkpoint.records), }
}

///|
/// Captures execution records for durable persistence.
pub fn EdgeExecutor::checkpoint(self : EdgeExecutor) -> ExecutionCheckpoint {
  { records: copy_execution_records(self.records), }
}

///|
/// Returns all persisted execution records.
pub fn EdgeExecutor::records(self : EdgeExecutor) -> Array[ExecutionRecord] {
  copy_execution_records(self.records)
}

///|
/// Returns the persisted record for one command, if present.
pub fn EdgeExecutor::record(
  self : EdgeExecutor,
  command_id~ : CommandId,
) -> ExecutionRecord? {
  match self.find_record_index(command_id~) {
    Some(index) => Some(self.records[index])
    None => None
  }
}

///|
/// Executes an allowlisted command once and persists its result.
///
/// A prior record is returned without invoking the adapter again. An in-progress
/// record is also returned unchanged so a retry cannot repeat a non-idempotent
/// side effect after a restart.
pub fn EdgeExecutor::execute(
  self : EdgeExecutor,
  command~ : Command,
  at~ : Timestamp,
  runner~ : (CommandAction) -> ExecutionResult,
) -> ExecutionRecord raise EdgeError {
  if at.unix_seconds < 0 {
    raise EdgeError::InvalidTimestamp
  }
  if command.node_id != self.node.id {
    raise EdgeError::CommandTargetMismatch(command.id)
  }
  match self.find_record_index(command_id=command.id) {
    Some(index) => return self.records[index]
    None => ()
  }
  match self.node.lifecycle {
    NodeLifecycle::New => raise EdgeError::NodeNotReady(NodeLifecycle::New)
    NodeLifecycle::Retired => raise EdgeError::RetiredNode(self.node.id)
    _ => ()
  }
  if !self.allowlist.allows(action=command.action) {
    raise EdgeError::ActionNotAllowed(command.action)
  }
  let required = required_capability(command.action)
  if !self.node.supports(capability=required) {
    raise EdgeError::MissingCapability(required)
  }
  if at.unix_seconds > command.expires_at.unix_seconds {
    raise EdgeError::ExpiredCommand(command.id)
  }
  let running = match command.state {
    CommandState::Pending => {
      let accepted = command.accept(at~) catch {
        error => raise EdgeError::CommandTransition(error)
      }
      accepted.start(at~) catch {
        error => raise EdgeError::CommandTransition(error)
      }
    }
    CommandState::Accepted =>
      command.start(at~) catch {
        error => raise EdgeError::CommandTransition(error)
      }
    CommandState::Running => raise EdgeError::ExecutionInProgress(command.id)
    state => raise EdgeError::CommandNotExecutable(state)
  }
  let started = {
    command: running,
    status: ExecutionStatus::InProgress,
    message: "",
    started_at: at,
    completed_at: None,
  }
  self.records.push(started)
  match runner(command.action) {
    ExecutionResult::Succeeded(message) => {
      if message == "" {
        raise EdgeError::EmptyResultMessage
      }
      let completed = running.succeed(at~, message~) catch {
        error => raise EdgeError::CommandTransition(error)
      }
      let record = {
        command: completed,
        status: ExecutionStatus::Succeeded,
        message,
        started_at: at,
        completed_at: Some(at),
      }
      self.records[self.records.length() - 1] = record
      record
    }
    ExecutionResult::Failed(message) => {
      if message == "" {
        raise EdgeError::EmptyResultMessage
      }
      let completed = running.fail(at~, message~) catch {
        error => raise EdgeError::CommandTransition(error)
      }
      let record = {
        command: completed,
        status: ExecutionStatus::Failed,
        message,
        started_at: at,
        completed_at: Some(at),
      }
      self.records[self.records.length() - 1] = record
      record
    }
  }
}

///|
fn required_capability(action : CommandAction) -> NodeCapability {
  match action {
    CommandAction::ApplyConfig(_) => NodeCapability::PersistentStorage
    CommandAction::ReadTelemetry => NodeCapability::Telemetry
    CommandAction::Execute(_) => NodeCapability::CommandExecution
  }
}

///|
fn EdgeExecutor::find_record_index(
  self : EdgeExecutor,
  command_id~ : CommandId,
) -> Int? {
  for index in 0..<self.records.length() {
    if self.records[index].command.id == command_id {
      return Some(index)
    }
  }
  None
}

///|
fn copy_execution_records(
  records : Array[ExecutionRecord],
) -> Array[ExecutionRecord] {
  let copy : Array[ExecutionRecord] = []
  for record in records {
    copy.push({
      command: record.command,
      status: record.status,
      message: record.message,
      started_at: record.started_at,
      completed_at: record.completed_at,
    })
  }
  copy
}
