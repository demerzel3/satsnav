import ElectrumKit
import Foundation
import Grammar
import JSON
import JSONDecoding
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

private let client = JSONRPCClient(hostName: "electrum1.bluewallet.io", port: 50001)
client.start()

extension JSONRPCRequest {
    static func getScripthashHistory(scriptHash: String) -> JSONRPCRequest {
        return self.init(
            method: "blockchain.scripthash.get_history",
            params: ["scripthash": .string(scriptHash)]
        )
    }

    static func getTransaction(txHash: String, verbose: Bool) -> JSONRPCRequest {
        return self.init(
            method: "blockchain.transaction.get",
            params: ["tx_hash": .string(txHash), "verbose": .bool(verbose)]
        )
    }
}

struct GetScriptHashHistoryResultItem: Decodable {
    let tx_hash: String
    let height: Int
}

typealias GetScriptHashHistoryResult = [GetScriptHashHistoryResultItem]

private let historyRequests = knownAddresses[0 ... 0].map { address in
    JSONRPCRequest.getScripthashHistory(scriptHash: address.scriptHash)
}

guard let history: [GetScriptHashHistoryResult] = await client.send(requests: historyRequests) else {
    print("🚨 Unable to get history")
    exit(1)
}

let storage = TransactionStorage()
func retrieveAndStoreTransactions(txIds: [String]) async -> [ElectrumTransaction] {
    print("requesting transaction information for", txIds.count, "transactions")

    // Do not request transactions that we have already stored
    let filteredIds = await storage.notIncludedTxIds(txIds: txIds)
    let txRequests = filteredIds.map { JSONRPCRequest.getTransaction(txHash: $0, verbose: true) }
    print(txRequests)
    guard let transactions: [ElectrumTransaction] = await client.send(requests: txRequests) else {
        print("🚨 Unable to get transactions")
        exit(1)
    }

    let storageSize = await storage.store(transactions: transactions)
    print("Retrieved \(transactions.count) transactions, in store: \(storageSize)")

    return transactions
}

let txIds = history.flatMap { $0.map { $0.tx_hash } }
let rootTransactions = await retrieveAndStoreTransactions(txIds: txIds)
let refTransactionIds = rootTransactions.flatMap { transaction in
    transaction.vin.map { $0.txid }
}.compactMap { $0 }
_ = await retrieveAndStoreTransactions(txIds: refTransactionIds)

for transaction in rootTransactions {
    print("--- transaction \(transaction.txid) ---")
    var totalIn = 0
    for vin in transaction.vin {
        guard let vinTxId = vin.txid else {
            break
        }
        guard let vinTx = await storage.getTransaction(by: vinTxId) else {
            print("\(vinTxId) not in store")
            break
        }

        guard let voutIndex = vin.vout else {
            break
        }

        let vout = vinTx.vout[voutIndex]
        totalIn += Int(vout.value * 100000000)

        guard let vinAddress = vout.scriptPubKey.address else {
            print("\(vinTxId):\(voutIndex) has no address")
            break
        }

        print("input \(vinAddress): \(vout.value)")
    }

    var totalOut = 0
    for vout in transaction.vout {
        guard let toAddress = vout.scriptPubKey.address else {
            break
        }

        print("output \(toAddress): \(vout.value)")
        totalOut += Int(vout.value * 100000000)
    }

    print("total amount \(Double(totalIn) / 100000000), fee \(totalIn - totalOut) sats")
}
