import Foundation

struct Transaction {
    enum Provider {
        case Onchain
        case Coinbase
        case Kraken
        case Celsius
        case Ledn
    }

    enum TransactionType {
        case Deposit
        case Withdrawal
        case Trade
        case Interest
        case Bonus
    }

    enum AssetType {
        case fiat
        case crypto
    }

    struct Asset {
        let name: String
        let type: AssetType
    }

    let provider: Provider
    let id: String
    let date: Date
    let type: TransactionType
    let amount: Double
    let asset: Asset
}

protocol CSVReader {
    func read(filePath: String) async throws -> [Transaction]
}
