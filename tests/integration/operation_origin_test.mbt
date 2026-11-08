///|
async test "another runtime cannot remove the managed operation wait restriction" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let direct_denied = Ref(false)
    let foreign_denied = Ref(false)
    let child : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let parent : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let (_, operation) = ctx.child_scope().install(child, ())
      direct_denied.val = try {
        ignore(operation.wait())
        false
      } catch {
        @runtime.ReentrantOperation => true
        error => raise error
      }
      let foreign_driver = @lifecycle.Driver::new(fn(_, _) {
        abort("no task expected")
      })
      let foreign = @runtime.Runtime::new(foreign_driver)
      foreign_denied.val = try {
        ignore(foreign.observe_operation(operation))
        false
      } catch {
        @runtime.ContractViolation(_) => true
        error => raise error
      }
    })
    let installed = runtime.root().install(parent, ()).1.wait()
    ignore(runtime.close().wait())
    assert_true(installed is @runtime.Succeeded(_))
    assert_true(direct_denied.val)
    assert_true(foreign_denied.val)
  })
}
