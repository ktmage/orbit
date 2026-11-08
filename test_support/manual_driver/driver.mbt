///|
pub struct Gate {
  priv mut open : Bool
  priv changed : @async.CondVar
}

///|
pub fn Gate::new() -> Gate {
  { open: false, changed: @async.CondVar::Cond(), }
}

///|
pub fn Gate::open(self : Gate) -> Unit {
  self.open = true
  self.changed.broadcast()
}

///|
pub async fn Gate::wait(self : Gate) -> Unit {
  while !self.open {
    self.changed.wait()
  }
}

///|
pub struct ManualDriver {
  priv driver : @lifecycle.Driver
  priv scheduled : Array[Scheduled]
}

///|
pub async fn[T] with_driver(body : async (ManualDriver) -> T) -> T {
  @async_driver.with_driver(base => {
    let scheduled = []
    let driver = @lifecycle.Driver::new(fn(task, completed) {
      let gate = Gate::new()
      let entry : Scheduled = { gate, finished: false, }
      scheduled.push(entry)
      base.start(
        () => {
          gate.wait()
          task()
        },
        fn(result) {
          entry.finished = true
          scheduled.retain(fn(candidate) { !candidate.finished })
          completed(result)
        },
      )
    })
    body({ driver, scheduled, })
  })
}

///|
pub fn ManualDriver::driver(self : ManualDriver) -> @lifecycle.Driver {
  self.driver
}

///|
pub fn ManualDriver::pending(self : ManualDriver) -> Int32 {
  self.scheduled.length()
}

///|
pub fn ManualDriver::start_next(self : ManualDriver) -> Unit {
  if !self.scheduled.is_empty() {
    self.scheduled.remove(0).gate.open()
  }
}

///|
priv struct Scheduled {
  gate : Gate
  mut finished : Bool
}
