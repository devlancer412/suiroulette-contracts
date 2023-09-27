module roulette::roulette {
  use std::vector;
  use sui::address;
  use sui::tx_context::{TxContext, sender};
  use sui::object::{Self, UID};
  use sui::vec_map::{Self, VecMap};
  use sui::transfer::{transfer, share_object, public_transfer};
  use sui::clock::{Clock, timestamp_ms};
  use sui::coin::{Coin, into_balance, take};
  use sui::balance::{Balance, join, value};
  use sui::event::{emit};
  use roulette::drand::{verify_drand_signature, derive_randomness, safe_selection};
  use sui::package;

  // errors
  const E_INVALID_COIN_VALUE: u64 = 0;
  const E_ROUND_NOT_AVAILABLE: u64 = 1;
  const E_POOL_NOT_ENOUGH: u64 = 2;
  const E_ROUND_CLOSED: u64 = 3;
  const E_ALREADY_PLACED: u64 = 4;
  const E_ROUND_NOT_FINISHED: u64 = 5;
  
  /// Capability allowing the bearer to execute admin related tasks
  struct AdminCap has key {id: UID}

  struct RouletteConfig has key {
    id: UID,
    current_round: u64
  }

  struct BetEntity has store {
    player: address,
    amount: u64,
    values: vector<u8>
  }
  
  struct RoundConfig<phantom T> has key {
    id: UID,
    /// round id
    round: u64,
    /// The pool of roulette
    pool: Balance<T>,
    /// The range of roulette. Default value is 50
    min_value: u64,
    /// The maximum amount of bet
    max_value: u64,
    /// Total bet amount can bet
    total_amount: u64,
    /// Closing time
    closing_time: u64,
    /// Players
    players: VecMap<vector<u8>, BetEntity>,
  }

  struct NewBetEntity has copy, drop {
    player: address,
    amount: u64,
    values: vector<u8>
  }

  struct RoundResult has copy, drop {
    round: u64,
    seed: vector<u8>,
    random: u8,
  }
  
  // --------------- Witness ---------------

  struct ROULETTE has drop {}

  // init
  fun init(otw: ROULETTE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    public_transfer(publisher, sender(ctx));
    let admin_cap = AdminCap {
      id: object::new(ctx),
    };

    let config = RouletteConfig {
      id: object::new(ctx),
      current_round: 0,
    };
    
    share_object(config);
    transfer(admin_cap, sender(ctx));
  }

  public fun get_round_data<T>(self: &RoundConfig<T>): (u64, u64, u64, u64, u64) {
    (
      value<T>(&self.pool),
      self.min_value,
      self.max_value,
      self.total_amount,
      self.closing_time,
    )
  }
  
  /// Creates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  public entry fun create_round<T>(
    _admin_cap: &mut AdminCap,
    _roulette_config: &mut RouletteConfig,
    min_value: u64,
    max_value: u64,
    total_amount: u64,
    period: u64,
    coins: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
  ) {
    let round_config = RoundConfig<T> {
      id: object::new(ctx),
      round: _roulette_config.current_round,
      min_value: min_value,
      max_value: max_value,
      total_amount: total_amount,
      pool: into_balance(coins),
      closing_time: timestamp_ms(clock) + period,
      players: vec_map::empty(),
    };

    _roulette_config.current_round = _roulette_config.current_round + 1;
    share_object(round_config);
  }

  /// Updates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  public entry fun update_round<T>(
    _admin_cap: &AdminCap,
    config: &mut RoundConfig<T>,
    min_value: u64,
    max_value: u64,
    total_amount: u64,
    coins: Coin<T>
  ) {
    config.min_value = min_value;
    config.max_value = max_value;
    config.total_amount = total_amount;
    join(&mut config.pool, into_balance(coins));
  }

  /// Places bet to the round
  public entry fun bet<T>(
    config: &mut RoundConfig<T>,
    bet_values: vector<u8>,
    coins: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
  ) {
    let input_balance = into_balance(coins);
    let input_value = value(&input_balance);
    let timestamp = timestamp_ms(clock);

    assert!(input_value >= config.min_value, E_INVALID_COIN_VALUE);
    assert!(input_value <= config.max_value, E_INVALID_COIN_VALUE);
    assert!(input_value <= config.total_amount, E_ROUND_NOT_AVAILABLE);
    assert!(timestamp <= config.closing_time, E_ROUND_CLOSED);
    config.total_amount = config.total_amount - input_value;

    let player_bytes = address::to_bytes(sender(ctx));
    assert!(vec_map::contains(&config.players, &player_bytes) == false, E_ALREADY_PLACED);

    let entity = BetEntity {
      player: sender(ctx),
      amount: input_value,
      values: bet_values
    };
    vec_map::insert(&mut config.players, player_bytes, entity);
    
    join(&mut config.pool, input_balance);

    emit(NewBetEntity {
      values: bet_values,
      player: sender(ctx),
      amount: input_value,
    });
  }

  /// Finish round
  public entry fun finish<T>(
    _: &AdminCap,
    config: &mut RoundConfig<T>,
    drand_sig: vector<u8>,
    drand_seed: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
  ) {
    let timestamp = timestamp_ms(clock);
    assert!(timestamp > config.closing_time, E_ROUND_NOT_FINISHED);

    verify_drand_signature(drand_sig, drand_seed);

    let digest = derive_randomness(drand_seed, timestamp);
    let random = safe_selection(38, &digest) + 1;


    let length = vec_map::size(&mut config.players);

    let idx = 0;
    while(idx < length) {
      let (address_bytes, entity) = vec_map::get_entry_by_idx(&mut config.players, idx);
      let winned = vector::contains(&entity.values, &random);
      if(winned) {
        let prize = entity.amount * 36 / vector::length(&entity.values);
        // Transfer funds to player
        public_transfer(take(&mut config.pool, prize, ctx), address::from_bytes(*address_bytes));
      };
      idx = idx + 1;
    };
    
    let remaining_value = value(&config.pool);
    let coin = take(&mut config.pool, remaining_value, ctx);
    public_transfer(coin, sender(ctx));

    emit(RoundResult {
      round: config.round,
      seed: drand_seed,
      random: random,
    });
  }
  
  public entry fun withdraw<T>(
    _: &AdminCap,
    config: &mut RoundConfig<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
  ) {
    assert!(amount <= value(&config.pool), E_POOL_NOT_ENOUGH);
    let coin = take(&mut config.pool, amount, ctx);
    public_transfer(coin, recipient);
  }

  #[test_only]
  public fun test_init(otw: ROULETTE, ctx: &mut TxContext) {
    init(otw, ctx)
  }
}
