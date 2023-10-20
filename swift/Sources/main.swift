import ElectrumKit
import Foundation
import Grammar
import JSON
import KrakenAPI
import SwiftCSV

private let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: "./ledgers.csv"))

private enum AssetType {
    case fiat
    case crypto
}

private struct Asset {
    let name: String
    let type: AssetType

    init(fromTicker ticker: String) {
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

private struct LedgerEntry {
    let txId: String
    let refId: String
    let time: String
    let type: String
    let asset: Asset
    let amount: Decimal
}

private struct Trade {
    let from: Asset
    let fromAmount: Decimal
    let to: Asset
    let toAmount: Decimal
    let rate: Decimal

    init?(fromLedgers entries: [LedgerEntry]) {
        if entries.count < 2 {
            return nil
        }

        if entries[0].amount < 0 {
            self.from = entries[0].asset
            self.fromAmount = -entries[0].amount
            self.to = entries[1].asset
            self.toAmount = entries[1].amount
        } else {
            self.from = entries[1].asset
            self.fromAmount = -entries[1].amount
            self.to = entries[0].asset
            self.toAmount = entries[0].amount
        }

        self.rate = self.fromAmount / self.toAmount
    }
}

private let rateFormatterFiat = NumberFormatter()
rateFormatterFiat.maximumFractionDigits = 4
rateFormatterFiat.minimumFractionDigits = 0

private let rateFormatterCrypto = NumberFormatter()
rateFormatterCrypto.maximumFractionDigits = 10
rateFormatterCrypto.minimumFractionDigits = 0

private func printTrade(entries: [LedgerEntry]) {
    guard let trade = Trade(fromLedgers: entries) else {
        return
    }

    let rateFormatter = trade.from.type == .fiat ? rateFormatterFiat : rateFormatterCrypto

    if trade.from.name != "EUR" || trade.to.name != "BTC" {
        return
    }
    print("Traded", trade.fromAmount, trade.from.name, "for", trade.toAmount, trade.to.name, "@", rateFormatter.string(for: trade.rate)!)
}

private var ledgers = [LedgerEntry]()
private var ledgersByRefId = [String: [LedgerEntry]]()
// "txid","refid","time","type","subtype","aclass","asset","amount","fee","balance"
try csv.enumerateAsDict { dict in
    let entry = LedgerEntry(txId: dict["txid"] ?? "",
                            refId: dict["refid"] ?? "",
                            time: dict["time"] ?? "",
                            type: dict["type"] ?? "",
                            asset: Asset(fromTicker: dict["asset"] ?? ""),
                            amount: Decimal(string: dict["amount"] ?? "0") ?? 0)
    ledgers.append(entry)
    if !entry.refId.isEmpty {
        ledgersByRefId[entry.refId, default: []].append(entry)
    }
}

private let ledgersGroupedByRefId = ledgersByRefId.values.filter { $0.count > 1 }

print(ledgers.count)
print(ledgersByRefId.count)
// for trade in ledgersGroupedByRefId {
//    printTrade(entries: trade)
// }

// if let firstTrade = ledgersGroupedByRefId.first {
//
// }

// private let electrum = Electrum(hostName: "bitcoin.lu.ke", port: 50001, using: .tcp, debug: true)
// private let transactions = try await electrum.addressTXS(address: knownAddresses[0])
// print(transactions)
//// go back one step
// private let oneStepBackTransaction = try await electrum.transaction(txid: transactions[0].vin[0].txid)
// print(oneStepBackTransaction)

struct Message: Codable {
    let id: Int32
    let jsonrpc: String
    let method: String
    let params: [String]
}

////////////////////////////////////
//////////// Awesome TCP connection
////////////////////////////////////

// private let connection = EasyTCP(hostName: "electrum1.bluewallet.io", port: 50001, waitTime: 30)
// connection.start()
// private var msg = try JSONEncoder().encode(Message(
//    id: 1, jsonrpc: "2.0", method: "blockchain.scripthash.get_history", params: ["ab779523f6d1e361de94c9f47ee19f72c4ec344d42758efd260f2e8a33edccd1"]))
// msg.append("\r\n".data(using: .utf8)!)
//
// print("sending", String(data: msg, encoding: .utf8)!)
//
// await withCheckedContinuation { continuation in
//    connection.send(data: msg) { data in
//        print("continuation: \(data)")
//        print("EasyTCP JSON Receive:")
//        print(String(data: data, encoding: .utf8)!)
//        // let a = try! JSONDecoder().decode(output, from: data)
//        continuation.resume(returning: "")
//    }
// }

////////////////////////////////////
//////////// Magic JSON parser
////////////////////////////////////
private let input =
    """
    {"ciao": 1}{"ciao":2}    
    [1, 2, 3, 4, null, "ciao", 5]
    """
private var inputData = input.data(using: .utf8)!

struct Response: Codable {
    let ciao: Int32
}

// let decoder = try JSON(parsing: input.utf8)
// let response = try JSON.Object(from: decoder)

// do {
//    let response = try JSON.Rule<String.Index>.Root.parse(input.utf8, into: [JSON].self)
//    // let response = try JSON.Rule<String.Index>.Value.parse(diagnosing: input.utf8)
//    print(response)
// } catch let error as ParsingError<String.Index> {
//    let annotated: String = error.annotate(source: input,
//                                           renderer: String.init(_:),
//                                           newline: \.isNewline)
//    print(annotated)
// }

print(input.bytes.count)

var parsingInput: ParsingInput<NoDiagnostics<Data>> = .init(inputData)
while let result: JSON = parsingInput.parse(as: JSON.Rule<Int>.Root?.self) {
    print(result)
}
print("parsed up to @\(parsingInput.index)")
inputData.removeFirst(parsingInput.index)
print("size:", inputData.count, String(data: inputData, encoding: .utf8)!)
