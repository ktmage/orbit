///|
#derive(Debug)
pub(all) suberror AcquisitionCancelled

///|
pub extend AcquisitionCancelled with Debug::{to_repr}

///|
pub async fn[T] EffectScope::acquire(
  self : EffectScope,
  driver : Driver,
  acquire : async () -> T,
  release : async (T) -> Unit,
) -> T {
  let value : Ref[T?] = Ref(None)
  let task = self.tasks.spawn(driver, () => {
    let acquired = acquire()
    ignore(self.record_cleanup(() => release(acquired)))
    if !self.tasks.is_stopping() {
      value.val = Some(acquired)
    }
  })
  let observed = @async.handle_cancellation(() => task.wait())
  let result = if observed is None {
    task.cancel()
    @async.protect_from_cancel(() => task.wait())
  } else {
    observed.unwrap()
  }
  match result {
    Failed(error) => raise error
    Succeeded(_) if observed is Some(_) && !self.tasks.is_stopping() => {
      guard value.val is Some(acquired) else { raise AcquisitionCancelled }
      acquired
    }
    _ => raise AcquisitionCancelled
  }
}
