///|
/// Errors raised while reconnecting and negotiating a transport link.
pub(all) suberror TransportError {
  InvalidBaseDelay
  InvalidMaxDelay
  InvalidAttemptLimit
  InvalidTimestamp
  InvalidState(ConnectionState)
  RetryNotReady(Timestamp)
  RetryExhausted
  UnsupportedProtocol(ProtocolVersion)
  NoSharedCapability
  SyncNotReady
  Store(StoreError)
} derive(Debug, Eq)

///|
/// States of the local transport lifecycle.
pub(all) enum ConnectionState {
  Disconnected
  Connecting
  Connected
  Backoff
} derive(Debug, Eq)

///|
/// Channels that can be negotiated after the protocol handshake.
pub(all) enum TransportCapability {
  EventReplay
  Heartbeat
  Telemetry
  Command
  Config
} derive(Debug, Eq)

///|
/// Exponential reconnect limits measured in seconds.
pub(all) struct BackoffPolicy {
  base_delay : Int
  max_delay : Int
  max_attempts : Int
} derive(Debug, Eq)

///|
/// Creates a bounded exponential backoff policy.
pub fn BackoffPolicy::new(
  base_delay~ : Int,
  max_delay~ : Int,
  max_attempts~ : Int,
) -> BackoffPolicy raise TransportError {
  if base_delay <= 0 {
    raise TransportError::InvalidBaseDelay
  }
  if max_delay < base_delay {
    raise TransportError::InvalidMaxDelay
  }
  if max_attempts <= 0 {
    raise TransportError::InvalidAttemptLimit
  }
  { base_delay, max_delay, max_attempts, }
}

///|
/// Returns the delay for a one-based failed connection attempt.
pub fn BackoffPolicy::delay_for(
  self : BackoffPolicy,
  attempt~ : Int,
) -> Int raise TransportError {
  if attempt <= 0 {
    raise TransportError::InvalidAttemptLimit
  }
  let mut delay = self.base_delay
  let mut index = 1
  while index < attempt && delay < self.max_delay {
    delay = if delay > self.max_delay / 2 { self.max_delay } else { delay * 2 }
    index = index + 1
  }
  delay
}

///|
/// The peer capabilities presented during a transport handshake.
pub(all) struct CapabilityAdvertisement {
  protocol : ProtocolVersion
  capabilities : Array[TransportCapability]
} derive(Debug, Eq)

///|
/// Creates a peer capability advertisement.
pub fn CapabilityAdvertisement::new(
  protocol~ : ProtocolVersion,
  capabilities~ : Array[TransportCapability],
) -> CapabilityAdvertisement {
  { protocol, capabilities, }
}

///|
/// The negotiated protocol and channel set for an active link.
pub(all) struct NegotiatedLink {
  protocol : ProtocolVersion
  capabilities : Array[TransportCapability]
} derive(Debug, Eq)

///|
/// Local transport state, reconnect budget, and sync cursor.
pub(all) struct TransportManager {
  protocol : ProtocolVersion
  capabilities : Array[TransportCapability]
  backoff : BackoffPolicy
  mut state : ConnectionState
  mut attempts : Int
  mut next_retry_at : Timestamp?
  mut negotiated : NegotiatedLink?
  mut cursor : SyncCursor
} derive(Debug, Eq)

///|
/// Creates a disconnected transport manager.
pub fn TransportManager::new(
  protocol~ : ProtocolVersion,
  capabilities~ : Array[TransportCapability],
  backoff~ : BackoffPolicy,
) -> TransportManager raise TransportError {
  if protocol != ProtocolVersion::current() {
    raise TransportError::UnsupportedProtocol(protocol)
  }
  {
    protocol,
    capabilities: copy_capabilities(capabilities),
    backoff,
    state: ConnectionState::Disconnected,
    attempts: 0,
    next_retry_at: None,
    negotiated: None,
    cursor: SyncCursor::start(),
  }
}

///|
/// Returns the current connection state.
pub fn TransportManager::state(self : TransportManager) -> ConnectionState {
  self.state
}

///|
/// Returns the most recent negotiated link, if connected.
pub fn TransportManager::negotiated(self : TransportManager) -> NegotiatedLink? {
  self.negotiated
}

///|
/// Returns the next retry time, if the link is backing off.
pub fn TransportManager::next_retry_at(self : TransportManager) -> Timestamp? {
  self.next_retry_at
}

