///|
struct ExecutionDocument {
  format : Int32
  checkpoint : @edgeweaver.ExecutionCheckpoint
} derive(ToJson, FromJson)

///|
pub extend ExecutionDocument with ToJson::{to_json}

///|
pub extend ExecutionDocument with @json.FromJson::{from_json}

///|
struct PolicyDocument {
  format : Int32
  rules : Array[@edgeweaver.AutonomyRule]
} derive(ToJson, FromJson)

///|
pub extend PolicyDocument with ToJson::{to_json}

///|
pub extend PolicyDocument with @json.FromJson::{from_json}

///|
/// Saves command execution records for one node before or after side effects.
pub fn save_execution_checkpoint(
  path : String,
  executor : @edgeweaver.EdgeExecutor,
) -> Unit raise DiskCheckpointError {
  save_execution_records(
    path,
    node=executor.node,
    allowlist=executor.allowlist,
    checkpoint=executor.checkpoint(),
  )
}

///|
/// Persists a proposed execution state from execute_durable's callback.
pub fn save_execution_records(
  path : String,
  node~ : @edgeweaver.Node,
  allowlist~ : @edgeweaver.CommandAllowlist,
  checkpoint~ : @edgeweaver.ExecutionCheckpoint,
) -> Unit raise DiskCheckpointError {
  if path == "" {
    raise DiskCheckpointError::EmptyPath
  }
  let _ = @edgeweaver.EdgeExecutor::restore_checked(
    node~,
    allowlist~,
    checkpoint~,
  ) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let bytes = @utf8.encode(
    @json.to_json(ExecutionDocument::{ format: 1, checkpoint, }).stringify(),
  )
  if write_checkpoint_bytes(@utf8.encode(path), bytes) != 1 {
    raise DiskCheckpointError::WriteFailed
  }
}

///|
/// Loads records and rejects malformed or mismatched node state.
pub fn load_execution_checkpoint(
  path : String,
  node : @edgeweaver.Node,
  allowlist : @edgeweaver.CommandAllowlist,
) -> @edgeweaver.EdgeExecutor raise DiskCheckpointError {
  if path == "" {
    raise DiskCheckpointError::EmptyPath
  }
  let bytes = read_checkpoint_bytes(@utf8.encode(path))
  if bytes.length() == 0 {
    raise DiskCheckpointError::ReadFailed
  }
  let content = @utf8.decode(bytes) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let json = @json.parse(content) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let document : ExecutionDocument = @json.from_json(json) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  if document.format != 1 {
    raise DiskCheckpointError::UnsupportedFormat
  }
  @edgeweaver.EdgeExecutor::restore_checked(
    node~,
    allowlist~,
    checkpoint=document.checkpoint,
  ) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
}

///|
/// Saves bounded offline rule budgets as one versioned document.
pub fn save_policy_checkpoint(
  path : String,
  engine : @edgeweaver.AutonomyEngine,
) -> Unit raise DiskCheckpointError {
  save_policy_rules(path, allowlist=engine.allowlist, rules=engine.checkpoint())
}

///|
/// Persists proposed budgets before returning an offline action decision.
pub fn save_policy_rules(
  path : String,
  allowlist~ : @edgeweaver.CommandAllowlist,
  rules~ : Array[@edgeweaver.AutonomyRule],
) -> Unit raise DiskCheckpointError {
  if path == "" {
    raise DiskCheckpointError::EmptyPath
  }
  let _ = @edgeweaver.AutonomyEngine::restore(allowlist~, rules~) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let document = PolicyDocument::{ format: 1, rules, }
  let bytes = @utf8.encode(@json.to_json(document).stringify())
  if write_checkpoint_bytes(@utf8.encode(path), bytes) != 1 {
    raise DiskCheckpointError::WriteFailed
  }
}

///|
/// Loads budget counters; invalid or future rule versions are rejected.
pub fn load_policy_checkpoint(
  path : String,
  allowlist : @edgeweaver.CommandAllowlist,
) -> @edgeweaver.AutonomyEngine raise DiskCheckpointError {
  if path == "" {
    raise DiskCheckpointError::EmptyPath
  }
  let bytes = read_checkpoint_bytes(@utf8.encode(path))
  if bytes.length() == 0 {
    raise DiskCheckpointError::ReadFailed
  }
  let content = @utf8.decode(bytes) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let json = @json.parse(content) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let document : PolicyDocument = @json.from_json(json) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  if document.format != 1 {
    raise DiskCheckpointError::UnsupportedFormat
  }
  @edgeweaver.AutonomyEngine::restore(allowlist~, rules=document.rules) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
}
