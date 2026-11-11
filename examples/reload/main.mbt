///|
async fn main {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let key : @service.ServiceKey[String] = @service.ServiceKey::new("version")
    let display : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => println(ctx.service(key).call(version => version)),
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(runtime.root().install(display, ()).1.wait())
    let resolver = @loader.Resolver::new(reference => {
      @runtime.Plugin::new((ctx, _) => ctx.provide(key, reference.revision), provides=[
        key.id(),
      ])
    })
    let entry : @loader.ModuleEntry = {
      id: "version-service",
      module_ref: { source: "version", revision: "v1", },
      config: null,
      enabled: true,
    }
    loader.reload([entry], resolver)
    loader.reload([entry], resolver)
    loader.reload(
      [{ ..entry, module_ref: { source: "version", revision: "v2", }, }],
      resolver,
    )
    loader.close()
    ignore(runtime.close().wait())
  })
}
