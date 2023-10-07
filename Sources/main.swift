import Foundation
import KrakenAPI
import SwiftCSV

private let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: "/Users/gabriele/Projects/SatsNav/ledgers.csv"))

private struct LedgerEntry {
    let txId: String
    let refId: String
    let time: String
    let type: String
    let asset: String
    let amount: String
}

private let rateFormatterFiat = NumberFormatter()
rateFormatterFiat.maximumFractionDigits = 4
rateFormatterFiat.minimumFractionDigits = 0

private let rateFormatterCrypto = NumberFormatter()
rateFormatterCrypto.maximumFractionDigits = 10
rateFormatterCrypto.minimumFractionDigits = 0

private func printTrade(entries: [LedgerEntry]) {
    if entries.count < 2 {
        return
    }

    var from: String,
        to: String,
        amountFrom: String,
        amountTo: String

    if entries[0].amount.starts(with: "-") {
        from = entries[0].asset
        amountFrom = String(entries[0].amount.dropFirst())
        to = entries[1].asset
        amountTo = entries[1].amount
    } else {
        from = entries[1].asset
        amountFrom = String(entries[1].amount.dropFirst())
        to = entries[0].asset
        amountTo = entries[0].amount
    }

    let amountFromDec = Decimal(string: amountFrom)!
    let amountToDec = Decimal(string: amountTo)!
    let rate = (amountFromDec / amountToDec)
    let rateFormatter = from == "EUR" || from == "USD" ? rateFormatterFiat : rateFormatterCrypto

    if from != "EUR" || to != "BTC" {
        return
    }
    print("Traded", amountFrom, from, "for", amountTo, to, "@", rateFormatter.string(for: rate)!)
}

private func sanitizeAssetName(asset: String) -> String {
    if asset == "XXBT" {
        return "BTC"
    }
    if asset == "XXDG" {
        return "DOGE"
    }
    if asset.starts(with: "X") || asset.starts(with: "Z") {
        return String(asset.dropFirst())
    }

    return asset
}

private var ledgers = [LedgerEntry]()
private var ledgersByRefId = [String: [LedgerEntry]]()
// "txid","refid","time","type","subtype","aclass","asset","amount","fee","balance"
try csv.enumerateAsDict { dict in
    let entry = LedgerEntry(txId: dict["txid"] ?? "",
                            refId: dict["refid"] ?? "",
                            time: dict["time"] ?? "",
                            type: dict["type"] ?? "",
                            asset: sanitizeAssetName(asset: dict["asset"] ?? ""),
                            amount: dict["amount"] ?? "")
    ledgers.append(entry)
    if !entry.refId.isEmpty {
        ledgersByRefId[entry.refId, default: []].append(entry)
    }
}

private let ledgersGroupedByRefId = ledgersByRefId.values.filter { $0.count > 1 }

print(ledgers.count)
print(ledgersByRefId.count)
for trade in ledgersGroupedByRefId {
    printTrade(entries: trade)
}

// if let firstTrade = ledgersGroupedByRefId.first {
//
// }
