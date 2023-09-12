// A mock USDC coin
#[test_only]
module roulette::roulette_test {
  use std::debug;
  use sui::sui::SUI;
  use sui::coin::{mint_for_testing};
  use sui::clock::{Clock, create_for_testing, increment_for_testing, destroy_for_testing};
  use sui::test_scenario::{
    Scenario, begin, ctx, next_tx, end, take_from_sender, take_shared, return_to_sender, return_shared
  };
  use roulette::roulette::{
    AdminCap, Config, RouletteEntity, test_init, create_config, update_config, get_config_data, play
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
      36,
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
    assert!(range == 36, 1);
    assert!(min_value == to_base(1), 1);
    assert!(max_value == to_base(10), 1);
    assert!(rate == 9474, 1);

    let admin_cap = take_from_sender<AdminCap>(&mut scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(&mut scenario));
    next_tx(&mut scenario, admin());

    update_config(
      &admin_cap,
      &mut config,
      50,
      min_value,
      max_value,
      9400,
      coins
    );
    return_to_sender(&mut scenario, admin_cap);
    return_shared(config);
    next_tx(&mut scenario, admin());

    config = take_shared(&mut scenario);
    (poolSize, range, min_value, max_value, rate) = get_config_data(&config);

    assert!(poolSize == to_base(20), 1);      
    assert!(range == 50, 1);
    assert!(min_value == to_base(1), 1);
    assert!(max_value == to_base(10), 1);
    assert!(rate == 9400, 1);  
    return_shared(config);
    end(scenario);
  }

  #[test]
  fun test_play_signature_validation() {
    let admin_scenario = begin(admin());
    setup(&mut admin_scenario);
    let config = take_shared<Config<SUI>>(&mut admin_scenario);
    end(admin_scenario);

    let seed = x"0000000000000000000000000000000000000000000000000000000000000123";
    let sign = x"a66f3cdf1147339a3f0021180ba6d178219423ec8f8c69a0059efbca4e6732b1e2cfbbba9a7b2eed315bbf684221668a10563f05345e30c994c50e8f0023dea77133b740a18074bbc77154ee27d4add019406d086f19ea36b1a24c89d1a52a8a";

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let clock = create_for_testing(ctx(&mut player_scenario));
    let bet_values = vector[1];

    play(
      &mut config,
      sign,
      seed,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    let entity = take_from_sender<RouletteEntity>(&mut player_scenario);
    debug::print(&entity);
    
    return_shared(config);
    return_to_sender(&mut player_scenario, entity);
    destroy_for_testing(clock);
    end(player_scenario);
  }

  #[test]
  fun test_prize_of_game() {
    let admin_scenario = begin(admin());
    setup(&mut admin_scenario);
    let config = take_shared<Config<SUI>>(&mut admin_scenario);
    end(admin_scenario);

    let seed = x"0000000000000000000000000000000000000000000000000000000000000123";
    let sign = x"a66f3cdf1147339a3f0021180ba6d178219423ec8f8c69a0059efbca4e6732b1e2cfbbba9a7b2eed315bbf684221668a10563f05345e30c994c50e8f0023dea77133b740a18074bbc77154ee27d4add019406d086f19ea36b1a24c89d1a52a8a";

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let clock = create_for_testing(ctx(&mut player_scenario));
    let bet_values = vector[38, 21, 20, 19]; // 6 expected, win rate is 10.5% so prize is 100 / 10.5 = 9.5238...

    play(
      &mut config,
      sign,
      seed,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    let entity = take_from_sender<RouletteEntity>(&mut player_scenario);
    debug::print(&entity);
    
    return_shared(config);
    return_to_sender(&mut player_scenario, entity);
    destroy_for_testing(clock);
    end(player_scenario);
  }
}