///|
/// Returns the cursor advanced by successful event replay.
pub fn TransportManager::sync_cursor(self : TransportManager) -> SyncCursor {
  self.cursor
}

///|
/// Starts a connection attempt when the retry window permits it.
pub fn TransportManager::begin_connect(
  self : TransportManager,
  at~ : Timestamp,
) -> Unit raise TransportError {
  ensure_transport_timestamp(at)
  match self.state {
    ConnectionState::Disconnected => {
      self.state = ConnectionState::Connecting
      self.negotiated = None
    }
    ConnectionState::Backoff => {
      if self.attempts >= self.backoff.max_attempts {
        raise TransportError::RetryExhausted
      }
      match self.next_retry_at {
        Some(retry_at) if at.unix_seconds < retry_at.unix_seconds =>
          raise TransportError::RetryNotReady(retry_at)
        _ => {
          self.state = ConnectionState::Connecting
          self.negotiated = None
        }
      }
    }
    state => raise TransportError::InvalidState(state)
  }
}

///|
/// Completes the handshake and records the common capabilities.
pub fn TransportManager::handshake(
  self : TransportManager,
  peer~ : CapabilityAdvertisement,
) -> NegotiatedLink raise TransportError {
  if self.state != ConnectionState::Connecting {
    raise TransportError::InvalidState(self.state)
  }
  if peer.protocol != self.protocol {
    raise TransportError::UnsupportedProtocol(peer.protocol)
  }
  let common = intersect_capabilities(self.capabilities, peer.capabilities)
  if common.length() == 0 {
    raise TransportError::NoSharedCapability
  }
  let link : NegotiatedLink = { protocol: self.protocol, capabilities: common, }
  self.negotiated = Some(link)
  self.state = ConnectionState::Connected
  self.attempts = 0
  self.next_retry_at = None
  link
}

///|
/// Records a link loss and schedules the next bounded retry.
pub fn TransportManager::disconnect(
  self : TransportManager,
  at~ : Timestamp,
) -> Unit raise TransportError {
  ensure_transport_timestamp(at)
  match self.state {
    ConnectionState::Connected | ConnectionState::Connecting => ()
    state => raise TransportError::InvalidState(state)
  }
  self.attempts = self.attempts + 1
  let delay = self.backoff.delay_for(attempt=self.attempts)
  self.next_retry_at = Some({ unix_seconds: at.unix_seconds + delay, })
  self.negotiated = None
  self.state = ConnectionState::Backoff
}

///|
/// Replays offline events only after a successful capability handshake.
pub fn TransportManager::replay_pending(
  self : TransportManager,
  store : LocalStore,
  config~ : SyncConfig,
  sender~ : (MessageEnvelope) -> SyncSendResult,
) -> ReplayReport raise TransportError {
  match self.state {
    ConnectionState::Connected => ()
    _ => raise TransportError::SyncNotReady
  }
  if !self.has_capability(capability=TransportCapability::EventReplay) {
    raise TransportError::SyncNotReady
  }
  let report = replay_pending(store, config~, cursor=self.cursor, sender~) catch {
    error => raise TransportError::Store(error)
  }
  self.cursor = report.cursor
  report
}

///|
/// Reports whether a negotiated channel is available.
pub fn TransportManager::has_capability(
  self : TransportManager,
  capability~ : TransportCapability,
) -> Bool {
  match self.negotiated {
    Some(link) => contains_capability(link.capabilities, capability)
    None => false
  }
}

///|
fn ensure_transport_timestamp(at : Timestamp) -> Unit raise TransportError {
  if at.unix_seconds < 0 {
    raise TransportError::InvalidTimestamp
  }
}

///|
fn contains_capability(
  capabilities : Array[TransportCapability],
  capability : TransportCapability,
) -> Bool {
  for item in capabilities {
    if item == capability {
      return true
    }
  }
  false
}

///|
fn intersect_capabilities(
  local_capabilities : Array[TransportCapability],
  peer : Array[TransportCapability],
) -> Array[TransportCapability] {
  let common : Array[TransportCapability] = []
  for capability in local_capabilities {
    if contains_capability(peer, capability) &&
      !contains_capability(common, capability) {
      common.push(capability)
    }
  }
  common
}

///|
fn copy_capabilities(
  capabilities : Array[TransportCapability],
) -> Array[TransportCapability] {
  let copy : Array[TransportCapability] = []
  for capability in capabilities {
    copy.push(capability)
  }
  copy
}
