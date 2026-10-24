///|
/// Errors from the native disk checkpoint adapter.
pub(all) suberror DiskCheckpointError {
  EmptyPath
  ReadFailed
  WriteFailed
  InvalidData
  UnsupportedFormat
} derive(Debug, Eq)

///|
pub extend DiskCheckpointError with @debug.Debug::{to_repr}

///|
pub extend DiskCheckpointError with Eq::{not_equal, equal}

///|
struct CheckpointDocument {
  format : Int32
  checkpoint : @edgeweaver.StoreCheckpoint
} derive(ToJson, FromJson)

///|
pub extend CheckpointDocument with ToJson::{to_json}

///|
pub extend CheckpointDocument with @json.FromJson::{from_json}

///|
#borrow(path, data)
extern "c" fn write_checkpoint_bytes(path : Bytes, data : Bytes) -> Int32 = "edgeweaver_checkpoint_write"

///|
#borrow(path)
extern "c" fn read_checkpoint_bytes(path : Bytes) -> Bytes = "edgeweaver_checkpoint_read"

///|
/// Atomically replaces a versioned checkpoint at an existing directory path.
pub fn save_checkpoint(
  path : String,
  store : @edgeweaver.LocalStore,
) -> Unit raise DiskCheckpointError {
  if path == "" {
    raise DiskCheckpointError::EmptyPath
  }
  let document = CheckpointDocument::{
    format: 1,
    checkpoint: store.checkpoint(),
  }
  let bytes = @utf8.encode(@json.to_json(document).stringify())
  if write_checkpoint_bytes(@utf8.encode(path), bytes) != 1 {
    raise DiskCheckpointError::WriteFailed
  }
}

///|
/// Loads and validates a disk checkpoint before exposing a local store.
pub fn load_checkpoint(
  path : String,
) -> @edgeweaver.LocalStore raise DiskCheckpointError {
  if path == "" {
    raise DiskCheckpointError::EmptyPath
  }
  let bytes = read_checkpoint_bytes(@utf8.encode(path))
  if bytes.length() == 0 {
    raise DiskCheckpointError::ReadFailed
  }
  decode_checkpoint_bytes(bytes)
}

///|
fn decode_checkpoint_bytes(
  bytes : Bytes,
) -> @edgeweaver.LocalStore raise DiskCheckpointError {
  let text = @utf8.decode(bytes) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let json = @json.parse(text) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  let document : CheckpointDocument = @json.from_json(json) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
  if document.format != 1 {
    raise DiskCheckpointError::UnsupportedFormat
  }
  @edgeweaver.LocalStore::restore(checkpoint=document.checkpoint) catch {
    _ => raise DiskCheckpointError::InvalidData
  }
}

///|
/// Returns None only when the checkpoint file is absent. Existing but invalid
/// checkpoints are rejected instead of being silently replaced.
pub fn load_checkpoint_if_exists(
  path : String,
) -> @edgeweaver.LocalStore? raise DiskCheckpointError {
  if path == "" {
    raise DiskCheckpointError::EmptyPath
  }
  match file_status(@utf8.encode(path)) {
    0 => None
    1 => Some(load_checkpoint(path))
    _ => raise DiskCheckpointError::ReadFailed
  }
}
