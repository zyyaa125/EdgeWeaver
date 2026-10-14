///|
struct ReceiptDocument {
  format : Int32
  message_ids : Array[String]
} derive(ToJson, FromJson)

///|
pub extend ReceiptDocument with ToJson::{to_json}

///|
pub extend ReceiptDocument with @json.FromJson::{from_json}

///|
#borrow(path)
extern "c" fn file_status(path : Bytes) -> Int32 = "edgeweaver_file_status"

///|
/// A disk-backed single-writer receiver used to demonstrate replay after an
/// acknowledgement is lost. Repeated message IDs produce Duplicate.
pub fn receive_once(
  path : String,
  envelope : @edgeweaver.MessageEnvelope,
) -> @edgeweaver.SyncSendResult {
  if path == "" {
    return @edgeweaver.SyncSendResult::RetryableFailure("empty receipt path")
  }
  let encoded_path = @utf8.encode(path)
  let status = file_status(encoded_path)
  if status < 0 {
    return @edgeweaver.SyncSendResult::RetryableFailure("receipt inaccessible")
  }
  let ids : Array[String] = if status == 0 {
    []
  } else {
    let bytes = read_checkpoint_bytes(encoded_path)
    if bytes.length() == 0 {
      return @edgeweaver.SyncSendResult::RetryableFailure("receipt unreadable")
    }
    let content = @utf8.decode(bytes) catch {
      _ =>
        return @edgeweaver.SyncSendResult::RetryableFailure("receipt invalid")
    }
    let json = @json.parse(content) catch {
      _ =>
        return @edgeweaver.SyncSendResult::RetryableFailure("receipt invalid")
    }
    let document : ReceiptDocument = @json.from_json(json) catch {
      _ =>
        return @edgeweaver.SyncSendResult::RetryableFailure("receipt invalid")
    }
    if document.format != 1 {
      return @edgeweaver.SyncSendResult::RetryableFailure(
        "receipt format unsupported",
      )
    }
    document.message_ids
  }
  for id in ids {
    if id == envelope.message_id {
      return @edgeweaver.SyncSendResult::Duplicate
    }
  }
  ids.push(envelope.message_id)
  let document = ReceiptDocument::{ format: 1, message_ids: ids, }
  let bytes = @utf8.encode(@json.to_json(document).stringify())
  if write_checkpoint_bytes(encoded_path, bytes) != 1 {
    return @edgeweaver.SyncSendResult::RetryableFailure("receipt write failed")
  }
  @edgeweaver.SyncSendResult::Accepted
}
