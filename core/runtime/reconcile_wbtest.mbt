///|
test "missing required services prevent starting" {
  assert_true(
    next_action(
      Waiting,
      has_activation=false,
      stopping=false,
      stop_requested=false,
      blocked_by_consumers=false,
      registered=true,
      failed=false,
      may_start=true,
      missing=true,
    )
    is NoAction,
  )
}

///|
test "a provider waits for its consumers before stopping" {
  assert_true(
    next_action(
      Active,
      has_activation=true,
      stopping=false,
      stop_requested=true,
      blocked_by_consumers=true,
      registered=true,
      failed=false,
      may_start=false,
      missing=false,
    )
    is NoAction,
  )
  assert_true(
    next_action(
      Active,
      has_activation=true,
      stopping=false,
      stop_requested=true,
      blocked_by_consumers=false,
      registered=true,
      failed=false,
      may_start=false,
      missing=false,
    )
    is StopInstance,
  )
}

///|
test "a failed instance does not restart because a service becomes available" {
  assert_true(
    next_action(
      Failed,
      has_activation=false,
      stopping=false,
      stop_requested=false,
      blocked_by_consumers=false,
      registered=true,
      failed=true,
      may_start=true,
      missing=false,
    )
    is NoAction,
  )
}
