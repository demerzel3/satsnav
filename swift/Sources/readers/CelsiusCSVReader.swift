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

class CelsiusCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()

    func read(filePath: String) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: filePath))

        var ledgers = [LedgerEntry]()
        // Internal id,Date and time,Transaction type,Coin type,Coin amount,USD Value,Original Reward Coin,Reward Amount In Original Coin,Confirmed
        try csv.enumerateAsDict { dict in
            let type: LedgerEntry.LedgerEntryType = switch dict["Transaction type"] ?? "" {
            case "Transfer": .Deposit
            case "Inbound Transfer": .Deposit
            case "Reward": .Interest
            case "Bonus Token": .Bonus
            case "Withdrawal": .Withdrawal
            // TODO: how to handle loans?
            case "Collateral": .Transfer
            case "Loan Interest Payment": .Transfer
            case "Loan Principal Payment": .Transfer
            default:
                fatalError("Unexpected Celsius transaction type: \(dict["Transaction type"] ?? "undefined") defaulting to Trade")
            }
            let assetName = dict["Coin type"] ?? ""

            let entry = LedgerEntry(
                provider: .Celsius,
                id: dict["Internal id"] ?? "",
                groupId: dict["Internal id"] ?? "",
                date: self.dateFormatter.date(from: dict["Date and time"] ?? "") ?? Date.now,
                type: type,
                amount: Double(dict["Coin amount"] ?? "0") ?? 0,
                asset: LedgerEntry.Asset(name: assetName, type: assetName == "EUR" ? .fiat : .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
