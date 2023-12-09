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

    func read(fileUrl: URL) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: fileUrl)

        var ledgers = [LedgerEntry]()
        // Internal id,Date and time,Transaction type,Coin type,Coin amount,USD Value,Original Reward Coin,Reward Amount In Original Coin,Confirmed
        try csv.enumerateAsDict { dict in
            let typeString = dict["Transaction type"] ?? ""
            // I can ignore this because all the loans have been paid out so they cancel each other.
            // TODO: allocate these funds to a "Celsius-Loan" wallet or something in case they don't cancel out
            if typeString == "Collateral" {
                return
            }
            let type: LedgerEntry.LedgerEntryType = switch dict["Transaction type"] ?? "" {
            case "Transfer": .deposit
            case "Inbound Transfer": .deposit
            case "Reward": .interest
            case "Bonus Token": .bonus
            case "Withdrawal": .withdrawal
            // TODO: how to handle loans?
            case "Loan Interest Payment": .transfer
            case "Loan Principal Payment": .transfer
            default:
                fatalError("Unexpected Celsius transaction type: \(dict["Transaction type"] ?? "undefined")")
            }
            let assetName = dict["Coin type"] ?? ""

            let entry = LedgerEntry(
                wallet: "Celsius",
                id: dict["Internal id"] ?? "",
                groupId: dict["Internal id"] ?? "",
                date: self.dateFormatter.date(from: dict["Date and time"] ?? "") ?? Date.now,
                type: type,
                amount: Decimal(string: dict["Coin amount"] ?? "0") ?? 0,
                asset: Asset(name: assetName == "USDT ERC20" ? "USDT" : assetName, type: .crypto)
            )
            ledgers.append(entry)
        }

        return ledgers
    }
}
