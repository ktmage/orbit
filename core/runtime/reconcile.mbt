///|
priv enum NextAction {
  StartInstance
  StopInstance
  WaitForServices
  NoAction
}

///|
fn next_action(
  state : State,
  has_activation~ : Bool,
  stopping~ : Bool,
  stop_requested~ : Bool,
  blocked_by_consumers~ : Bool,
  registered~ : Bool,
  failed~ : Bool,
  may_start~ : Bool,
  missing~ : Bool,
) -> NextAction {
  if has_activation {
    if stop_requested && !stopping && !blocked_by_consumers {
      StopInstance
    } else {
      NoAction
    }
  } else if registered && !failed && may_start {
    if missing {
      if state == Waiting {
        NoAction
      } else {
        WaitForServices
      }
    } else {
      StartInstance
    }
  } else {
    NoAction
  }
}

///|
fn Runtime::resolve(
  self : Runtime,
  instance : Instance,
) -> @dependency.Resolution {
  @dependency.resolve(
    self.scopes,
    self.providers,
    instance.scope,
    instance.definition.requires,
    fn(id, _) {
      match self.instances.get(id) {
        Some(record) =>
          match record.activation {
            Some(activation) => activation.published
            None => false
          }
        None => false
      }
    },
  )
}
