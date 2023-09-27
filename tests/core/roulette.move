// A mock USDC coin
#[test_only]
module roulette::roulette_test {
  use std::debug;
  use sui::sui::SUI;
  use sui::coin::{mint_for_testing};
  use sui::clock::{Clock, timestamp_ms, create_for_testing, destroy_for_testing, increment_for_testing};
  use sui::test_scenario::{
    Scenario, begin, ctx, next_tx, end, take_from_sender, take_shared, return_to_sender, return_shared
  };
  use sui::test_utils::create_one_time_witness;
  use roulette::roulette::{
    ROULETTE, AdminCap, RoundConfig, RouletteConfig, test_init, create_round, update_round, get_round_data, bet, finish
  };
  use roulette::common_test::{to_base};
  use roulette::test_accounts::{admin, player};

  public fun setup(scenario: &mut Scenario, clock: &Clock) {
    let otw = create_one_time_witness<ROULETTE>();
    test_init(otw, ctx(scenario));
    next_tx(scenario, admin());

    let admin_cap = take_from_sender<AdminCap>(scenario);
    let roulette_config = take_shared<RouletteConfig>(scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(scenario));
    next_tx(scenario, admin());

    create_round(
      &mut admin_cap,
      &mut roulette_config,
      to_base(1),
      to_base(10),
      to_base(10),
      60 * 1000,
      coins,
      clock,
      ctx(scenario)
    );

    return_to_sender(scenario, admin_cap);
    return_shared(roulette_config);
    next_tx(scenario, admin());
  }

