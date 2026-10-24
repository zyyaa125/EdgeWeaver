///|
struct ReceiptDocument {
  format : Int32
  messages : Array[@edgeweaver.MessageEnvelope]
} derive(ToJson, FromJson)

///|
pub extend ReceiptDocument with ToJson::{to_json}

///|
pub extend ReceiptDocument with @json.FromJson::{from_json}

///|
struct LegacyReceiptDocument {
  format : Int32
  message_ids : Array[String]
} derive(FromJson)

///|
pub extend LegacyReceiptDocument with @json.FromJson::{from_json}

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
  let messages : Array[@edgeweaver.MessageEnvelope] = if status == 0 {
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
      _ => {
        let legacy : LegacyReceiptDocument = @json.from_json(json) catch {
          _ =>
            return @edgeweaver.SyncSendResult::RetryableFailure(
              "receipt invalid",
            )
        }
        if legacy.format == 1 {
          if legacy.message_ids.length() == 0 {
            return @edgeweaver.SyncSendResult::RetryableFailure(
              "legacy receipt has no verifiable messages",
            )
          }
          return @edgeweaver.SyncSendResult::RetryableFailure(
            "legacy receipt cannot verify payload",
          )
        }
        return @edgeweaver.SyncSendResult::RetryableFailure("receipt invalid")
      }
    }
    if document.format != 2 || document.messages.length() > 10000 {
      return @edgeweaver.SyncSendResult::RetryableFailure(
        "receipt format unsupported",
      )
    }
    for previous in document.messages {
      if previous.node_id.value == "" || previous.created_at.unix_seconds < 0 {
        return @edgeweaver.SyncSendResult::RetryableFailure("receipt invalid")
      }
      let _ = @edgeweaver.MessageEnvelope::new(
        version=previous.version,
        message_id=previous.message_id,
        node_id=previous.node_id,
        created_at=previous.created_at,
        correlation_id=previous.correlation_id,
        payload=previous.payload,
      ) catch {
        _ =>
          return @edgeweaver.SyncSendResult::RetryableFailure("receipt invalid")
      }
    }
    document.messages
  }
  for previous in messages {
    if previous.message_id == envelope.message_id {
      if previous == envelope {
        return @edgeweaver.SyncSendResult::Duplicate
      }
      return @edgeweaver.SyncSendResult::PermanentFailure(
        "message id conflicts with durable receipt",
      )
    }
  }
  messages.push(envelope)
  let document = ReceiptDocument::{ format: 2, messages, }
  let bytes = @utf8.encode(@json.to_json(document).stringify())
  if write_checkpoint_bytes(encoded_path, bytes) != 1 {
    return @edgeweaver.SyncSendResult::RetryableFailure("receipt write failed")
  }
  @edgeweaver.SyncSendResult::Accepted
}
