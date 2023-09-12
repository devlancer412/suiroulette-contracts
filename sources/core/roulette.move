module roulette::roulette {
  use std::vector;
  use sui::tx_context::{TxContext, sender};
  use sui::object::{Self, UID};
  use sui::transfer::{transfer, share_object, public_transfer};
  use sui::clock::{Clock, timestamp_ms};
  use sui::coin::{Coin, into_balance, take};
  use sui::balance::{Balance, join, value};
  use roulette::drand::{verify_drand_signature, derive_randomness, safe_selection};

  // errors
  const E_INVALID_COIN_VALUE: u64 = 0;
  const E_POOL_NOT_ENOUGH: u64 = 1;
  
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
    id: UID,
    player: address,
    random: u8,
    amount: u64,
    prize: u64,
  }

  // init
  fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
      id: object::new(ctx),
    };
    
    transfer(admin_cap, sender(ctx));
  }

  public fun get_config_data<T>(self: &Config<T>): (u64, u8, u64, u64, u64) {
    (
      value<T>(&self.pool),
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

  public entry fun play<T>(
    config: &mut Config<T>,
    drand_sig: vector<u8>,
    drand_seed: vector<u8>,
    bet_values: vector<u8>,
    coins: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
  ) {
    let input_balance = into_balance(coins);
    let input_value = value(&input_balance);

    assert!(input_value >= config.min_value, E_INVALID_COIN_VALUE);
    assert!(input_value <= config.max_value, E_INVALID_COIN_VALUE);

    verify_drand_signature(drand_sig, drand_seed);

    let digest = derive_randomness(drand_seed, timestamp_ms(clock));
    let random = safe_selection(config.range, &digest) + 1;

    let entity = RouletteEntity {
      id: object::new(ctx),
      player: sender(ctx),
      random: random,
      amount: input_value,
      prize: 0,
    };
    let winned = vector::contains(&bet_values, &random);

    // Join funds to contract pool
    join(&mut config.pool, input_balance);
    if(winned) {
      entity.prize = input_value * (config.range as u64) * config.rate / vector::length(&bet_values) / 10000;
      // Transfer funds to player
      public_transfer(take(&mut config.pool, entity.prize, ctx), sender(ctx));
    };

    transfer(entity, sender(ctx));
  }

  /// Updates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  public entry fun create_config<T>(
    _admin_cap: &AdminCap,
    range: u8,
    min_value: u64,
    max_value: u64,
    rate: u64,
    coins: Coin<T>,
    ctx: &mut TxContext
  ) {
    let config = Config<T> {
      id: object::new(ctx),
      range: range,
      min_value: min_value,
      max_value: max_value,
      rate: rate,
      pool: into_balance(coins),
    };

    share_object(config);
  }

  /// Updates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  public entry fun update_config<T>(
    _admin_cap: &AdminCap,
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
    join(&mut config.pool, into_balance(coins));
  }

  
  public entry fun withdraw<T>(
    _: &AdminCap,
    config: &mut Config<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
  ) {
    assert!(amount <= value(&config.pool), E_POOL_NOT_ENOUGH);
    let coin = take(&mut config.pool, amount, ctx);
    public_transfer(coin, recipient);
  }
  
  #[test_only]
  public fun test_init(ctx: &mut TxContext) {
    init(ctx)
  }
}
