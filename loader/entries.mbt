///|
pub(all) struct Entry {
  id : String
  plugin : @runtime.Plugin[Json]
  config : Json
  enabled : Bool
}

///|
pub fn Entry::new(
  id : String,
  plugin : @runtime.Plugin[Json],
  config : Json,
  enabled~ : Bool = true,
) -> Entry {
  { id, plugin, config, enabled, }
}

///|
fn Entry::equivalent(self : Entry, other : Entry) -> Bool {
  self.id == other.id &&
  self.plugin.id() == other.plugin.id() &&
  self.config == other.config &&
  self.enabled == other.enabled
}

///|
priv struct Record {
  mut entry : Entry
  mut handle : @runtime.Handle?
}

///|
#derive(Debug)
pub(all) struct EntrySnapshot {
  id : String
  enabled : Bool
  instance : @runtime.Snapshot?
}

///|
pub extend EntrySnapshot with Debug::{to_repr}

///|
#derive(Debug)
pub(all) suberror LoaderError {
  InvalidEntry(String)
  ApplyFailed(String, @runtime.OperationResult)
  ReconcileFailed(Error, Error?)
  RecoveryFailed(Error)
  Closed
}

///|
pub extend LoaderError with Debug::{to_repr}
