///|
async fn verify_orders(failures : Int32) -> Unit {
  let orders = operation_orders()
  let mut completed = 0
  for replace in [false, true] {
    for steps in orders {
      run_order(steps, failures, replace)
      completed += 1
    }
  }
  assert_eq(completed, 240)
}

///|
async test "all operation orders finish cleanup and preserve unrelated plugins" {
  verify_orders(0)
}

///|
async test "all operation orders recover after one cleanup failure" {
  verify_orders(1)
}

///|
async test "all operation orders recover after repeated cleanup failures" {
  verify_orders(2)
}
