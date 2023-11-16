
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

class BlockFiCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()

    func read(filePath: String) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: filePath))

        var ledgers = [LedgerEntry]()
        // Cryptocurrency,Amount,Transaction Type,Exchange Rate Per Coin (USD),Confirmed At
        try csv.enumerateAsDict { dict in
            let transactionType = dict["Transaction Type"] ?? ""
            // Ignore these as they are messing up with the ledger
            if transactionType == "BIA Withdraw" {
                return
            }

            let type: LedgerEntry.LedgerEntryType = switch transactionType {
            case "Interest Payment": .interest
            case "Bonus Payment": .bonus
            case "Referral Bonus": .bonus
            case "Trade": .trade
            case "Crypto Transfer": .deposit
            case "Withdrawal": .withdrawal
            // TODO: handle the following better
            case "Withdrawal Fee": .transfer
            default:
                fatalError("Unexpected BlockFi transaction type: \(dict["Transaction Type"] ?? "undefined")")
            }

            let entry = LedgerEntry(
                wallet: "BlockFi",
                id: "\(ledgers.count)",
                groupId: "\(ledgers.count)",
                date: self.dateFormatter.date(from: dict["Confirmed At"] ?? "") ?? Date.now,
                type: type,
                amount: Decimal(string: dict["Amount"] ?? "0") ?? 0,
                asset: LedgerEntry.Asset(name: dict["Cryptocurrency"] ?? "", type: .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
