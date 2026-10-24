///|
fn checkpoint_test_store() -> @edgeweaver.LocalStore {
  let config = try! @edgeweaver.JournalConfig::new(
    capacity=2,
    full_policy=@edgeweaver.QueueFullPolicy::RejectNew,
  )
  @edgeweaver.LocalStore::new(config~)
}

///|
test "checkpoint decoder rejects truncated and missing fields" {
  for
    content in [
      "{\"format\":1,\"checkpoint\":", "{\"format\":1}", "{\"format\":1,\"checkpoint\":null}",
    ] {
    try decode_checkpoint_bytes(@utf8.encode(content)) catch {
      DiskCheckpointError::InvalidData => ()
      _ => fail("wrong corruption error")
    } noraise {
      _ => fail("corrupt checkpoint accepted")
    }
  }
}

///|
test "checkpoint decoder rejects unsupported format and invalid journal" {
  let store = checkpoint_test_store()
  let unsupported = CheckpointDocument::{
    format: 99,
    checkpoint: store.checkpoint(),
  }
  try
    decode_checkpoint_bytes(
      @utf8.encode(@json.to_json(unsupported).stringify()),
    )
  catch {
    DiskCheckpointError::UnsupportedFormat => ()
    _ => fail("wrong format error")
  } noraise {
    _ => fail("unsupported format accepted")
  }
  let valid = store.checkpoint()
  let invalid = CheckpointDocument::{
    format: 1,
    checkpoint: {
      config: valid.config,
      state: valid.state,
      journal: [],
      next_sequence: 0,
      dropped_count: 0,
    },
  }
  try
    decode_checkpoint_bytes(@utf8.encode(@json.to_json(invalid).stringify()))
  catch {
    DiskCheckpointError::InvalidData => ()
    _ => fail("wrong invalid checkpoint error")
  } noraise {
    _ => fail("invalid journal accepted")
  }
}
