///|
#derive(Eq)
enum Step {
  UpdateProvider
  RemoveProvider
  RetryConsumer
  CloseScope
  ReleaseCleanup
}

///|
fn Step::label(self : Step) -> String {
  match self {
    UpdateProvider => "update"
    RemoveProvider => "remove"
    RetryConsumer => "retry_stop"
    CloseScope => "close"
    ReleaseCleanup => "release_cleanup"
  }
}

///|
fn operation_orders() -> Array[Array[Step]] {
  fn visit(
    prefix : Array[Step],
    remaining : Array[Step],
    result : Array[Array[Step]],
  ) -> Unit {
    if remaining.is_empty() {
      result.push(prefix)
      return
    }
    for index in 0..<remaining.length() {
      let next = prefix.copy()
      next.push(remaining[index])
      let rest = remaining.copy()
      ignore(rest.remove(index))
      visit(next, rest, result)
    }
  }
  let orders = []
  visit(
    [],
    [UpdateProvider, RemoveProvider, RetryConsumer, CloseScope, ReleaseCleanup],
    orders,
  )
  orders
}

///|
fn describe_order(steps : Array[Step]) -> String {
  steps.map(step => step.label()).join(" -> ")
}

///|
test "generated orders cover every permutation without duplicates" {
  let orders = operation_orders()
  let distinct : Map[String, Bool] = Map([])
  for steps in orders {
    assert_eq(steps.length(), 5)
    for
      step in [
        UpdateProvider,
        RemoveProvider,
        RetryConsumer,
        CloseScope,
        ReleaseCleanup,
      ] {
      assert_eq(steps.filter(candidate => candidate == step).length(), 1)
    }
    distinct[describe_order(steps)] = true
  }
  assert_eq((orders.length(), distinct.length()), (120, 120))
}
