///|
/// Keep derived trait methods explicit for newer MoonBit toolchains.
pub extend NodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NodeError with Eq::{not_equal, equal}

///|
pub extend NodeLifecycle with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NodeLifecycle with Eq::{not_equal, equal}

///|
pub extend NodeHealth with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NodeHealth with Eq::{not_equal, equal}

///|
pub extend NodeCapability with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NodeCapability with Eq::{not_equal, equal}

///|
pub extend NodeId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NodeId with Eq::{not_equal, equal}

///|
pub extend Timestamp with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Timestamp with Eq::{not_equal, equal}

///|
pub extend Node with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Node with Eq::{not_equal, equal}

///|
pub extend ProtocolVersion with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProtocolVersion with Eq::{not_equal, equal}

///|
pub extend ProtocolError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProtocolError with Eq::{not_equal, equal}

///|
pub extend MessagePayload with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MessagePayload with Eq::{not_equal, equal}

///|
pub extend MessageEnvelope with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MessageEnvelope with Eq::{not_equal, equal}

///|
pub extend ConfigError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigError with Eq::{not_equal, equal}

///|
pub extend ConfigVersion with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigVersion with Eq::{not_equal, equal}

///|
pub extend ConfigSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigSnapshot with Eq::{not_equal, equal}

///|
pub extend CommandError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandError with Eq::{not_equal, equal}

///|
pub extend CommandId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandId with Eq::{not_equal, equal}

///|
pub extend CommandAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandAction with Eq::{not_equal, equal}

///|
pub extend CommandState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandState with Eq::{not_equal, equal}

///|
pub extend CommandResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandResult with Eq::{not_equal, equal}

///|
pub extend Command with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Command with Eq::{not_equal, equal}

///|
pub extend StoreError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend StoreError with Eq::{not_equal, equal}

///|
pub extend QueueFullPolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend QueueFullPolicy with Eq::{not_equal, equal}

///|
pub extend JournalConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JournalConfig with Eq::{not_equal, equal}

///|
pub extend JournalStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JournalStatus with Eq::{not_equal, equal}

///|
pub extend JournalEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JournalEntry with Eq::{not_equal, equal}

///|
pub extend LocalStateSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LocalStateSnapshot with Eq::{not_equal, equal}

///|
pub extend StoreCheckpoint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend StoreCheckpoint with Eq::{not_equal, equal}

///|
pub extend SyncError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyncError with Eq::{not_equal, equal}

///|
pub extend SyncConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyncConfig with Eq::{not_equal, equal}

///|
pub extend SyncCursor with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyncCursor with Eq::{not_equal, equal}

///|
pub extend SyncSendResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyncSendResult with Eq::{not_equal, equal}

///|
pub extend ReplayOutcome with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReplayOutcome with Eq::{not_equal, equal}

///|
pub extend ReplayItem with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReplayItem with Eq::{not_equal, equal}

///|
pub extend ReplayReport with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReplayReport with Eq::{not_equal, equal}

///|
pub extend ControlError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlError with Eq::{not_equal, equal}

///|
pub extend EnrollmentRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EnrollmentRequest with Eq::{not_equal, equal}

///|
pub extend Heartbeat with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Heartbeat with Eq::{not_equal, equal}

///|
pub extend ControlPlane with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlPlane with Eq::{not_equal, equal}

///|
pub extend ConfigDelivery with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigDelivery with Eq::{not_equal, equal}

///|
pub extend CommandUpdate with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandUpdate with Eq::{not_equal, equal}

///|
pub extend EdgeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EdgeError with Eq::{not_equal, equal}

///|
pub extend AllowedAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AllowedAction with Eq::{not_equal, equal}

///|
pub extend CommandAllowlist with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandAllowlist with Eq::{not_equal, equal}

///|
pub extend ExecutionResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionResult with Eq::{not_equal, equal}

///|
pub extend ExecutionStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionStatus with Eq::{not_equal, equal}

///|
pub extend ExecutionRecord with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionRecord with Eq::{not_equal, equal}

///|
pub extend ExecutionCheckpoint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExecutionCheckpoint with Eq::{not_equal, equal}

///|
pub extend EdgeExecutor with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EdgeExecutor with Eq::{not_equal, equal}

///|
pub extend PolicyError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyError with Eq::{not_equal, equal}

///|
pub extend PolicyCondition with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyCondition with Eq::{not_equal, equal}

///|
pub extend AutonomyRule with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AutonomyRule with Eq::{not_equal, equal}

///|
pub extend AutonomyContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AutonomyContext with Eq::{not_equal, equal}

///|
pub extend PolicyDecision with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PolicyDecision with Eq::{not_equal, equal}

///|
pub extend AutonomyEngine with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AutonomyEngine with Eq::{not_equal, equal}

///|
pub extend TransportError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TransportError with Eq::{not_equal, equal}

///|
pub extend ConnectionState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConnectionState with Eq::{not_equal, equal}

///|
pub extend TransportCapability with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TransportCapability with Eq::{not_equal, equal}

///|
pub extend BackoffPolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BackoffPolicy with Eq::{not_equal, equal}

///|
pub extend CapabilityAdvertisement with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CapabilityAdvertisement with Eq::{not_equal, equal}

///|
pub extend NegotiatedLink with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NegotiatedLink with Eq::{not_equal, equal}

///|
pub extend TransportManager with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TransportManager with Eq::{not_equal, equal}
