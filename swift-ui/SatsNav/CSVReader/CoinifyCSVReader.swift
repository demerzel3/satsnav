
import Foundation
import SwiftCSV

private func createDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    // Set the locale to ensure that the date formatter doesn't get affected by the user's locale.
    formatter.locale = Locale(identifier: "en_US_POSIX")

    return formatter
}

class CoinifyCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()

    func read(fileUrl: URL) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: fileUrl)

        var ledgers = [LedgerEntry]()
        // Posted Date,Source,Amount,Type,Currency,Txn ID,Ref ID
        try csv.enumerateAsDict { dict in
            let type: LedgerEntry.LedgerEntryType = switch dict["Source"] ?? "" {
            case "Withdrawal": .withdrawal
            case "Deposit": .deposit
            case "Purchase": .trade
            default:
                fatalError("Unexpected Coinify transaction type: \(dict["Source"] ?? "undefined")")
            }

            let amount = Decimal(string: dict["Amount"] ?? "0") ?? 0
            let currency = dict["Currency"] ?? ""
            let entry = LedgerEntry(
                wallet: "Coinify",
                id: dict["Txn ID"] ?? "",
                groupId: dict["Ref ID"] ?? "",
                date: self.dateFormatter.date(from: dict["Posted Date"] ?? "") ?? Date.now,
                type: type,
                amount: amount,
                asset: LedgerEntry.Asset(name: currency, type: currency == "EUR" ? .fiat : .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
