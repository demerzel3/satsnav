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
            let date = self.dateFormatter.date(from: dict["Time"] ?? "") ?? Date.now
            let typeString = dict["Type"] ?? ""
            let id = dict["ID"] ?? ""
            let groupId = "\(id)-\(date.ISO8601Format())"
            let amount = Decimal(string: dict["Amount"] ?? "0") ?? 0
            let assetName = dict["Asset"] ?? ""

            let type: LedgerEntry.LedgerEntryType = switch dict["Type"] ?? "" {
            case "Deposit": .Deposit
            case "Match": .Trade
            case "Withdrawal": .Withdrawal
            case "Fee": .Fee
            default:
                fatalError("Unexpected Coinbase transaction type: \(dict["Type"] ?? "undefined")")
            }

            let entry = LedgerEntry(
                wallet: "Coinbase",
                id: id,
                groupId: groupId,
                date: date,
                type: type,
                amount: amount,
                asset: LedgerEntry.Asset(name: assetName, type: assetName == "EUR" ? .fiat : .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
