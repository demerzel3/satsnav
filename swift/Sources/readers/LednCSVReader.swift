
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

class LednCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()

    func read(filePath: String) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: filePath))

        var ledgers = [LedgerEntry]()
        // Posted Date,Source,Amount,Type,Currency,Ledn Fee Amount,Fee Currency,Status,Blockchain,Txn ID,Txn Hash,Direction of funds
        try csv.enumerateAsDict { dict in
            let type: LedgerEntry.LedgerEntryType = switch dict["Source"] ?? "" {
            case "Interest": .interest
            case "Withdrawal": .withdrawal
            case "Deposit": .deposit
            // TODO: add something specific for loans maybe?
            case "B2X": .deposit
            default:
                fatalError("Unexpected Ledn transaction type: \(dict["Source"] ?? "undefined")")
            }

            let isSending = dict["Direction of funds"] == "Sending"
            let amount = Decimal(string: dict["Amount"] ?? "0") ?? 0
            let entry = LedgerEntry(
                wallet: "Ledn",
                id: dict["Txn ID"] ?? "",
                groupId: dict["Txn ID"] ?? "",
                date: self.dateFormatter.date(from: dict["Posted Date"] ?? "") ?? Date.now,
                type: type,
                amount: (isSending ? -1 : 1) * amount,
                asset: LedgerEntry.Asset(name: dict["Currency"] ?? "", type: .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
