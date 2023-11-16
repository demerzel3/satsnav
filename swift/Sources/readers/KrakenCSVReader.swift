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
            let startIndex = a.index(a.startIndex, offsetBy: 1)
            // get rid of .HOLD as it's not really useful
            let endIndex = a.index(a.endIndex, offsetBy: a.hasSuffix(".HOLD") ? -5 : 0)
            if a.hasSuffix(".HOLD") {
                print(a, a.hasSuffix(".HOLD"), endIndex)
            }
            self.name = String(a[startIndex ..< endIndex])
            self.type = .fiat
        case let a where a.hasSuffix(".HOLD"):
            let endIndex = a.index(a.endIndex, offsetBy: a.hasSuffix(".HOLD") ? -5 : 0)
            self.name = String(a[a.startIndex ..< endIndex])
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

        var balances = [String: Decimal]()
        var ledgers = [LedgerEntry]()
        // "txid","refid","time","type","subtype","aclass","asset","amount","fee","balance"
        try csv.enumerateAsDict { dict in
            let id = dict["txid"] ?? ""
            let type: LedgerEntry.LedgerEntryType = switch dict["type"] ?? "" {
            case "deposit": .deposit
            case "withdrawal": .withdrawal
            case "trade": .trade
            case "spend": .trade
            case "receive": .trade
            case "staking": .interest
            case "dividend": .interest
            // TODO: handle subtypes for staking
            case "transfer": .transfer
            default:
                fatalError("Unexpected Kraken transaction type: \(dict["type"] ?? "undefined")")
            }

            // Duplicated Deposit/Withdrawal, skip
            if (type == .withdrawal || type == .deposit) && id == "" {
                return
            }

            let ticker = dict["asset"] ?? ""
            let asset = LedgerEntry.Asset(fromKrakenTicker: ticker)
            let amount = Decimal(string: dict["amount"] ?? "0") ?? 0
            let fee = Decimal(string: dict["fee"] ?? "0") ?? 0
            let balance = Decimal(string: dict["balance"] ?? "0") ?? 0
            let entry = LedgerEntry(
                wallet: "Kraken",
                id: id,
                groupId: dict["refid"] ?? "",
                date: self.dateFormatter.date(from: dict["time"] ?? "") ?? Date.now,
                // Failed withdrwals get reaccredited, we want to track those as deposits
                type: type == .withdrawal && amount > 0 ? .deposit : type,
                amount: amount,
                asset: asset
            )

            if fee > 0 {
                ledgers.append(LedgerEntry(
                    wallet: entry.wallet,
                    id: "fee-\(entry.id)",
                    groupId: entry.groupId,
                    date: entry.date,
                    type: .fee,
                    amount: -fee,
                    asset: asset
                ))
            }

            balances[ticker, default: 0] += amount - fee
            ledgers.append(entry)

            // Ledger sanity check
            if balances[ticker, default: 0] != balance {
                fatalError("Wrong balance for \(ticker), is \(balances[ticker, default: 0]), expected \(balance)")
            }
        }

        return ledgers
    }
}
