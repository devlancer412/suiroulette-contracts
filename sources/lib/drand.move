/// Helper module for working with drand outputs.
/// Currently works with chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
module roulette::drand {
  use std::hash::sha2_256;
  use std::vector;
  use sui::bls12381;

  /// Error codes
  const E_INVALID_RND_LENGTH: u64 = 0;
  const E_INVALID_PROOF: u64 = 1;

  const DRAND_PK: vector<u8> = x"b3882aba835eb999ccfe5402845a6d5fea3ef3f93cbe7e25f065366fbd1a737139f0d18b10e3f3c4898cbf331000c82a";

  /// Check a drand output.
  public fun verify_drand_signature(sig: vector<u8>, seed: vector<u8>) {
    let digest = sha2_256(seed);

    // Verify the signature on the hash.
    assert!(bls12381::bls12381_min_pk_verify(&sig, &DRAND_PK, &digest), E_INVALID_PROOF);
  }

  /// Derive a uniform vector from a drand signature.
  public fun derive_randomness(drand_sig: vector<u8>, timestamp: u64): vector<u8> {
    // Convert timestamp to a byte array in big-endian order.
    let timestamp_bytes: vector<u8> = vector[0, 0, 0, 0, 0, 0, 0, 0];
    let i = 7;

    while (i > 0) {
      let curr_byte = timestamp % 0x100;
      let curr_element = vector::borrow_mut(&mut timestamp_bytes, i);
      *curr_element = (curr_byte as u8);
      timestamp = timestamp >> 8;
      i = i - 1;
    };

    // Compute sha256(drand_sig, timestamp_bytes).
    vector::append(&mut drand_sig, timestamp_bytes);
    sha2_256(drand_sig)
  }

  /// Converts the first 16 bytes of rnd to a u128 number and outputs its modulo with input n.
  /// Since n is u64, the output is at most 2^{-64} biased assuming rnd is uniformly random.
  public fun safe_selection(n: u8, rnd: &vector<u8>): u8 {
    assert!(vector::length(rnd) >= 16, E_INVALID_RND_LENGTH);
    
    let m: u128 = 0;
    let i = 0;
    while (i < 16) {
      m = m << 8;
      let curr_byte = *vector::borrow(rnd, i);
      m = m + (curr_byte as u128);
      i = i + 1;
    };
    let n_128 = (n as u128);
    let module_128  = m % n_128;
    let res = (module_128 as u8);

    res
  }
}