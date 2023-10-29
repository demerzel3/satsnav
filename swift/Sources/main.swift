import CryptoKit
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

private let btcFormatter = NumberFormatter()
btcFormatter.maximumFractionDigits = 8
btcFormatter.minimumFractionDigits = 8

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

private let client = JSONRPCClient(hostName: "electrum1.bluewallet.io", port: 50001)
// private let client = JSONRPCClient(hostName: "bitcoin.lu.ke", port: 50001)
client.start()

private let historyRequests = knownAddresses /* [0 ... 50] */ .map { address in
    JSONRPCRequest.getScripthashHistory(scriptHash: address.scriptHash)
}

guard let history: [GetScriptHashHistoryResult] = await client.send(requests: historyRequests) else {
    print("🚨 Unable to get history")
    exit(1)
}

let storage = TransactionStorage()
// Restore transactions storage from disk
await storage.read()
func retrieveAndStoreTransactions(txIds: [String]) async -> [ElectrumTransaction] {
    let txIdsSet = Set<String>(txIds)
    print("requesting transaction information for", txIdsSet.count, "transactions")

    // Do not request transactions that we have already stored
    let unknownTransactionIds = await storage.notIncludedTxIds(txIds: txIdsSet)
    if unknownTransactionIds.count > 0 {
        let txRequests = Set<String>(unknownTransactionIds).map { JSONRPCRequest.getTransaction(txHash: $0, verbose: true) }
        guard let transactions: [ElectrumTransaction] = await client.send(requests: txRequests) else {
            print("🚨 Unable to get transactions")
            exit(1)
        }

        let storageSize = await storage.store(transactions: transactions)
        print("Retrieved \(transactions.count) transactions, in store: \(storageSize)")

        // Commit transactions storage to disk
        await storage.write()
    }

    return await storage.getTransactions(byIds: txIdsSet)
}

// Manual transactions have usually a number of inputs (in case of consolidation)
// but only one output, + optional change
func isManualTransaction(_ transaction: ElectrumTransaction) -> Bool {
    return transaction.vout.count <= 2
}

let txIds = history.flatMap { $0.map { $0.tx_hash } }
let rootTransactions = await retrieveAndStoreTransactions(txIds: txIds)
let refTransactionIds = rootTransactions
    .filter { isManualTransaction($0) }
    .flatMap { transaction in transaction.vin.map { $0.txid } }
    .compactMap { $0 }
_ = await retrieveAndStoreTransactions(txIds: refTransactionIds)

func satsToBtc(_ amount: Int) -> String {
    btcFormatter.string(from: Double(amount) / 100000000 as NSNumber)!
}

func btcToSats(_ amount: Double) -> Int {
    Int(amount * 100000000)
}

func buildTransaction(transaction: ElectrumTransaction) async -> Transaction {
    var totalIn = 0
    var transactionVin = [TransactionVin]()
    for vin in transaction.vin {
        guard let vinTxId = vin.txid else {
            continue
        }
        guard let vinTx = await storage.getTransaction(byId: vinTxId) else {
            continue
        }
        guard let voutIndex = vin.vout else {
            continue
        }

        let vout = vinTx.vout[voutIndex]
        let sats = btcToSats(vout.value)

        guard let vinAddress = vout.scriptPubKey.address else {
            print("\(vinTxId):\(voutIndex) has no address")
            continue
        }
        guard let vinScriptHash = getScriptHashForElectrum(vout.scriptPubKey) else {
            print("Could not compute script hash for address \(vinAddress)")
            continue
        }

        totalIn += sats
        transactionVin.append(TransactionVin(
            txid: vinTxId,
            voutIndex: voutIndex,
            sats: sats,
            address: Address(id: vinAddress, scriptHash: vinScriptHash)
        ))
    }

    var totalOut = 0
    var transactionVout = [TransactionVout]()
    for vout in transaction.vout {
        guard let voutAddress = vout.scriptPubKey.address else {
            continue
        }

        let sats = btcToSats(vout.value)
        totalOut += sats
        transactionVout.append(TransactionVout(
            sats: sats,
            address: voutAddress
        ))
    }

    let (knownVin, _) = transactionVin.partition { knownAddressIds.contains($0.address.id) }
    let (knownVout, unknownVout) = transactionVout.partition { knownAddressIds.contains($0.address) }

    let type: TransactionType = if
        knownVin.count == transaction.vin.count,
        knownVout.count == transaction.vout.count
    {
        // vin and vout are all known, it's consolidation transaction
        .consolidation(fee: totalOut - totalIn)
    } else if knownVin.count == transaction.vin.count {
        // All vin known, it must be a transfer out of some kind
        .withdrawal(amount: unknownVout.reduce(0) { sum, vout in sum + vout.sats })
    } else if knownVin.count == 0 {
        // No vin is known, must be a deposit
        .deposit(amount: knownVout.reduce(0) { sum, vout in sum + vout.sats })
    } else {
        .unknown
    }

    // print("total amount \(Double(totalIn) / 100000000), fee \(totalIn - totalOut) sats")

    return Transaction(
        txid: transaction.txid,
        time: transaction.time ?? 0,
        rawTransaction: transaction,
        type: type,
        totalInSats: totalIn,
        totalOutSats: totalOut,
        feeSats: totalIn - totalOut,
        vin: transactionVin,
        vout: transactionVout
    )
}

var transactions = [Transaction]()
for rawTransaction in rootTransactions {
    transactions.append(await buildTransaction(transaction: rawTransaction))
}

transactions.sort(by: { a, b in a.time < b.time })

var otherAddresses = Set<Address>()
for transaction in transactions {
    if case .deposit = transaction.type, isManualTransaction(transaction.rawTransaction) {
        // print("Manual Deposit", satsToBtc(amount), transaction.txid)
        // print("vin# \(transaction.rawTransaction.vin.count) (\(transaction.vin.count)) vout# \(transaction.vout.count)")
        print("--- \(transaction.txid) --- other addresses:")
        for vin in transaction.vin {
            otherAddresses.insert(vin.address)
            print(vin.address.id)
        }
        // print()
    } else if case .deposit(let amount) = transaction.type {
        print("External Service Deposit", satsToBtc(amount), transaction.txid)
        // print()
    }
}

print("--- OTHER ADDRESSES ---")
for address in otherAddresses.map({ $0.id }).sorted() {
    print(address)
}

let otherReqs = otherAddresses.map { JSONRPCRequest.getScripthashHistory(scriptHash: $0.scriptHash) }
// print(otherReqs)
if let otherRes: [GetScriptHashHistoryResult] = await client.send(requests: otherReqs) {
    for res in otherRes {
        if res.isEmpty {
            print(res)
        }
    }
} else {
    print("nah...")
}

/*
 BRAIN DUMP:
 - implement error handling in JSONRPCClient to handle this shape of response:
    `{"jsonrpc":"2.0","error":{"code":1,"message":"history too large"},"id":123}`
 - when that kind of response is detected it means the address has too many transactions, so the
   original transaction that was marked as "Manual" is not manual at all, it's part of an external service
 - the thing that was considered a manual deposit must become an external service deposit,
   marked for look up in external data sources (CSV and whatnot)
 - so: tag transactions as manual/external by default using our euristics, but allow it to change and store the change
 - link "other address" with originating transaction to allow updating of transaction tag
 - once cleanup and transaction tagging is complete download all missing transactions by txid and recompute
   external vs manual transactions, rinse and repeat
 - open question: where to store "other addresses"? with knownAddresses? as its separate thing?
   we need a more general solution that can scale beyond knownAddresses / other addresses to multiple wallets maybe?
 */
