
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

    func read(fileUrl: URL) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: fileUrl)

        var ledgers = [LedgerEntry]()
        var ids = [String: Int]()
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

            let ticker = dict["Cryptocurrency"] ?? ""
            let date = self.dateFormatter.date(from: dict["Confirmed At"] ?? "") ?? Date.now
            let groupId = date.ISO8601Format()
            let entry = LedgerEntry(
                wallet: "BlockFi",
                id: "\(groupId)-\(ids[groupId, default: 0])",
                groupId: "\(groupId)",
                date: date,
                type: type,
                amount: Decimal(string: dict["Amount"] ?? "0") ?? 0,
                asset: LedgerEntry.Asset(name: ticker, type: .crypto)
            )
            ledgers.append(entry)
            ids[groupId, default: 0] += 1
        }

        return ledgers
    }
}
