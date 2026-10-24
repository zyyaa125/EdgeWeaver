///|
/// A deliberately small diagnostic projection. Raw events, command payloads,
/// runner output and error messages never enter this type.
struct DiagnosticsJson {
  node_id : String
  role : String
  lifecycle : String
  health : String
  captured_at : Int32
  connection_state : String
  last_connected_at : Json
  next_retry_at : Json
  pending_events : Int32
  dropped_events : Int32
  sync_cursor : Int32
  sync_failures : Int32
  last_error_category : Json
  negotiated_capabilities : Array[String]
  policy_state : String
  execution_records : Int32
  uncertain_executions : Int32
  failed_executions : Int32
  succeeded_executions : Int32
} derive(ToJson)

///|
pub extend DiagnosticsJson with ToJson::{to_json}

///|
/// Emits one stable, redacted JSON snapshot for local diagnostics.
pub fn LocalDiagnostics::to_json(
  self : LocalDiagnostics,
  role~ : RunProfileKind,
) -> String {
  let capabilities : Array[String] = []
  for capability in self.negotiated_capabilities {
    capabilities.push(
      match capability {
        TransportCapability::EventReplay => "event_replay"
        TransportCapability::Heartbeat => "heartbeat"
        TransportCapability::Telemetry => "telemetry"
        TransportCapability::Command => "command"
        TransportCapability::Config => "config"
      },
    )
  }
  let summary : DiagnosticsJson = {
    node_id: self.node_id.value,
    role: match role {
      RunProfileKind::Node => "node"
      RunProfileKind::ControlPlane => "control_plane"
    },
    lifecycle: match self.lifecycle {
      NodeLifecycle::New => "new"
      NodeLifecycle::Enrolled => "enrolled"
      NodeLifecycle::Online => "online"
      NodeLifecycle::Offline => "offline"
      NodeLifecycle::Retired => "retired"
    },
    health: match self.health {
      NodeHealth::Unknown => "unknown"
      NodeHealth::Healthy => "healthy"
      NodeHealth::Degraded => "degraded"
      NodeHealth::Unhealthy => "unhealthy"
    },
    captured_at: self.captured_at.unix_seconds,
    connection_state: match self.connection_state {
      ConnectionState::Disconnected => "disconnected"
      ConnectionState::Connecting => "connecting"
      ConnectionState::Connected => "connected"
      ConnectionState::Backoff => "backoff"
    },
    last_connected_at: match self.last_connected_at {
      Some(at) => @json.to_json(at.unix_seconds)
      None => Json::null()
    },
    next_retry_at: match self.next_retry_at {
      Some(at) => @json.to_json(at.unix_seconds)
      None => Json::null()
    },
    pending_events: self.pending_events,
    dropped_events: self.dropped_events,
    sync_cursor: self.sync_cursor.last_acked_sequence,
    sync_failures: self.sync_failures,
    last_error_category: match self.last_error_category {
      Some(category) => @json.to_json(category)
      None => Json::null()
    },
    negotiated_capabilities: capabilities,
    policy_state: match self.policy_decision {
      PolicyDecision::SafeDefault => "safe_default"
      PolicyDecision::Execute(_, _) => "execute"
    },
    execution_records: self.execution_records,
    uncertain_executions: self.uncertain_executions,
    failed_executions: self.failed_executions,
    succeeded_executions: self.succeeded_executions,
  }
  @json.to_json(summary).stringify()
}
