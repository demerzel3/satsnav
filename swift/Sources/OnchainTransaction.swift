enum OnchainTransaction {
    struct Vout {
        let sats: Int
        let address: Address
    }

    struct Vin {
        let txid: String
        let voutIndex: Int
        let sats: Int
        let address: Address
    }
}
