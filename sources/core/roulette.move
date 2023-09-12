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

  // errors
  const E_INVALID_COIN_VALUE: u64 = 0;
  const E_ROUND_NOT_AVAILABLE: u64 = 1;
  const E_POOL_NOT_ENOUGH: u64 = 2;
  const E_USED_SEED: u64 = 3;
  
  /// Capability allowing the bearer to execute admin related tasks
  struct AdminCap has key {id: UID}
  
  struct RoundConfig<phantom T> has key {
    id: UID,
    /// The pool of roulette
    pool: Balance<T>,
    /// The range of roulette. Default value is 50
    range: u8,
    /// The minimum amount of bet
    min_value: u64,
    /// The maximum amount of bet
    max_value: u64,
    /// Total bet amount can bet
    remaining_amount: u64,
    /// The winning prize rate
    rate: u64,
    /// Seed use data
    seed_uses: VecMap<vector<u8>, bool>,
  }

  struct RouletteEntity has key {
    id: UID,
    seed: vector<u8>,
    player: address,
    random: u8,
    amount: u64,
    prize: u64,
  }

  struct NewRouletteEntity has copy, drop {
    seed: vector<u8>,
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

  public fun get_config_data<T>(self: &RoundConfig<T>): (u64, u8, u64, u64, u64, u64) {
    (
      value<T>(&self.pool),
      self.range,
      self.min_value,
      self.max_value,
      self.remaining_amount,
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
    config: &mut RoundConfig<T>,
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
    assert!(input_value <= config.remaining_amount, E_ROUND_NOT_AVAILABLE);
    config.remaining_amount = config.remaining_amount - input_value;

    let use_hash = get_seed_use_hash(drand_seed, sender(ctx));
    assert!(validate_seed_use(&config.seed_uses, &use_hash) == false, E_USED_SEED);
    vec_map::insert(&mut config.seed_uses, use_hash, true);

    verify_drand_signature(drand_sig, drand_seed);

    // Join funds to contract pool
    join(&mut config.pool, input_balance);

    let converted_range = ((config.range as u64) * 10000 - 1) / config.rate + 1;

    let digest = derive_randomness(drand_seed, timestamp_ms(clock));
    let random = safe_selection((converted_range as u8), &digest) + 1;

    let entity = RouletteEntity {
      id: object::new(ctx),
      seed: drand_seed,
      player: sender(ctx),
      random: random,
      amount: input_value,
      prize: 0,
    };

    let winned = vector::contains(&bet_values, &random);
    if(winned) {
      entity.prize = input_value * (config.range as u64) / vector::length(&bet_values);
      // Transfer funds to player
      public_transfer(take(&mut config.pool, entity.prize, ctx), sender(ctx));
    };

    emit(NewRouletteEntity {
      seed: drand_seed,
      player: sender(ctx),
      random: random,
      amount: input_value,
      prize: entity.prize,
    });

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
    total_amount: u64,
    rate: u64,
    coins: Coin<T>,
    ctx: &mut TxContext
  ) {
    let config = RoundConfig<T> {
      id: object::new(ctx),
      range: range,
      min_value: min_value,
      max_value: max_value,
      remaining_amount: total_amount,
      rate: rate,
      pool: into_balance(coins),
      seed_uses: vec_map::empty(),
    };

    share_object(config);
  }

  /// Updates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  public entry fun update_config<T>(
    _admin_cap: &AdminCap,
    config: &mut RoundConfig<T>,
    range: u8,
    min_value: u64,
    max_value: u64,
    total_amount: u64,
    rate: u64,
    coins: Coin<T>
  ) {
    config.range = range;
    config.min_value = min_value;
    config.max_value = max_value;
    config.remaining_amount = total_amount;
    config.rate = rate;
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

  public fun get_seed_use_hash(seed: vector<u8>, player: address): vector<u8> {
    let use_bytes = address::to_bytes(player);
    vector::append(&mut use_bytes, seed);

    sha2_256(use_bytes)
  }

  /// CHecks if the given coin type is supported
  public fun validate_seed_use(seed_uses: &VecMap<vector<u8>, bool>, use_hash: &vector<u8>): bool {
    vec_map::contains(seed_uses, use_hash)
  }
  
  #[test_only]
  public fun test_init(ctx: &mut TxContext) {
    init(ctx)
  }
}
