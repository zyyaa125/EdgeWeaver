///|
/// Errors raised while managing local durable state.
pub(all) suberror StoreError {
  InvalidCapacity
  QueueFull
  EventNotFound(Int)
  InvalidCheckpoint
} derive(Debug, Eq)

///|
/// The policy applied when the pending journal reaches its capacity.
pub(all) enum QueueFullPolicy {
  RejectNew
  DropOldest
} derive(Debug, Eq)

///|
/// Capacity and overload behavior for a local event journal.
pub(all) struct JournalConfig {
  capacity : Int
  full_policy : QueueFullPolicy
} derive(Debug, Eq)

///|
/// Creates a journal configuration with a positive pending capacity.
pub fn JournalConfig::new(
  capacity~ : Int,
  full_policy~ : QueueFullPolicy,
) -> JournalConfig raise StoreError {
  if capacity <= 0 {
    raise StoreError::InvalidCapacity
  }
  { capacity, full_policy, }
}

///|
/// Retention state for one journal entry.
pub(all) enum JournalStatus {
  Pending
  Acknowledged
} derive(Debug, Eq)

///|
/// One ordered event retained for local replay or audit.
pub(all) struct JournalEntry {
  sequence : Int
  envelope : MessageEnvelope
  mut status : JournalStatus
  mut attempts : Int
} derive(Debug, Eq)

///|
/// Reports whether an entry still awaits acknowledgement.
pub fn JournalEntry::is_pending(self : JournalEntry) -> Bool {
  self.status == JournalStatus::Pending
}

///|
/// A recoverable snapshot of the node's local operational state.
pub(all) struct LocalStateSnapshot {
  node : Node
  config : ConfigSnapshot?
  saved_at : Timestamp
} derive(Debug, Eq)

///|
/// The persistence boundary used to recover a local store after restart.
pub(all) struct StoreCheckpoint {
  config : JournalConfig
  state : LocalStateSnapshot?
  journal : Array[JournalEntry]
  next_sequence : Int
  dropped_count : Int
} derive(Debug, Eq)

///|
/// Mutable local state and event journal for one edge node process.
pub(all) struct LocalStore {
  config : JournalConfig
  mut state : LocalStateSnapshot?
  mut journal : Array[JournalEntry]
  mut next_sequence : Int
  mut dropped_count : Int
}

///|
/// Creates an empty local store.
pub fn LocalStore::new(config~ : JournalConfig) -> LocalStore {
  { config, state: None, journal: [], next_sequence: 1, dropped_count: 0, }
}

///|
/// Restores a local store from a previously captured checkpoint.
pub fn LocalStore::restore(
  checkpoint~ : StoreCheckpoint,
) -> LocalStore raise StoreError {
  let config = JournalConfig::new(
    capacity=checkpoint.config.capacity,
    full_policy=checkpoint.config.full_policy,
  )
  if checkpoint.next_sequence <= 0 || checkpoint.dropped_count < 0 {
    raise StoreError::InvalidCheckpoint
  }
  let pending = pending_entry_count(checkpoint.journal)
  if pending > config.capacity {
    raise StoreError::InvalidCheckpoint
  }
  for i in 0..<checkpoint.journal.length() {
    let entry = checkpoint.journal[i]
    if entry.sequence <= 0 ||
      entry.sequence >= checkpoint.next_sequence ||
      entry.attempts < 0 {
      raise StoreError::InvalidCheckpoint
    }
    for j in 0..<i {
      if checkpoint.journal[j].sequence == entry.sequence {
        raise StoreError::InvalidCheckpoint
      }
    }
  }
  {
    config,
    state: checkpoint.state,
    journal: copy_journal(checkpoint.journal),
    next_sequence: checkpoint.next_sequence,
    dropped_count: checkpoint.dropped_count,
  }
}

///|
/// Replaces the recoverable node and configuration snapshot.
pub fn LocalStore::save_state(
  self : LocalStore,
  snapshot~ : LocalStateSnapshot,
) -> Unit {
  self.state = Some(snapshot)
}

