///|
/// Errors raised while dispatching an edge command.
pub(all) suberror EdgeError {
  EmptyAllowlistedAction
  InvalidActionName
  InvalidExecutionCheckpoint
  PersistenceFailed
  OutputTooLarge
  InvalidTimestamp
  NodeNotReady(NodeLifecycle)
  RetiredNode(NodeId)
  CommandTargetMismatch(CommandId)
  CommandConflict(CommandId)
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
      AllowedAction::Execute(name) => {
        if name == "" {
          raise EdgeError::EmptyAllowlistedAction
        }
        if !valid_action_name(name) {
          raise EdgeError::InvalidActionName
        }
      }
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
        actual &&
        valid_action_name(actual) => return true
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
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExecutionStatus with ToJson::{to_json}

///|
pub extend ExecutionStatus with @json.FromJson::{from_json}

///|
/// A persisted execution record used to make retries idempotent.
pub(all) struct ExecutionRecord {
  command : Command
  status : ExecutionStatus
  message : String
  started_at : Timestamp
  completed_at : Timestamp?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExecutionRecord with ToJson::{to_json}

///|
pub extend ExecutionRecord with @json.FromJson::{from_json}

///|
/// A checkpoint that can be persisted and restored across process restarts.
pub(all) struct ExecutionCheckpoint {
  records : Array[ExecutionRecord]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExecutionCheckpoint with ToJson::{to_json}

///|
pub extend ExecutionCheckpoint with @json.FromJson::{from_json}

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
/// Validates a durable execution checkpoint before exposing any result.
pub fn EdgeExecutor::restore_checked(
  node~ : Node,
  allowlist~ : CommandAllowlist,
  checkpoint~ : ExecutionCheckpoint,
) -> EdgeExecutor raise EdgeError {
  for i in 0..<checkpoint.records.length() {
    let record = checkpoint.records[i]
    if record.command.node_id != node.id ||
      record.command.id.value == "" ||
      record.started_at.unix_seconds < 0 {
      raise EdgeError::InvalidExecutionCheckpoint
    }
    for j in 0..<i {
      if checkpoint.records[j].command.id == record.command.id {
        raise EdgeError::InvalidExecutionCheckpoint
      }
    }
    match record.status {
      ExecutionStatus::InProgress =>
        if record.command.state != CommandState::Running ||
          record.completed_at != None ||
          record.message != "" {
          raise EdgeError::InvalidExecutionCheckpoint
        }
      ExecutionStatus::Succeeded =>
        if record.command.state != CommandState::Succeeded ||
          record.completed_at == None ||
          record.message == "" {
          raise EdgeError::InvalidExecutionCheckpoint
        }
      ExecutionStatus::Failed =>
        if record.command.state != CommandState::Failed ||
          record.completed_at == None ||
          record.message == "" {
          raise EdgeError::InvalidExecutionCheckpoint
        }
    }
  }
  EdgeExecutor::restore(node~, allowlist~, checkpoint~)
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
  self.execute_durable(command~, at~, persist=_checkpoint => true, runner~)
}

///|
/// Writes InProgress before a side effect and saves the terminal result after.
/// If either save fails, the command is never presented as successful and a
/// restored InProgress record prevents an automatic retry.
pub fn EdgeExecutor::execute_durable(
  self : EdgeExecutor,
  command~ : Command,
  at~ : Timestamp,
  persist~ : (ExecutionCheckpoint) -> Bool,
  runner~ : (CommandAction) -> ExecutionResult,
) -> ExecutionRecord raise EdgeError {
  if at.unix_seconds < 0 {
    raise EdgeError::InvalidTimestamp
  }
  if command.node_id != self.node.id {
    raise EdgeError::CommandTargetMismatch(command.id)
  }
  match self.find_record_index(command_id=command.id) {
    Some(index) => {
      let previous = self.records[index].command
      if previous.action != command.action ||
        previous.issued_at != command.issued_at ||
        previous.expires_at != command.expires_at {
        raise EdgeError::CommandConflict(command.id)
      }
      return self.records[index]
    }
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
  let before = self.checkpoint()
  before.records.push(started)
  if !persist(before) {
    raise EdgeError::PersistenceFailed
  }
  self.records.push(started)
  match runner(command.action) {
    ExecutionResult::Succeeded(message) => {
      if message == "" {
        raise EdgeError::EmptyResultMessage
      }
      if @utf8.encode(message).length() > 4096 {
        raise EdgeError::OutputTooLarge
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
      let completed_checkpoint = self.checkpoint()
      completed_checkpoint.records[completed_checkpoint.records.length() - 1] = record
      if !persist(completed_checkpoint) {
        raise EdgeError::PersistenceFailed
      }
      self.records[self.records.length() - 1] = record
      record
    }
    ExecutionResult::Failed(message) => {
      if message == "" {
        raise EdgeError::EmptyResultMessage
      }
      if @utf8.encode(message).length() > 4096 {
        raise EdgeError::OutputTooLarge
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
      let completed_checkpoint = self.checkpoint()
      completed_checkpoint.records[completed_checkpoint.records.length() - 1] = record
      if !persist(completed_checkpoint) {
        raise EdgeError::PersistenceFailed
      }
      self.records[self.records.length() - 1] = record
      record
    }
  }
}

///|
fn valid_action_name(name : String) -> Bool {
  if name.length() == 0 || name.length() > 64 {
    return false
  }
  for character in name.to_array() {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-' ||
      character == '.') {
      return false
    }
  }
  true
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
) -> Int32? {
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
