///|
#borrow(path)
extern "c" fn remove_receipt_test_file(path : Bytes) -> Int32 = "edgeweaver_checkpoint_remove"

///|
fn receipt_test_event(content : String) -> @edgeweaver.MessageEnvelope {
  try! @edgeweaver.MessageEnvelope::new(
    version=@edgeweaver.ProtocolVersion::current(),
    message_id="same-id",
    node_id=try! @edgeweaver.NodeId::new(value="receipt-node"),
    created_at=try! @edgeweaver.Timestamp::new(unix_seconds=10),
    correlation_id=None,
    payload=@edgeweaver.MessagePayload::Telemetry(content),
  )
}

///|
test "durable receipt rejects same ID with different payload" {
  let path = "edgeweaver-receipt-conflict-test.json"
  let original = receipt_test_event("sample=1")
  assert_eq(receive_once(path, original), @edgeweaver.SyncSendResult::Accepted)
  assert_eq(receive_once(path, original), @edgeweaver.SyncSendResult::Duplicate)
  match receive_once(path, receipt_test_event("sample=2")) {
    @edgeweaver.SyncSendResult::PermanentFailure(_) => ()
    _ => fail("conflicting payload accepted")
  }
  assert_eq(remove_receipt_test_file(@utf8.encode(path)), 1)
}

///|
test "legacy ID-only receipt is preserved and fails closed" {
  let path = "edgeweaver-legacy-receipt-test.json"
  assert_eq(
    write_checkpoint_bytes(
      @utf8.encode(path),
      @utf8.encode("{\"format\":1,\"message_ids\":[\"same-id\"]}"),
    ),
    1,
  )
  match receive_once(path, receipt_test_event("sample=1")) {
    @edgeweaver.SyncSendResult::RetryableFailure(_) => ()
    _ => fail("legacy ID-only receipt trusted")
  }
  let preserved = read_checkpoint_bytes(@utf8.encode(path))
  assert_true(preserved.length() > 0)
  assert_eq(remove_receipt_test_file(@utf8.encode(path)), 1)
}
