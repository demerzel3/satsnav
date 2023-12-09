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

    func read(fileUrl: URL) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: fileUrl)

        var ledgers = [LedgerEntry]()
        var ids = [String: Int]()
        // Asset,Type,Time,Amount,Balance,ID
        try csv.enumerateAsDict { dict in
            let date = self.dateFormatter.date(from: dict["Time"] ?? "") ?? Date.now
            let cbId = dict["ID"] ?? ""
            // Coinbase IDs are not unique so we need to add date and an index to keep track of them
            let groupId = "\(cbId)-\(date.ISO8601Format())"
            let amount = Decimal(string: dict["Amount"] ?? "0") ?? 0
            let assetName = dict["Asset"] ?? ""

            let type: LedgerEntry.LedgerEntryType = switch dict["Type"] ?? "" {
            case "Deposit": .deposit
            case "Match": .trade
            case "Withdrawal": .withdrawal
            case "Fee": .fee
            default:
                fatalError("Unexpected Coinbase transaction type: \(dict["Type"] ?? "undefined")")
            }

            let entry = LedgerEntry(
                wallet: "Coinbase",
                id: "\(groupId)-\(ids[groupId, default: 0])",
                groupId: groupId,
                // Add 1 second to the fee entry so that it's always after the trade
                date: type == .fee ? date.addingTimeInterval(1) : date,
                type: type,
                amount: amount,
                asset: Asset(name: assetName, type: assetName == "EUR" ? .fiat : .crypto)
            )
            ledgers.append(entry)
            ids[groupId, default: 0] += 1
        }

        return ledgers
    }
}
