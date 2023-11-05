
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
            let type: LedgerEntry.LedgerEntryType = switch dict["Transaction Type"] ?? "" {
            case "Interest Payment": .Interest
            case "Bonus Payment": .Bonus
            case "Referral Bonus": .Bonus
            case "Trade": .Trade
            case "Crypto Transfer": .Deposit
            case "Withdrawal": .Withdrawal
            // TODO: handle the following two better
            case "Withdrawal Fee": .Transfer
            case "BIA Withdraw": .Transfer
            default:
                fatalError("Unexpected BlockFi transaction type: \(dict["Transaction Type"] ?? "undefined") defaulting to Trade")
            }

            let entry = LedgerEntry(
                provider: .BlockFi,
                id: "",
                groupId: "",
                date: self.dateFormatter.date(from: dict["Confirmed At"] ?? "") ?? Date.now,
                type: type,
                amount: Double(dict["Amount"] ?? "0") ?? 0,
                asset: LedgerEntry.Asset(name: dict["Cryptocurrency"] ?? "", type: .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
