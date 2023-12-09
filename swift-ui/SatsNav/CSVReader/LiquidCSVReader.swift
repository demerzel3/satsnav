import Foundation
import SwiftCSV

private func createDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    // Set the locale to ensure that the date formatter doesn't get affected by the user's locale.
    formatter.locale = Locale(identifier: "en_US_POSIX")

    return formatter
}

class LiquidCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()
    func read(fileUrl: URL) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: fileUrl)

        var ledgers = [LedgerEntry]()
        // TxId,GroupId,Date,Type,Asset,Amount
        try csv.enumerateAsDict { (dict: [String: String]) in
            let type: LedgerEntry.LedgerEntryType = switch dict["Type"] ?? "" {
            case "deposit": .deposit
            case "trade": .trade
            default:
                fatalError("Unexpected Liquid transaction type: \(dict["Type"] ?? "undefined")")
            }

            let amount = Decimal(string: dict["Amount"] ?? "0") ?? 0
            let date = self.dateFormatter.date(from: dict["Date"] ?? "") ?? Date.now
            let entry = LedgerEntry(
                wallet: "Liquid",
                id: dict["TxId"] ?? "",
                groupId: dict["GroupId"] ?? "",
                date: date,
                type: type,
                amount: amount,
                asset: Asset(name: dict["Asset"] ?? "", type: .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
