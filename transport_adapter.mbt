///|
/// Outcome of a physical connection attempt.
pub(all) enum TransportIoResult {
  Ready
  Timeout
  Disconnected
  Failed(String)
}

///|
/// Result of exchanging a version and channel advertisement.
pub(all) enum TransportHandshakeResult {
  Peer(CapabilityAdvertisement)
  Timeout
  Disconnected
  Failed(String)
}

///|
/// One receiver response bound to the original message ID.
pub(all) struct TransportReceipt {
  message_id : String
  result : SyncSendResult
}

///|
/// Result of one bounded event batch request.
pub(all) enum TransportBatchResult {
  Receipts(Array[TransportReceipt])
  Timeout
  Disconnected
  Failed(String)
}

///|
/// Injected I/O boundary. Implementations must return only after the receiver
/// durably accepts a message; a timeout or unknown result must retain it.
pub(all) struct TransportAdapter {
  connect : () -> TransportIoResult
  close : () -> Unit
  exchange : (CapabilityAdvertisement) -> TransportHandshakeResult
  send_batch : (Array[MessageEnvelope]) -> TransportBatchResult
}

///|
/// Opens a link through an injected adapter and enforces the handshake gate.
pub fn TransportManager::connect_with(
  self : TransportManager,
  adapter~ : TransportAdapter,
  at~ : Timestamp,
) -> NegotiatedLink raise TransportError {
  self.begin_connect(at~)
  match (adapter.connect)() {
    TransportIoResult::Ready => ()
    _ => {
      self.disconnect(at~)
      raise TransportError::SyncNotReady
    }
  }
  let advertisement = CapabilityAdvertisement::new(
    protocol=self.protocol,
    capabilities=self.capabilities,
  )
  match (adapter.exchange)(advertisement) {
    TransportHandshakeResult::Peer(peer) => {
      if peer.protocol != self.protocol {
        (adapter.close)()
        self.disconnect(at~)
        raise TransportError::UnsupportedProtocol(peer.protocol)
      }
      if intersect_capabilities(self.capabilities, peer.capabilities).length() ==
        0 {
        (adapter.close)()
        self.disconnect(at~)
        raise TransportError::NoSharedCapability
      }
      self.handshake(peer~)
    }
    _ => {
      (adapter.close)()
      self.disconnect(at~)
      raise TransportError::SyncNotReady
    }
  }
}

///|
/// Sends each pending event as a one-element batch and checks the matching
/// receipt before marking it acknowledged. Missing/extra/alien receipts fail
/// closed; the event remains pending for another attempt.
pub fn TransportManager::replay_with(
  self : TransportManager,
  store : LocalStore,
  config~ : SyncConfig,
  adapter~ : TransportAdapter,
) -> ReplayReport raise TransportError {
  self.replay_pending(store, config~, sender=envelope => {
    match (adapter.send_batch)([envelope]) {
      TransportBatchResult::Receipts(receipts) =>
        if receipts.length() == 1 &&
          receipts[0].message_id == envelope.message_id {
          receipts[0].result
        } else {
          SyncSendResult::RetryableFailure("receipt does not match request")
        }
      TransportBatchResult::Timeout =>
        SyncSendResult::RetryableFailure("transport timeout")
      TransportBatchResult::Disconnected =>
        SyncSendResult::RetryableFailure("transport disconnected")
      TransportBatchResult::Failed(reason) =>
        SyncSendResult::RetryableFailure(reason)
    }
  })
}

///|
/// Closes an established or connecting link and schedules a bounded retry.
pub fn TransportManager::close_with(
  self : TransportManager,
  adapter~ : TransportAdapter,
  at~ : Timestamp,
) -> Unit raise TransportError {
  (adapter.close)()
  self.disconnect(at~)
}
