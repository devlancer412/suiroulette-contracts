// A mock USDC coin
#[test_only]
module roulette::roulette_test {
  use sui::sui::SUI;
  use sui::coin::{Coin, mint_for_testing};
  use sui::test_scenario::{
    Scenario, begin, ctx, next_tx, end, take_from_sender, take_shared, return_to_sender, return_shared
  };
  use roulette::roulette::{
    AdminCap, Config, test_init, create_config, update_config, get_config_data
  };
  use roulette::common_test::{to_base};
  use roulette::test_accounts::{admin, player};

  public fun setup(scenario: &mut Scenario) {
    test_init(ctx(scenario));
    next_tx(scenario, admin());

    let admin_cap = take_from_sender<AdminCap>(scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(scenario));
    next_tx(scenario, admin());

    create_config(
      &admin_cap,
      50,
      to_base(1),
      to_base(10),
      9474,
      coins,
      ctx(scenario)
    );

    return_to_sender(scenario, admin_cap);
    next_tx(scenario, admin());
  }

  #[test]
  fun test_update_config() {
    let scenario = begin(admin());
    setup(&mut scenario);

    let config = take_shared<Config<SUI>>(&mut scenario);
    let (poolSize, range, min_value, max_value, rate) = get_config_data(&config);

    assert!(poolSize == to_base(10), 1);
    assert!(range == 50, 1);
    assert!(min_value == to_base(1), 1);
    assert!(max_value == to_base(10), 1);
    assert!(rate == 9474, 1);

    let admin_cap = take_from_sender<AdminCap>(&mut scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(&mut scenario));
    next_tx(&mut scenario, admin());

    update_config(
      &admin_cap,
      &mut config,
      range,
      min_value,
      max_value,
      9474,
      coins
    );
    return_to_sender(&mut scenario, admin_cap);
    return_shared(config);
    next_tx(&mut scenario, admin());

    config = take_shared(&mut scenario);
    (poolSize, range, min_value, max_value, rate) = get_config_data(&config);

    assert!(poolSize == to_base(20), 1);        
    return_shared(config);
    end(scenario);
  }
}