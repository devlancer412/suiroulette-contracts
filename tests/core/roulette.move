// A mock USDC coin
#[test_only]
module roulette::roulette_test {
  use sui::sui::SUI;
  use sui::coin::{Self, Coin, mint_for_testing, burn_for_testing};
  use sui::test_scenario::{
    Scenario, begin, ctx, next_tx, end, take_from_sender, take_shared, return_to_sender, return_share
  };
  use roulette::roulette::{
    AdminCap, Config, test_init, update_config, get_config_data
  };
  use roulette::common_test::{to_base};

  public fun setup(scenario: &mut Scenario) {
    test_init(ctx(scenario));
    next_tx(scenario, @admin);

    let admin_cap = take_from_sender<AdminCap>(scenario);
    let config = take_shared<Config>(scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(scenario));
    next_tx(scenario, @admin);

    update_config(
      admin_cap,
      config,
      50,
      to_base(1),
      to_base(10),
      9474,
      coins
    );

    return_to_sender(scenario, admin_cap);
    return_share(scenario);
    next_tx(scenario, @admin);
  }

  #[test]
  fun test_update_config() {
    let scenario = begin(@admin);
    setup(&mut scenario);

    let config = take_shared<Config>(&mut scenario);
    let (poolSize, range, min_value, max_value, rate) = get_config_data(&config);

    assert!(poolSize == to_base(10), 1);
    assert!(range == 50, 1);
    assert!(min_value == to_base(1), 1);
    assert!(max_value == to_base(10), 1);
    assert!(rate == 9474, 1);

    let admin_cap = take_from_sender<AdminCap>(&mut scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(&mut scenario));
    next_tx(&mut scenario, @admin);

    update_config(
      admin_cap,
      config,
      range,
      min_value,
      max_value,
      9474,
      coins
    );
    return_to_sender(&mut scenario, admin_cap);
    return_share(&mut scenario);
    next_tx(scenario, @admin);

    config = take_shared(&mut scenario);
    (poolSize, , , , ) = get_config_data(&config);

    assert!(poolSize == to_base(20), 1);        
  }
}