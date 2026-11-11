///|
async test "module preparation failure leaves current activations intact" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let loads : Array[String] = []
    let starts : Array[String] = []
    let resolver = @loader.Resolver::new(reference => {
      loads.push(reference.revision)
      if reference.revision == "broken" {
        raise RejectedConfig
      }
      @runtime.Plugin::new((_, _) => starts.push(reference.revision))
    })
    let entry : @loader.ModuleEntry = {
      id: "entry",
      module_ref: { source: "plugin", revision: "v1", },
      config: null,
      enabled: true,
    }
    loader.reload([entry], resolver)
    let before = loader.snapshots()[0].instance.unwrap()
    loader.reload([entry], resolver)
    assert_eq(loads, ["v1"])
    assert_true(
      try {
        loader.reload(
          [{ ..entry, module_ref: { source: "plugin", revision: "broken", }, }],
          resolver,
        )
        false
      } catch {
        RejectedConfig => true
        error => raise error
      },
    )
    assert_eq(
      loader.snapshots()[0].instance.unwrap().activation,
      before.activation,
    )
    assert_eq(starts, ["v1"])
    loader.reload(
      [{ ..entry, module_ref: { source: "plugin", revision: "v2", }, }],
      resolver,
    )
    assert_eq(loader.snapshots()[0].instance.unwrap().instance, before.instance)
    assert_eq(starts, ["v1", "v2"])
    loader.close()
    ignore(runtime.close().wait())
  })
}
