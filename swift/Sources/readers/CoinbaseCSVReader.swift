import Foundation
import SwiftCSV

private func createDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    // Set the locale to ensure that the date formatter doesn't get affected by the user's locale.
    formatter.locale = Locale(identifier: "en_US_POSIX")

    return formatter
}

class CoinbaseCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()

    func read(filePath: String) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: filePath))

        var ledgers = [LedgerEntry]()
        // Asset,Type,Time,Amount,Balance,ID
        try csv.enumerateAsDict { dict in
            let type: LedgerEntry.LedgerEntryType = switch dict["Type"] ?? "" {
            case "Deposit": .Deposit
            case "Match": .Trade
            case "Fee": .Transfer
            case "Withdrawal": .Withdrawal
            default:
                fatalError("Unexpected Coinbase transaction type: \(dict["type"] ?? "undefined") defaulting to Trade")
            }
            let assetName = dict["Asset"] ?? ""

            let entry = LedgerEntry(
                provider: .Coinbase,
                id: dict["ID"] ?? "",
                groupId: dict["ID"] ?? "",
                date: self.dateFormatter.date(from: dict["Time"] ?? "") ?? Date.now,
                type: type,
                amount: Double(dict["Amount"] ?? "0") ?? 0,
                asset: LedgerEntry.Asset(name: assetName, type: assetName == "EUR" ? .fiat : .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
