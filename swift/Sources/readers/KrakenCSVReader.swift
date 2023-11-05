import Foundation
import SwiftCSV

func createNumberFormatter(minimumFractionDigits: Int, maximumFranctionDigits: Int) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFranctionDigits

    return formatter
}

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
        case let a where a.starts(with: "X"):
            self.name = String(a.dropFirst())
            self.type = .crypto
        case let a where a.starts(with: "Z"):
            self.name = String(a.dropFirst())
            self.type = .fiat
        default:
            self.name = ticker
            self.type = .crypto
        }
    }
}

class KrakenCSVReader: CSVReader {
    private let rateFormatterFiat = createNumberFormatter(minimumFractionDigits: 0, maximumFranctionDigits: 4)
    private let rateFormatterCrypto = createNumberFormatter(minimumFractionDigits: 0, maximumFranctionDigits: 10)
    private let dateFormatter = createDateFormatter()

//    private struct Trade {
//        let from: Asset
//        let fromAmount: Decimal
//        let to: Asset
//        let toAmount: Decimal
//        let rate: Decimal
//
//        init?(fromLedgers entries: [LedgerEntry]) {
//            if entries.count < 2 {
//                return nil
//            }
//
//            if entries[0].amount < 0 {
//                self.from = entries[0].asset
//                self.fromAmount = -entries[0].amount
//                self.to = entries[1].asset
//                self.toAmount = entries[1].amount
//            } else {
//                self.from = entries[1].asset
//                self.fromAmount = -entries[1].amount
//                self.to = entries[0].asset
//                self.toAmount = entries[0].amount
//            }
//
//            self.rate = fromAmount / toAmount
//        }
//    }

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

            let entry = LedgerEntry(
                provider: .Kraken,
                id: dict["txid"] ?? "",
                groupId: dict["refid"] ?? "",
                date: self.dateFormatter.date(from: dict["time"] ?? "") ?? Date.now,
                type: type,
                amount: Double(dict["amount"] ?? "0") ?? 0,
                asset: LedgerEntry.Asset(fromKrakenTicker: dict["asset"] ?? "")
            )
            ledgers.append(entry)
        }

        return ledgers
    }

//    private func printTrade(entries: [LedgerEntry]) {
//        guard let trade = Trade(fromLedgers: entries) else {
//            return
//        }
//
//        let rateFormatter = trade.from.type == .fiat ? rateFormatterFiat : rateFormatterCrypto
//
//        if trade.from.name != "EUR" || trade.to.name != "BTC" {
//            return
//        }
//        print("Traded", trade.fromAmount, trade.from.name, "for", trade.toAmount, trade.to.name, "@", rateFormatter.string(for: trade.rate)!)
//    }
}
