import Foundation

struct LedgerEntry {
    enum Provider {
        case Onchain
        case Coinbase
        case Kraken
        case Celsius
        case Ledn
    }

    enum LedgerEntryType {
        case Deposit
        case Withdrawal
        case Trade
        case Interest
        case Bonus
        case Transfer // Fallback
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
    let groupId: String // Useful to group together ledgers from the same provider, usually part of the same transaction
    let date: Date
    let type: LedgerEntryType
    let amount: Double
    let asset: Asset
}

protocol CSVReader {
    func read(filePath: String) async throws -> [LedgerEntry]
}
