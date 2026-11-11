///|
#derive(Debug)
pub(all) suberror CleanupFailed {
  CleanupFailed(@identity.RegistrationId, Error)
}

///|
pub extend CleanupFailed with Debug::{to_repr}

///|
pub async fn EffectScope::cleanup(self : EffectScope) -> Unit {
  guard !self.cleaning else { raise CleanupInProgress }
  self.cleaning = true
  defer {
    self.cleaning = false
  }
  self.request_stop()
  @async.protect_from_cancel(() => {
    self.tasks.join()
    while self.cleanups.last() is Some(entry) {
      entry.dispose()
      self.cleanups.retain(fn(candidate) { candidate.id != entry.id })
    }
  })
}