  #[test]
  fun test_update_round() {
    let scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut scenario));
    setup(&mut scenario, &clock);

    let config = take_shared<RoundConfig<SUI>>(&mut scenario);
    let (poolSize, min_value, max_value, total_amount, closing_time) = get_round_data(&config);

    assert!(poolSize == to_base(10), 1);
    assert!(min_value == to_base(1), 1);
    assert!(max_value == to_base(10), 1);
    assert!(total_amount == to_base(10), 1);
    assert!(closing_time == timestamp_ms(&clock) + 60000, 1);

    let admin_cap = take_from_sender<AdminCap>(&mut scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(&mut scenario));
    next_tx(&mut scenario, admin());

    update_round(
      &admin_cap,
      &mut config,
      min_value,
      max_value,
      total_amount,
      coins
    );
    return_to_sender(&mut scenario, admin_cap);
    return_shared(config);
    next_tx(&mut scenario, admin());

    config = take_shared(&mut scenario);
    (poolSize, min_value, max_value, _, _) = get_round_data(&config);

    assert!(poolSize == to_base(20), 1);      
    assert!(min_value == to_base(1), 1);
    assert!(max_value == to_base(10), 1);
    return_shared(config);
    destroy_for_testing(clock);
    end(scenario);
  }

  #[test]
  #[expected_failure(abort_code=roulette::roulette::E_INVALID_COIN_VALUE)]
  fun test_bet_min_value_validation_invalid() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);
    end(admin_scenario);

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1) / 10, ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let bet_values = vector[1];

    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    return_shared(config);
    destroy_for_testing(clock);
    end(player_scenario);
  }

  #[test]
  #[expected_failure(abort_code=roulette::roulette::E_INVALID_COIN_VALUE)]
  fun test_bet_max_value_validation_invalid() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);
    end(admin_scenario);

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(11), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let bet_values = vector[1];

    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    return_shared(config);
    destroy_for_testing(clock);
    end(player_scenario);
  }

  #[test]
  #[expected_failure(abort_code=roulette::roulette::E_ROUND_NOT_AVAILABLE)]
  fun test_bet_total_amount_validation_invalid() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);
    
    let admin_cap = take_from_sender<AdminCap>(&mut admin_scenario);
    let coins = mint_for_testing<SUI>(to_base(10), ctx(&mut admin_scenario));
    next_tx(&mut admin_scenario, admin());

    update_round(
      &admin_cap,
      &mut config,
      to_base(1),
      to_base(10),
      to_base(1) / 10,
      coins
    );
    return_to_sender(&mut admin_scenario, admin_cap);
    end(admin_scenario);

    let player_scenario = begin(player());
    coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let bet_values = vector[1];

    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    return_shared(config);
    destroy_for_testing(clock);
    end(player_scenario);
  }

  #[test]
  #[expected_failure(abort_code=roulette::roulette::E_ROUND_CLOSED)]
  fun test_bet_closing_time_validation_invalid() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);
    end(admin_scenario);

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let bet_values = vector[1];

    increment_for_testing(&mut clock, 60001);
    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    return_shared(config);
    destroy_for_testing(clock);
    end(player_scenario);
  }

  #[test]
  #[expected_failure(abort_code=roulette::roulette::E_ALREADY_PLACED)]
  fun test_bet_duplication_validation_invalid() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);
    end(admin_scenario);

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let bet_values = vector[1];

    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    return_shared(config);
    destroy_for_testing(clock);
    end(player_scenario);
  }

  #[test]
  fun test_play_signature_validation() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let bet_values = vector[1];

    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    let seed = x"0000000000000000000000000000000000000000000000000000000000000123";
    let sign = x"a66f3cdf1147339a3f0021180ba6d178219423ec8f8c69a0059efbca4e6732b1e2cfbbba9a7b2eed315bbf684221668a10563f05345e30c994c50e8f0023dea77133b740a18074bbc77154ee27d4add019406d086f19ea36b1a24c89d1a52a8a";

    let admin_cap = take_from_sender<AdminCap>(&mut admin_scenario);
    increment_for_testing(&mut clock, 60001);
    finish(
      &admin_cap,
      &mut config,
      sign,
      seed,
      &clock,
      ctx(&mut admin_scenario)
    );
    next_tx(&mut admin_scenario, admin());

    return_to_sender(&mut admin_scenario, admin_cap);
    return_shared(config);
    destroy_for_testing(clock);
    end(admin_scenario);
    end(player_scenario);
  }

  #[test]
  #[expected_failure(abort_code=roulette::drand::E_INVALID_PROOF)]
  fun test_play_signature_validation_invalid() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
    let bet_values = vector[1];

    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    next_tx(&mut player_scenario, player());

    let seed = x"0000000000000000000000000000000000000000000000000000000000000123";
    let sign = x"b66f3cdf1147339a3f0021180ba6d178219423ec8f8c69a0059efbca4e6732b1e2cfbbba9a7b2eed315bbf684221668a10563f05345e30c994c50e8f0023dea77133b740a18074bbc77154ee27d4add019406d086f19ea36b1a24c89d1a52a8a";

    let admin_cap = take_from_sender<AdminCap>(&mut admin_scenario);
    increment_for_testing(&mut clock, 60001);
    finish(
      &admin_cap,
      &mut config,
      sign,
      seed,
      &clock,
      ctx(&mut admin_scenario)
    );
    next_tx(&mut admin_scenario, admin());

    return_to_sender(&mut admin_scenario, admin_cap);
    return_shared(config);
    destroy_for_testing(clock);
    end(admin_scenario);
    end(player_scenario);
  }

  #[test]
  fun test_prize() {
    let admin_scenario = begin(admin());
    let clock = create_for_testing(ctx(&mut admin_scenario));
    setup(&mut admin_scenario, &clock);
    let config = take_shared<RoundConfig<SUI>>(&mut admin_scenario);

    let player_scenario = begin(player());
    let coins = mint_for_testing<SUI>(to_base(1), ctx(&mut player_scenario));
    next_tx(&mut player_scenario, player());
       let bet_values = vector[36, 21, 20, 19]; // 6 expected, win rate is 10.5% so prize is 100 / 10.5 = 9.5238...

    bet(
      &mut config,
      bet_values,
      coins,
      &clock,
      ctx(&mut player_scenario)
    );
    let effect = next_tx(&mut player_scenario, player());
    debug::print(&effect);

    let seed = x"0000000000000000000000000000000000000000000000000000000000000123";
    let sign = x"a66f3cdf1147339a3f0021180ba6d178219423ec8f8c69a0059efbca4e6732b1e2cfbbba9a7b2eed315bbf684221668a10563f05345e30c994c50e8f0023dea77133b740a18074bbc77154ee27d4add019406d086f19ea36b1a24c89d1a52a8a";

    let admin_cap = take_from_sender<AdminCap>(&mut admin_scenario);
    increment_for_testing(&mut clock, 60001);
    finish(
      &admin_cap,
      &mut config,
      sign,
      seed,
      &clock,
      ctx(&mut admin_scenario)
    );
    effect = next_tx(&mut admin_scenario, admin());
    debug::print(&effect);

    return_to_sender(&mut admin_scenario, admin_cap);
    return_shared(config);
    destroy_for_testing(clock);
    end(admin_scenario);
    end(player_scenario);
  }
}