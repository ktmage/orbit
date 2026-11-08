///|
test "requests made by an effect commit immediately and defer their effects" {
  let queue = ControlQueue::new()
  let log : Array[String] = []
  queue.submit(fn() {
    log.push("first-commit")
    queue.effects.push(fn() {
      log.push("first-effect")
      queue.submit(fn() {
        log.push("second-commit")
        queue.effects.push(fn() { log.push("second-effect") })
      })
      log.push("first-effect-return")
    })
  })
  assert_eq(log, [
    "first-commit", "first-effect", "second-commit", "first-effect-return", "second-effect",
  ])
}
