///|
/// Errors raised while configuring offline event replay.
pub(all) suberror SyncError {
  InvalidBatchSize
  InvalidMaxAttempts
  InvalidCursor
} derive(Debug, Eq)

///|
/// Limits applied to one offline replay pass.
pub(all) struct SyncConfig {
  batch_size : Int
  max_attempts : Int
} derive(Debug, Eq)

///|
/// Creates a replay configuration with positive limits.
pub fn SyncConfig::new(
  batch_size~ : Int,
  max_attempts~ : Int,
) -> SyncConfig raise SyncError {
  if batch_size <= 0 {
    raise SyncError::InvalidBatchSize
  }
  if max_attempts <= 0 {
    raise SyncError::InvalidMaxAttempts
  }
  { batch_size, max_attempts, }
}

///|
/// The last event sequence acknowledged during ordered replay.
pub(all) struct SyncCursor {
  last_acked_sequence : Int
} derive(Debug, Eq)

///|
/// Creates a cursor at a validated journal sequence.
pub fn SyncCursor::new(
  last_acked_sequence~ : Int,
) -> SyncCursor raise SyncError {
  if last_acked_sequence < 0 {
    raise SyncError::InvalidCursor
  }
  { last_acked_sequence, }
}

///|
/// Starts replay before the first local journal sequence.
pub fn SyncCursor::start() -> SyncCursor {
  { last_acked_sequence: 0, }
}

///|
/// Advances the cursor without moving it backwards.
pub fn SyncCursor::advance(self : SyncCursor, sequence~ : Int) -> SyncCursor {
  if sequence > self.last_acked_sequence {
    { last_acked_sequence: sequence, }
  } else {
    self
  }
}

///|
/// Result returned by a transport adapter for one message.
pub(all) enum SyncSendResult {
  Accepted
  Duplicate
  RetryableFailure(String)
  PermanentFailure(String)
} derive(Debug, Eq)

///|
/// Outcome recorded for one inspected journal entry.
pub(all) enum ReplayOutcome {
  Acknowledged
  Deduplicated
  RetryScheduled
  Rejected
  Exhausted
} derive(Debug, Eq)

///|
/// Per-entry result from one replay pass.
pub(all) struct ReplayItem {
  sequence : Int
  message_id : String
  outcome : ReplayOutcome
  attempts : Int
} derive(Debug, Eq)

///|
/// Summary of one bounded, ordered replay pass.
pub(all) struct ReplayReport {
  cursor : SyncCursor
  inspected : Int
  acknowledged : Int
  deduplicated : Int
  retryable_failures : Int
  permanent_failures : Int
  exhausted : Int
  items : Array[ReplayItem]
} derive(Debug, Eq)

///|
/// Replays pending events in order and records idempotent outcomes.
///
/// An acknowledged message ID is never sent again. A retryable or permanent
/// result stops the pass so the cursor remains contiguous with the journal.
pub fn replay_pending(
  store : LocalStore,
  config~ : SyncConfig,
  cursor~ : SyncCursor,
  sender~ : (MessageEnvelope) -> SyncSendResult,
) -> ReplayReport raise StoreError {
  let pending = store.pending_events()
  let mut next_cursor = cursor
  let mut inspected = 0
  let mut acknowledged = 0
  let mut deduplicated = 0
  let mut retryable_failures = 0
  let mut permanent_failures = 0
  let mut exhausted = 0
  let items : Array[ReplayItem] = []
  let mut halted = false
  for entry in pending {
    if halted || inspected >= config.batch_size {
      break
    }
    if entry.sequence <= next_cursor.last_acked_sequence {
      continue
    }
    inspected = inspected + 1
    if has_acknowledged_message(store, message_id=entry.envelope.message_id) {
      store.acknowledge(sequence=entry.sequence)
      next_cursor = next_cursor.advance(sequence=entry.sequence)
      deduplicated = deduplicated + 1
      items.push({
        sequence: entry.sequence,
        message_id: entry.envelope.message_id,
        outcome: ReplayOutcome::Deduplicated,
        attempts: entry.attempts,
      })
      continue
    }
    if entry.attempts >= config.max_attempts {
      exhausted = exhausted + 1
      halted = true
      items.push({
        sequence: entry.sequence,
        message_id: entry.envelope.message_id,
        outcome: ReplayOutcome::Exhausted,
        attempts: entry.attempts,
      })
      continue
    }
    let attempts = entry.attempts + 1
    store.record_attempt(sequence=entry.sequence)
    match sender(entry.envelope) {
      SyncSendResult::Accepted => {
        store.acknowledge(sequence=entry.sequence)
        next_cursor = next_cursor.advance(sequence=entry.sequence)
        acknowledged = acknowledged + 1
        items.push({
          sequence: entry.sequence,
          message_id: entry.envelope.message_id,
          outcome: ReplayOutcome::Acknowledged,
          attempts,
        })
      }
      SyncSendResult::Duplicate => {
        store.acknowledge(sequence=entry.sequence)
        next_cursor = next_cursor.advance(sequence=entry.sequence)
        deduplicated = deduplicated + 1
        items.push({
          sequence: entry.sequence,
          message_id: entry.envelope.message_id,
          outcome: ReplayOutcome::Deduplicated,
          attempts,
        })
      }
      SyncSendResult::RetryableFailure(_) => {
        retryable_failures = retryable_failures + 1
        halted = true
        items.push({
          sequence: entry.sequence,
          message_id: entry.envelope.message_id,
          outcome: ReplayOutcome::RetryScheduled,
          attempts,
        })
      }
      SyncSendResult::PermanentFailure(_) => {
        permanent_failures = permanent_failures + 1
        halted = true
        items.push({
          sequence: entry.sequence,
          message_id: entry.envelope.message_id,
          outcome: ReplayOutcome::Rejected,
          attempts,
        })
      }
    }
  }
  {
    cursor: next_cursor,
    inspected,
    acknowledged,
    deduplicated,
    retryable_failures,
    permanent_failures,
    exhausted,
    items,
  }
}

///|
fn has_acknowledged_message(store : LocalStore, message_id~ : String) -> Bool {
  for entry in store.journal_entries() {
    if entry.status == JournalStatus::Acknowledged &&
      entry.envelope.message_id == message_id {
      return true
    }
  }
  false
}
