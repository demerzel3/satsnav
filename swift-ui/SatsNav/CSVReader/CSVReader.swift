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

    var globalId: String {
        "\(wallet)-\(id)"
    }

    var formattedAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(amount) : formatFiatAmount(amount))"
    }

    var description: String {
        "\(date) \(wallet) \(type) \(formattedAmount) - \(id)"
    }

    func abs() -> LedgerEntry {
        if amount >= 0 {
            return self
        } else {
            return withAmount(-amount)
        }
    }

    func withAmount(_ amount: Decimal) -> LedgerEntry {
        return LedgerEntry(
            wallet: wallet,
            id: id,
            groupId: groupId,
            date: date,
            type: type,
            amount: amount,
            asset: asset
        )
    }
}

protocol CSVReader {
    func read(fileUrl: URL) async throws -> [LedgerEntry]
}

func readCSVFiles(config: [(CSVReader, String)]) async throws -> [LedgerEntry] {
    var entries = [LedgerEntry]()
    let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    try await withThrowingTaskGroup(of: [LedgerEntry].self) { group in
        for (reader, filePath) in config {
            group.addTask {
                try await reader.read(fileUrl: documentsDirectoryURL.appendingPathComponent(filePath))
            }
        }

        for try await fileEntries in group {
            entries.append(contentsOf: fileEntries)
        }
    }

    return entries
}
