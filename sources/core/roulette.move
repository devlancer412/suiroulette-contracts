module roulette::roulette {
  use sui::tx_context::{TxContext, sender};
  use sui::object::{Self, UID, uid_to_address};
  use sui::transfer::{transfer, share_object, public_transfer};
  use sui::clock::{Self, Clock, timestamp_ms};
  use std::option::{Self, Option};
  use sui::vec_map::{Self, VecMap};
  use sui::coin::{Coin, value, split, into_balance, take};
  use sui::balance::{Self, Balance, join, value};
  use roulette::drand::{verify_drand_signature, derive_randomness, safe_selection};

  // errors
  const E_INVALID_COIN_VALUE: u64 = 0;
  
  /// Capability allowing the bearer to execute admin related tasks
  struct AdminCap has key {id: UID}
  
  struct Config<phantom T> has key {
    id: UID,
    /// The pool of roulette
    pool: Balance<T>,
    /// The range of roulette. Default value is 50
    range: u8,
    /// The minimum amount of bet
    min_value: u64,
    /// The maximum amount of bet
    max_value: u64,
    /// The winning prize rate
    rate: u64
  }

  struct RouletteEntity has key {
    id: UID
    player: address
    random: u8
    amount: u64
    prize: u64
  }

  // init
  fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
      id: object::new(ctx),
    };
    let config = Config {
      id: object::new(ctx),
      pool: balance::zero(),
      range: 50,
      min_value: 0,
      max_value: 0,
      rate: 0,
    };
    
    transfer(admin_cap, sender(ctx));
    share_object(config);
  }

  public fun get_config_data(self: &Config): (u64, u8, u64, u64, u64) {
    (
      value(&self.pool),
      self.range,
      self.min_value,
      self.max_value,
      self.rate,
    )
  }

  public fun get_entity_data(self: &RouletteEntity): (address, u8, u64, u64) {
    (
      self.player,
      self.random,
      self.amount,
      self.prize
    )
  }

  public entity fun play<T>(
    config: &mut Config<T>,
    drand_sig: vector<u8>,
    drand_prev_sig: vector<u8>,
    bet_values: vector<u8>,
    coins: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
  ) {
    let value = into_balance(coins).value();

    assert!(value >= config.min_value, E_INVALID_COIN_VALUE);
    assert!(value <= config.max_value, E_INVALID_COIN_VALUE);

    verify_drand_signature(drand_sig, drand_prev_sig);

    let digest = derive_randomness(drand_sig, timestamp_ms(clock));
    let random = safe_selection(config.range, &digest) + 1;

    let entity = RouletteEntity {
      id: object::new(ctx),
      player: sender(ctx),
      random: random,
      amount: value,
      prize: 0,
    }
    let winned = vector::contains(&bet_values, random);
    /// transfer funds to contract
    join(config.pool, into_balance(coin));
    if(winned) {
      entity.prize = value(coins) * config.range * config.rate / vector::length(bet_values) / 10000;
      /// transfer funds to player
      public_transfer(split(config.pool, entity.prize, sender(ctx)));
    }

    share_object(entity);
  }

  /// Updates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  public entry fun update_config<T>(
    _: &AdminCap,
    config: &mut Config<T>,
    range: u8,
    min_value: u64,
    max_value: u64,
    rate: u64,
    coins: Coin<T>
  ) {
    config.range = range;
    config.min_value = min_value;
    config.max_value = max_value;
    config.rate = rate;
    config.pool = join(config.pool, into_balance(coins));
  }

  
  public entry fun withdraw<T>(
    _: &AdminCap,
    config: &mut Config<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
  ) {
    assert!(amount <= value(&config.pool), EPoolNotEnough);
    let coin = take(&mut config.pool, amount, ctx);
    public_transfer(coin, recipient);
  }
  
  #[test_only]
  public fun test_init(ctx: &mut TxContext) {
    init(ctx)
  }
}
