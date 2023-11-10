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

            // Fee usually follows the match it applies to, if that's the case we want to amend it
            if typeString == "Fee" {
                guard let lastEntry = ledgers.popLast() else {
                    fatalError("Unable to apply fee \(amount) \(assetName), is first entry")
                }

                guard lastEntry.asset.name == assetName && lastEntry.groupId == groupId && lastEntry.type == .Trade else {
                    fatalError("Unable to apply fee \(amount) \(assetName), previous entry does not match")
                }

                ledgers.append(LedgerEntry(
                    wallet: lastEntry.wallet,
                    id: lastEntry.id,
                    groupId: lastEntry.groupId,
                    date: lastEntry.date,
                    type: lastEntry.type,
                    amount: lastEntry.amount + amount,
                    asset: lastEntry.asset
                ))

                return
            }

            let type: LedgerEntry.LedgerEntryType = switch dict["Type"] ?? "" {
            case "Deposit": .Deposit
            case "Match": .Trade
            case "Withdrawal": .Withdrawal
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
