module roulette::roulette {
  use std::vector;
  use sui::address;
  use std::hash::sha2_256;
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
  
  /// Capability allowing the bearer to execute admin related tasks
  struct AdminCap has key {id: UID}
  
  struct RoundConfig<phantom T> has key {
    id: UID,
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
    players: VecMap<vector<u8>, vector<u8>>,
  }

  struct RouletteEntity has key {
    id: UID,
    player: address,
    amount: u64,
    values: vector<u8>
  }

  struct RoundResult has copy, drop {
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

  public fun get_entity_data(self: &RouletteEntity): (address, u64, vector<u8>) {
    (
      self.player,
      self.amount,
      self.values,
    )
  }

  public entry fun play<T>(
    config: &mut RoundConfig<T>,
    // drand_sig: vector<u8>,
    // drand_seed: vector<u8>,
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
    config.total_amount = config.total_amount - input_value;

    let player_bytes = address::to_bytes(sender(ctx));
    assert!(vec_map::contains(&config.players, &player_bytes) == false, E_ROUND_CLOSED);
    vec_map::insert(&mut config.players, player_bytes, bet_values);

    // verify_drand_signature(drand_sig, drand_seed);

    // // Join funds to contract pool
    // join(&mut config.pool, input_balance);

    // let converted_range = ((config.range as u64) * 10000 - 1) / config.rate + 1;

    // let digest = derive_randomness(drand_seed, timestamp);
    // let random = safe_selection((converted_range as u8), &digest) + 1;

    // let entity = RouletteEntity {
    //   id: object::new(ctx),
    //   seed: drand_seed,
    //   player: sender(ctx),
    //   random: random,
    //   amount: input_value,
    //   prize: 0,
    // };

    // let winned = vector::contains(&bet_values, &random);
    // if(winned) {
    //   entity.prize = input_value * (config.range as u64) / vector::length(&bet_values);
    //   // Transfer funds to player
    //   public_transfer(take(&mut config.pool, entity.prize, ctx), sender(ctx));
    // };

    // emit(NewRouletteEntity {
    //   seed: drand_seed,
    //   player: sender(ctx),
    //   random: random,
    //   amount: input_value,
    //   prize: entity.prize,
    // });

    // transfer(entity, sender(ctx));
  }

  /// Updates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  public entry fun create_round<T>(
    _admin_cap: &AdminCap,
    min_value: u64,
    max_value: u64,
    total_amount: u64,
    period: u64,
    coins: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
  ) {
    let config = RoundConfig<T> {
      id: object::new(ctx),
      min_value: min_value,
      max_value: max_value,
      total_amount: total_amount,
      pool: into_balance(coins),
      closing_time: timestamp_ms(clock) + period,
      players: vec_map::empty(),
    };

    share_object(config);
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
