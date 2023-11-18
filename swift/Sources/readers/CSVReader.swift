import Foundation

struct LedgerEntry: CustomStringConvertible {
    enum LedgerEntryType {
        case deposit
        case withdrawal
        case trade
        case interest
        case bonus
        case fee
        case transfer // Fallback
    }

    enum AssetType {
        case fiat
        case crypto
    }

    struct Asset: Hashable {
        let name: String
        let type: AssetType
    }

    let wallet: String
    let id: String
    let groupId: String // Useful to group together ledgers from the same provider, usually part of the same transaction
    let date: Date
    let type: LedgerEntryType
    let amount: Decimal
    let asset: Asset

    var formattedAmount: String {
        "\(asset.name) \(asset.type == .crypto ? btcFormatter.string(from: amount as NSNumber)! : fiatFormatter.string(from: amount as NSNumber)!)"
    }

    var description: String {
        "\(date) \(wallet) \(type) \(formattedAmount) - \(id)"
    }
}

protocol CSVReader {
    func read(filePath: String) async throws -> [LedgerEntry]
}

func readCSVFiles(config: [(CSVReader, String)]) async throws -> [LedgerEntry] {
    var entries = [LedgerEntry]()

    try await withThrowingTaskGroup(of: [LedgerEntry].self) { group in
        for (reader, filePath) in config {
            group.addTask {
                try await reader.read(filePath: filePath)
            }
        }

        for try await fileEntries in group {
            entries.append(contentsOf: fileEntries)
        }
    }

    return entries
}
