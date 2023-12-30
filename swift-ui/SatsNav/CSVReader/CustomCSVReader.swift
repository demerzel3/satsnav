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

class CustomCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()
    func read(fileUrl: URL) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: fileUrl)

        var ledgers = [LedgerEntry]()
        // Wallet,Transaction ID,Group ID,Date/Time,Type,Amount,Asset
        try csv.enumerateAsDict { (dict: [String: String]) in
            let type: LedgerEntry.LedgerEntryType = switch dict["Type"] ?? "" {
            case "Deposit": .deposit
            case "Receive": .deposit
            case "Withdrawal": .withdrawal
            case "Send": .withdrawal
            case "Trade": .trade
            case "Fee": .fee
            default:
                fatalError("Unexpected Custom transaction type: \(dict["Type"] ?? "undefined")")
            }

            let amount = Decimal(string: dict["Amount"] ?? "0") ?? 0
            let date = self.dateFormatter.date(from: dict["Date/Time"] ?? "") ?? Date.now
            let assetName = dict["Asset"] ?? ""
            let entry = LedgerEntry(
                wallet: dict["Wallet"] ?? "",
                id: dict["Transaction ID"] ?? "",
                groupId: dict["Group ID"] ?? "",
                date: date,
                type: type,
                amount: amount,
                asset: Asset(name: assetName, type: assetName == "EUR" ? .fiat : .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
