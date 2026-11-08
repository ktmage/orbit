///|
#derive(Eq, Debug)
pub(all) struct Requirement {
  key : @identity.KeyId
  required : Bool
}

///|
#derive(Eq, Debug)
pub(all) struct Selection {
  key : @identity.KeyId
  provider : @identity.InstanceId?
}

///|
pub(all) struct Resolution {
  selections : Array[Selection]
  missing : Array[@identity.KeyId]
}

///|
pub fn resolve(
  tree : ScopeTree,
  providers : ProviderIndex,
  scope : @identity.ScopeId,
  requirements : Array[Requirement],
  available : (@identity.InstanceId, @identity.KeyId) -> Bool,
) -> Resolution {
  let selections = []
  let missing = []
  for requirement in requirements {
    let mut provider = None
    for candidate_scope in tree.ancestors(scope) {
      if providers.get(candidate_scope, requirement.key) is Some(candidate) &&
        available(candidate, requirement.key) {
        provider = Some(candidate)
        break
      }
    }
    selections.push({ key: requirement.key, provider, })
    if provider is None && requirement.required {
      missing.push(requirement.key)
    }
  }
  { selections, missing, }
}
