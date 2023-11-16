import Foundation

enum OnchainTransaction {
    struct Vout {
        let amount: Decimal
        let address: Address
    }

    struct Vin {
        let txid: String
        let voutIndex: Int
        let amount: Decimal
        let address: Address
    }
}
