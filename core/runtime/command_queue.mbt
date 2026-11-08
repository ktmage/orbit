///|
priv struct ControlQueue {
  commands : Array[() -> Unit]
  effects : Array[() -> Unit]
  mut draining : Bool
  mut executing_effect : Bool
}

///|
fn ControlQueue::new() -> ControlQueue {
  { commands: [], effects: [], draining: false, executing_effect: false, }
}

///|
fn ControlQueue::submit(self : ControlQueue, command : () -> Unit) -> Unit {
  self.commands.push(command)
  guard !self.draining else {
    if self.executing_effect {
      while !self.commands.is_empty() {
        self.commands.remove(0)()
      }
    }
    return
  }
  self.draining = true
  defer {
    self.draining = false
  }
  while !self.commands.is_empty() || !self.effects.is_empty() {
    while !self.commands.is_empty() {
      self.commands.remove(0)()
    }
    if !self.effects.is_empty() {
      self.executing_effect = true
      self.effects.remove(0)()
      self.executing_effect = false
    }
  }
}

///|
fn Runtime::commit(self : Runtime, command : () -> Unit) -> Unit {
  self.queue.submit(fn() {
    command()
    self.refresh()
  })
}

///|
fn Runtime::later(self : Runtime, effect : () -> Unit) -> Unit {
  self.queue.effects.push(effect)
}
