///|
test "default metadata composition is associative for object layers" {
  let key : @service.ServiceKey[Unit] = @service.ServiceKey::new("metadata")
  let a : Json = { "a": true, "common": 1 }
  let b : Json = { "b": true, "common": 2 }
  let c : Json = { "c": true, "common": 3 }
  assert_eq(
    key.metadata([key.metadata([a, b]), c]),
    key.metadata([a, key.metadata([b, c])]),
  )
  assert_eq(key.metadata([a, b, c]), {
    "a": true,
    "b": true,
    "c": true,
    "common": 3,
  })
  assert_true(
    try {
      ignore(key.metadata([a, null, c]))
      false
    } catch {
      @service.InvalidMetadata => true
      error => raise error
    },
  )
}

///|
test "a service defines its own metadata identity and associative composition" {
  let key : @service.ServiceKey[Unit] = @service.ServiceKey::new(
    "paths",
    initial_metadata=[],
    merge=fn(a, b) raise {
      match (a, b) {
        (Array(left), Array(right)) => Json::array(left + right)
        _ => raise @service.InvalidMetadata
      }
    },
  )
  assert_eq(key.metadata([["declared"], ["outer"], ["inner"]]), [
    "declared", "outer", "inner",
  ])
}
