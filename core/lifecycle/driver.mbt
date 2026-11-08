///|
#derive(Debug)
pub(all) enum Completion[T] {
  Succeeded(T)
  Failed(Error)
  Cancelled
}

///|
pub extend Completion with Debug::{to_repr}

///|
pub struct CancelHandle {
  priv cancel : () -> Unit
}

///|
pub fn CancelHandle::new(cancel : () -> Unit) -> CancelHandle {
  { cancel, }
}

///|
pub fn CancelHandle::cancel(self : CancelHandle) -> Unit {
  (self.cancel)()
}

///|
pub struct Driver {
  priv launch : (async () -> Unit, (Completion[Unit]) -> Unit) -> CancelHandle
}

///|
pub fn Driver::new(
  launch : (async () -> Unit, (Completion[Unit]) -> Unit) -> CancelHandle,
) -> Driver {
  { launch, }
}

///|
pub fn Driver::start(
  self : Driver,
  body : async () -> Unit,
  completed : (Completion[Unit]) -> Unit,
) -> CancelHandle {
  (self.launch)(body, completed)
}