///|
/// Returns the latest local state snapshot, if one has been saved.
pub fn LocalStore::state(self : LocalStore) -> LocalStateSnapshot? {
  self.state
}

///|
/// Appends an event and returns its local journal sequence.
pub fn LocalStore::append_event(
  self : LocalStore,
  envelope~ : MessageEnvelope,
) -> Int raise StoreError {
  if self.pending_count() >= self.config.capacity {
    match self.config.full_policy {
      QueueFullPolicy::RejectNew => raise StoreError::QueueFull
      QueueFullPolicy::DropOldest => self.drop_oldest_pending()
    }
  }
  let sequence = self.next_sequence
  self.next_sequence = sequence + 1
  self.journal.push({
    sequence,
    envelope,
    status: JournalStatus::Pending,
    attempts: 0,
  })
  sequence
}

///|
/// Returns all entries that still await acknowledgement.
pub fn LocalStore::pending_events(self : LocalStore) -> Array[JournalEntry] {
  self.journal.filter(entry => entry.status == JournalStatus::Pending)
}

///|
/// Returns the complete retained journal in sequence order.
pub fn LocalStore::journal_entries(self : LocalStore) -> Array[JournalEntry] {
  copy_journal(self.journal)
}

///|
/// Returns the number of events awaiting acknowledgement.
pub fn LocalStore::pending_count(self : LocalStore) -> Int {
  pending_entry_count(self.journal)
}

///|
/// Returns how many pending events have been dropped by overload policy.
pub fn LocalStore::dropped_count(self : LocalStore) -> Int {
  self.dropped_count
}

///|
/// Records one replay attempt for a pending event.
pub fn LocalStore::record_attempt(
  self : LocalStore,
  sequence~ : Int,
) -> Unit raise StoreError {
  for index in 0..<self.journal.length() {
    if self.journal[index].sequence == sequence {
      if self.journal[index].status == JournalStatus::Pending {
        self.journal[index].attempts = self.journal[index].attempts + 1
      }
      return
    }
  }
  raise StoreError::EventNotFound(sequence)
}

///|
/// Marks an event acknowledged; repeating the acknowledgement is harmless.
pub fn LocalStore::acknowledge(
  self : LocalStore,
  sequence~ : Int,
) -> Unit raise StoreError {
  for index in 0..<self.journal.length() {
    if self.journal[index].sequence == sequence {
      self.journal[index].status = JournalStatus::Acknowledged
      return
    }
  }
  raise StoreError::EventNotFound(sequence)
}

///|
/// Captures a checkpoint suitable for durable encoding by a platform adapter.
pub fn LocalStore::checkpoint(self : LocalStore) -> StoreCheckpoint {
  {
    config: self.config,
    state: self.state,
    journal: copy_journal(self.journal),
    next_sequence: self.next_sequence,
    dropped_count: self.dropped_count,
  }
}

///|
fn LocalStore::drop_oldest_pending(self : LocalStore) -> Unit raise StoreError {
  let mut drop_index : Int? = None
  for index in 0..<self.journal.length() {
    if self.journal[index].status == JournalStatus::Pending {
      match drop_index {
        None => drop_index = Some(index)
        Some(_) => ()
      }
    }
  }
  match drop_index {
    Some(index) => {
      let retained : Array[JournalEntry] = []
      for i in 0..<self.journal.length() {
        if i != index {
          retained.push(self.journal[i])
        }
      }
      self.journal = retained
      self.dropped_count = self.dropped_count + 1
    }
    None => raise StoreError::InvalidCheckpoint
  }
}

///|
fn pending_entry_count(entries : Array[JournalEntry]) -> Int {
  let mut count = 0
  for entry in entries {
    if entry.status == JournalStatus::Pending {
      count = count + 1
    }
  }
  count
}

///|
fn copy_journal(entries : Array[JournalEntry]) -> Array[JournalEntry] {
  let copy : Array[JournalEntry] = []
  for entry in entries {
    copy.push({
      sequence: entry.sequence,
      envelope: entry.envelope,
      status: entry.status,
      attempts: entry.attempts,
    })
  }
  copy
}
