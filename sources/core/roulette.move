module roulette::roulette {
  use sui::tx_context::{TxContext, sender};
  use sui::object::{Self, UID, uid_to_address};
  use sui::transfer::{transfer, share_object, public_transfer};
  use sui::clock::{Self, Clock};
  use std::option::{Self, Option};
  use sui::vec_map::{Self, VecMap};
  use sui::coin::{Coin, value, split, into_balance, join};
  use sui::balance::{Self, Balance};
  use roulette::drand::{verify_drand_signature, derive_randomness, safe_selection};

  // errors
  let E_INVALID_COIN_VALUE: u64 = 0;
  let E_COIN_NOT_SUPPORTED: u64 = 1;
  
  /// Capability allowing the bearer to execute admin related tasks
  struct AdminCap has key {id: UID}
  
  struct Config has key {
    id: UID,
    /// The address that will be receiving the funds from the ticket purchases
    treasury: address,
    /// The pool of roulette
    pool: Balance<T>,
    /// The list of supported coins that can be used in purchases. The string value is the hash of sui::type_name::TypeName
    /// Note it's the TypeName of T not Coin<T>
    supported_coins: VecMap<vector<u8>, bool>,
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
      treasury: sender(ctx),
      supported_coins: vec_map::empty(),
      range: 50,
    };
    
    transfer(admin_cap, sender(ctx));
    share_object(config);
  }

  [#view]
  public fun get_entity_data(self: &RouletteEntity): (address, u8, u64, u64) {
    (
      self.player,
      self.random,
      self.amount,
      self.prize
    )
  }

  public entity fun play(
    config: &Config,
    drand_sig: vector<u8>,
    drand_prev_sig: vector<u8>,
    bet_values: vector<u8>,
    coins: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
  ) {
    // Check that Coin is supported
    let coin_type = ascii::into_bytes(
      type_name::into_string(type_name::get<T>())
    );
    assert!(is_coin_supported(config, &coin_type), E_COIN_NOT_SUPPORTED);
    assert!(into_balance(coins) >= config.min_value, E_INVALID_COIN_VALUE);
    assert!(into_balance(coins) <= config.max_value, E_INVALID_COIN_VALUE);

    let now = clock::timestamp_ms(clock);

    verify_drand_signature(drand_sig, drand_prev_sig, 0);

    let digest = derive_randomness(drand_sig);
    let random = safe_selection(config.range, &digest);

    let entity = RouletteEntity {
      id: object::new(ctx),
      player: sender(ctx),
      random: random,
      amount: into_balance(coins),
      prize: 0,
    }
    let winned = vector::contains(&bet_values, random);
    /// transfer funds to contract
    public_transfer(split(coins, into_balance(coins), ctx), config.treasury);
    if(winned) {
      entity.prize = value(coins) * config.range * config.rate / vector::length(bet_values) / 10000;
      /// transfer funds to player
    }

    share_object(entity);
  }

  /// Updates the config data
  /// 
  /// # Auth
  /// - Only bearer of the AdminCap is allowed to call this function
  /// 
  /// # Arguments
  /// * `treasury` - The address that will be receiving the funds from the ticket purchases
  public entry fun update_config(
    _cap: &AdminCap,
    config: &mut Config,
    treasury: address,
    supported_coins: vector<ascii::String>,
    range: u8,
    min_value: u64,
    max_value: u64,
    rate: u64,
  ) {
    config.supported_coins = vec_map::empty();
    config.treasury = treasury;
    config.range = range;
    config.min_value = min_value;
    config.max_value = max_value;
    config.rate = rate;

    let len = vector::length(&supported_coins);
    let i = 0;

    while (i < len) {
      let coin_type = *vector::borrow(&supported_coins, i);
      let key = ascii::into_bytes(coin_type);
      vec_map::insert(&mut config.supported_coins, key, true);

      i = i + 1;
    };
  }

  /// CHecks if the given coin type is supported
  public fun is_coin_supported(config: &Config, coin_type: &vector<u8>): bool {
    vec_map::contains(&config.supported_coins, coin_type)
  }
}