///|
#derive(Eq, Debug)
pub(all) enum Decision[T] {
  Continue
  Stop(T)
}

///|
pub extend Decision with Eq::{equal, not_equal}

///|
pub extend Decision with Debug::{to_repr}

///|
#derive(Debug)
pub(all) enum Outcome[T] {
  Success(T)
  Failed(Error)
  Cancelled
  Skipped
}

///|
pub extend Outcome with Debug::{to_repr}

///|
#derive(Debug)
pub(all) suberror DispatchError {
  DispatchCancelled
  NextAlreadyCalled
  NextAfterReturn
  NextNotAwaited
}

///|
pub extend DispatchError with Debug::{to_repr}

///|
pub struct Invocation {
  priv run : async (async () -> Unit, () -> Unit) -> Unit
}

///|
pub fn Invocation::new(
  run : async (async () -> Unit, () -> Unit) -> Unit,
) -> Invocation {
  { run, }
}

///|
priv struct AsyncHandler[I, O] {
  callback : async (I) -> O
  invocation : Invocation
}

///|
async fn[I, O] AsyncHandler::call(
  self : AsyncHandler[I, O],
  input : I,
  cancelled : () -> Unit,
  registered : () -> Bool,
) -> O {
  let result : Ref[O?] = Ref(None)
  let started = Ref(false)
  (self.invocation.run)(
    () => {
      guard registered() else { raise ListenerSkipped }
      started.val = true
      result.val = Some((self.callback)(input))
    },
    cancelled,
  ) catch {
    error =>
      raise if !started.val && !registered() {
        (ListenerSkipped : Error)
      } else {
        error
      }
  }
  guard result.val is Some(value) else { raise DispatchCancelled }
  value
}

///|
#derive(Debug)
priv suberror ListenerSkipped
