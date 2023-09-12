#[test_only]
module roulette::test_accounts {
  const ADMIN: address = @0xab;
  const PLAYER: address = @0xbc;

  public fun admin(): address {
    ADMIN
  }
  
  public fun player(): address {
    PLAYER
  }
}
