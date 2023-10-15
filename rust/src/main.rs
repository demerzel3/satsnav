use bitcoin::{
    bip32::{ChildNumber, ExtendedPubKey},
    Address, PublicKey,
};
use miniscript::{descriptor::Sh, Descriptor};
use secp256k1::Secp256k1;
use sha2::{
    digest::{generic_array::GenericArray, typenum::U32},
    Digest, Sha256,
};
use std::str::FromStr;

fn main() {
    dotenv::dotenv().ok();
    let xpubs = [
        std::env::var("XPUB_1").unwrap(),
        std::env::var("XPUB_2").unwrap(),
        std::env::var("XPUB_3").unwrap(),
    ]
    .map(|xpub| ExtendedPubKey::from_str(&xpub).unwrap())
    .to_vec();

    let secp = Secp256k1::new();

    (0..100).for_each(|i| {
        let rcv_desc = get_multisig_descriptor(i, &xpubs, &secp, false);
        let change_desc = get_multisig_descriptor(i, &xpubs, &secp, true);

        println!("rcv address       {}", get_address(&rcv_desc).unwrap());
        println!(
            "rcv scripthash    {}",
            get_script_hash_for_electrum(&rcv_desc)
        );
        println!("change address    {}", get_address(&change_desc).unwrap());
        println!(
            "change scripthash {}",
            get_script_hash_for_electrum(&change_desc)
        );
    });
}

const SPEND: ChildNumber = ChildNumber::Normal { index: 0 };
const CHANGE: ChildNumber = ChildNumber::Normal { index: 1 };

fn get_multisig_descriptor(
    index: u32,
    xpubs: &Vec<ExtendedPubKey>,
    secp: &Secp256k1<secp256k1::All>,
    is_change: bool,
) -> Descriptor<PublicKey> {
    let change = if is_change { CHANGE } else { SPEND };
    let index = ChildNumber::from_normal_idx(index).unwrap();
    let derivation_path = [change, index];

    let pubkeys = xpubs
        .iter()
        .map(|xpub| xpub.derive_pub(&secp, &derivation_path).unwrap().to_pub())
        .collect();

    return Descriptor::<PublicKey>::Sh(Sh::new_wsh_sortedmulti(2, pubkeys).unwrap());
}

fn get_address(desc: &Descriptor<PublicKey>) -> Result<Address, miniscript::Error> {
    return desc.address(bitcoin::Network::Bitcoin);
}

fn get_script_hash_for_electrum(desc: &Descriptor<PublicKey>) -> String {
    let mut hash: GenericArray<u8, U32> = Sha256::digest(desc.script_pubkey().as_bytes());
    hash.reverse();
    // Reversed because Electrum uses little endian
    return format!("{:x}", hash);
}
