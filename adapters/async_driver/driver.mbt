///|
pub async fn[T] with_driver(body : async (@lifecycle.Driver) -> T) -> T {
  @async.with_task_group(group => {
    let driver = @lifecycle.Driver::new(fn(task_body, completed) {
      let task = group.spawn(
        () => {
          let outcome = try {
            match @async.handle_cancellation(task_body) {
              Some(value) => @lifecycle.Succeeded(value)
              None => @lifecycle.Cancelled
            }
          } catch {
            error => @lifecycle.Failed(error)
          }
          completed(outcome)
        },
        allow_failure=true,
      )
      @lifecycle.CancelHandle::new(fn() { task.cancel() })
    })
    body(driver)
  })
}
