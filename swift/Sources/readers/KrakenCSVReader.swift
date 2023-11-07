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

extension LedgerEntry.Asset {
    init(fromKrakenTicker ticker: String) {
        switch ticker {
        case "XXBT":
            self.name = "BTC"
            self.type = .crypto
        case "XXDG":
            self.name = "DOGE"
            self.type = .crypto
        case "XBT.M":
            self.name = "BTC"
            self.type = .crypto
        case let a where a.hasPrefix("X"):
            self.name = String(a.dropFirst())
            self.type = .crypto
        case let a where a.hasPrefix("Z"):
            self.name = String(a.dropFirst())
            self.type = .fiat
        default:
            self.name = ticker
            self.type = .crypto
        }
    }
}

class KrakenCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()

    func read(filePath: String) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: filePath))

        var ledgers = [LedgerEntry]()
        // "txid","refid","time","type","subtype","aclass","asset","amount","fee","balance"
        try csv.enumerateAsDict { dict in
            let type: LedgerEntry.LedgerEntryType = switch dict["type"] ?? "" {
            case "deposit": .Deposit
            case "withdrawal": .Withdrawal
            case "trade": .Trade
            case "spend": .Trade
            case "receive": .Trade
            case "staking": .Interest
            case "dividend": .Interest
            // TODO: handle subtypes for staking
            case "transfer": .Transfer
            default:
                fatalError("Unexpected Kraken transaction type: \(dict["type"] ?? "undefined") defaulting to Trade")
            }
            let ticker = dict["asset"] ?? ""
            let asset = LedgerEntry.Asset(fromKrakenTicker: ticker)
            let entry = LedgerEntry(
                wallet: ticker.hasSuffix(".M") ? "Kaken Staking" : "Kraken",
                id: dict["txid"] ?? "",
                groupId: dict["refid"] ?? "",
                date: self.dateFormatter.date(from: dict["time"] ?? "") ?? Date.now,
                type: type,
                amount: Double(dict["amount"] ?? "0") ?? 0,
                asset: asset
            )
            ledgers.append(entry)
        }

        return ledgers.filter { ($0.type != .Withdrawal && $0.type != .Deposit) || $0.id == "" }
    }
}
