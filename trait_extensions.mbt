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
