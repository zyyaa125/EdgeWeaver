///|
/// Errors raised while recording local diagnostics.
pub(all) suberror DiagnosticsError {
  InvalidLogLimit
  EmptyComponent
  EmptyMessage
  InvalidTimestamp
} derive(Debug, Eq)

///|
/// Severity for one structured local diagnostic event.
pub(all) enum LogLevel {
  Debug
  Info
  Warn
  Error
} derive(Debug, Eq)

///|
/// One structured event retained by the local diagnostics collector.
pub(all) struct DiagnosticEvent {
  at : Timestamp
  level : LogLevel
  component : String
  message : String
} derive(Debug, Eq)

///|
/// A bounded collector for local events and sync/policy status.
pub(all) struct DiagnosticsCollector {
  max_logs : Int
  mut logs : Array[DiagnosticEvent]
  mut sync_failures : Int
  mut last_sync_error : String?
  mut last_policy_decision : PolicyDecision
} derive(Debug, Eq)

///|
/// Creates an empty diagnostics collector with a bounded log buffer.
pub fn DiagnosticsCollector::new(
  max_logs~ : Int,
) -> DiagnosticsCollector raise DiagnosticsError {
  if max_logs <= 0 {
    raise DiagnosticsError::InvalidLogLimit
  }
  {
    max_logs,
    logs: [],
    sync_failures: 0,
    last_sync_error: None,
    last_policy_decision: PolicyDecision::SafeDefault,
  }
}

///|
/// Records one structured event, dropping the oldest event at capacity.
pub fn DiagnosticsCollector::record_event(
  self : DiagnosticsCollector,
  at~ : Timestamp,
  level~ : LogLevel,
  component~ : String,
  message~ : String,
) -> Unit raise DiagnosticsError {
  ensure_diagnostic_timestamp(at)
  if component == "" {
    raise DiagnosticsError::EmptyComponent
  }
  if message == "" {
    raise DiagnosticsError::EmptyMessage
  }
  if self.logs.length() >= self.max_logs {
    let retained : Array[DiagnosticEvent] = []
    for index in 1..<self.logs.length() {
      retained.push(self.logs[index])
    }
    self.logs = retained
  }
  self.logs.push({ at, level, component, message, })
}

///|
/// Records a sync failure and retains its latest message.
pub fn DiagnosticsCollector::record_sync_failure(
  self : DiagnosticsCollector,
  at~ : Timestamp,
  message~ : String,
) -> Unit raise DiagnosticsError {
  ensure_diagnostic_timestamp(at)
  if message == "" {
    raise DiagnosticsError::EmptyMessage
  }
  self.sync_failures = self.sync_failures + 1
  self.last_sync_error = Some(message)
  self.record_event(at~, level=LogLevel::Error, component="sync", message~)
}

///|
/// Records the latest policy decision for diagnostics.
pub fn DiagnosticsCollector::record_policy_decision(
  self : DiagnosticsCollector,
  at~ : Timestamp,
  decision~ : PolicyDecision,
) -> Unit raise DiagnosticsError {
  ensure_diagnostic_timestamp(at)
  self.last_policy_decision = decision
  self.record_event(
    at~,
    level=LogLevel::Info,
    component="policy",
    message="policy decision recorded",
  )
}

///|
/// Returns a copy of the retained structured events.
pub fn DiagnosticsCollector::events(
  self : DiagnosticsCollector,
) -> Array[DiagnosticEvent] {
  copy_diagnostic_events(self.logs)
}

///|
/// Captures a cross-component local health snapshot.
pub fn DiagnosticsCollector::snapshot(
  self : DiagnosticsCollector,
  node~ : Node,
  store~ : LocalStore,
  transport~ : TransportManager,
  executor~ : EdgeExecutor,
  at~ : Timestamp,
) -> LocalDiagnostics raise DiagnosticsError {
  ensure_diagnostic_timestamp(at)
  let negotiated_capabilities = match transport.negotiated() {
    Some(link) => copy_transport_capabilities(link.capabilities)
    None => []
  }
  {
    node_id: node.id,
    lifecycle: node.lifecycle,
    health: node.health,
    captured_at: at,
    pending_events: store.pending_count(),
    dropped_events: store.dropped_count(),
    sync_failures: self.sync_failures,
    last_sync_error: self.last_sync_error,
    sync_cursor: transport.sync_cursor(),
    connection_state: transport.state(),
    negotiated_capabilities,
    next_retry_at: transport.next_retry_at(),
    policy_decision: self.last_policy_decision,
    execution_records: executor.records().length(),
    events: copy_diagnostic_events(self.logs),
  }
}

///|
/// Cross-component status exposed to local operators.
pub(all) struct LocalDiagnostics {
  node_id : NodeId
  lifecycle : NodeLifecycle
  health : NodeHealth
  captured_at : Timestamp
  pending_events : Int
  dropped_events : Int
  sync_failures : Int
  last_sync_error : String?
  sync_cursor : SyncCursor
  connection_state : ConnectionState
  negotiated_capabilities : Array[TransportCapability]
  next_retry_at : Timestamp?
  policy_decision : PolicyDecision
  execution_records : Int
  events : Array[DiagnosticEvent]
} derive(Debug, Eq)

///|
fn ensure_diagnostic_timestamp(at : Timestamp) -> Unit raise DiagnosticsError {
  if at.unix_seconds < 0 {
    raise DiagnosticsError::InvalidTimestamp
  }
}

///|
fn copy_diagnostic_events(
  events : Array[DiagnosticEvent],
) -> Array[DiagnosticEvent] {
  let copy : Array[DiagnosticEvent] = []
  for event in events {
    copy.push({
      at: event.at,
      level: event.level,
      component: event.component,
      message: event.message,
    })
  }
  copy
}

///|
fn copy_transport_capabilities(
  capabilities : Array[TransportCapability],
) -> Array[TransportCapability] {
  let copy : Array[TransportCapability] = []
  for capability in capabilities {
    copy.push(capability)
  }
  copy
}
