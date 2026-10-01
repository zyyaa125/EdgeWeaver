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

///|
pub extend ConfigError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigError with Eq::{not_equal, equal}

///|
pub extend ConfigVersion with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigVersion with Eq::{not_equal, equal}

///|
pub extend ConfigSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigSnapshot with Eq::{not_equal, equal}

///|
pub extend CommandError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandError with Eq::{not_equal, equal}

///|
pub extend CommandId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandId with Eq::{not_equal, equal}

///|
pub extend CommandAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandAction with Eq::{not_equal, equal}

///|
pub extend CommandState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandState with Eq::{not_equal, equal}

///|
pub extend CommandResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandResult with Eq::{not_equal, equal}

///|
pub extend Command with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Command with Eq::{not_equal, equal}
