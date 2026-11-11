///|
#derive(Eq, Compare, Hash, Debug)
pub struct RealmId {
  priv value : Int64
}

///|
pub fn RealmId::fresh() -> RealmId {
  { value: next_id(), }
}

///|
pub extend RealmId with Eq::{equal, not_equal}

///|
pub extend RealmId with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend RealmId with Hash::{hash, hash_combine}

///|
pub extend RealmId with Debug::{to_repr}
