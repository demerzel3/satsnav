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

// Addresses that are plausibly part of the wallet of the user or have been in the past
private var internalAddresses = Set<Address>(knownAddresses)
// Addresses that we know for sure are external (e.g. many, complex transactions, probably automated)
private var externalAddresses = Set<Address>()

private let client = JSONRPCClient(hostName: "electrum1.bluewallet.io", port: 50001)
// private let client = JSONRPCClient(hostName: "bitcoin.lu.ke", port: 50001)
client.start()

private let storage = TransactionStorage()
// Restore transactions storage from disk
await storage.read()
private func retrieveAndStoreTransactions(txIds: [String]) async -> [ElectrumTransaction] {
    let txIdsSet = Set<String>(txIds)
    print("requesting transaction information for", txIdsSet.count, "transactions")

    // Do not request transactions that we have already stored
    let unknownTransactionIds = await storage.notIncludedTxIds(txIds: txIdsSet)
    if unknownTransactionIds.count > 0 {
        let txRequests = Set<String>(unknownTransactionIds).map { JSONRPCRequest.getTransaction(txHash: $0, verbose: true) }
        guard let transactions: [Result<ElectrumTransaction, JSONRPCError>] = await client.send(requests: txRequests) else {
            print("🚨 Unable to get transactions")
            exit(1)
        }

        // TODO: do something with the errors maybe? at least log them!
        let validTransactions = transactions.compactMap { if case .success(let t) = $0 { t } else { nil } }
        let storageSize = await storage.store(transactions: validTransactions)
        print("Retrieved \(validTransactions.count) transactions, in store: \(storageSize)")

        // Commit transactions storage to disk
        await storage.write()
    }

    return await storage.getTransactions(byIds: txIdsSet)
}

// Manual transactions have usually a number of inputs (in case of consolidation)
// but only one output, + optional change
private func isManualTransaction(_ transaction: ElectrumTransaction) -> Bool {
    return transaction.vout.count <= 2
}

private func hasExternalAddressesInputs(_ transaction: Transaction) -> Bool {
    return transaction.vin.contains(where: { externalAddresses.contains($0.address) })
}

// History cache [ScriptHash: [TxId]]
private var historyCache = [Address: [String]]()

// TODO: study more about how actors work
@MainActor
private func round(no: Int) async -> Int {
    print("---------------------")
    print("---- ROUND \(no) ----")
    print("---------------------")

    let internalAddressesList = internalAddresses.filter { historyCache[$0] == nil }
    let historyRequests = internalAddressesList
        .map { address in
            JSONRPCRequest.getScripthashHistory(scriptHash: address.scriptHash)
        }
    print("Requesting transactions for \(historyRequests.count) addresses")
    guard let history: [Result<GetScriptHashHistoryResult, JSONRPCError>] = await client.send(requests: historyRequests) else {
        print("🚨 Unable to get history")
        exit(1)
    }

    // Collect transaction ids and log failures.
    var txIds = [String](historyCache.values.flatMap { $0 })
    var txIdToAddress = historyCache.reduce(into: [String: Address]()) { result, entry in
        let (address, txIds) = entry
        for txId in txIds where result[txId] == nil {
            result[txId] = address
        }
    }

//    if txIdToAddress.count > 0 {
//        print(txIdToAddress)
//        exit(0)
//    }

    for (address, res) in zip(internalAddressesList, history) {
        print(address.id)

        switch res {
        case .success(let history):
            let historyTxIds = history.map { $0.tx_hash }
            historyCache[address] = historyTxIds
            txIds.append(contentsOf: historyTxIds)
            for txId in historyTxIds {
                txIdToAddress[txId] = address
            }
        case .failure(let error):
            print("🚨 history request failed for address \(address.id)", error)
            // TODO: implement a retry mechanism if error is different from "historyTooLarge"
            print("Moving \(address.id) to external addresses")
            internalAddresses.remove(address)
            externalAddresses.insert(address)
            historyCache.removeValue(forKey: address)
        }
    }

    let rootTransactions = await retrieveAndStoreTransactions(txIds: txIds)
    let refTransactionIds = rootTransactions
        .filter { isManualTransaction($0) }
        .flatMap { transaction in transaction.vin.map { $0.txid } }
        .compactMap { $0 }
    _ = await retrieveAndStoreTransactions(txIds: refTransactionIds)

    var transactions = [Transaction]()
    for rawTransaction in rootTransactions {
        transactions.append(await buildTransaction(
            transaction: rawTransaction,
            // TODO: handle this unwrap gracefully, should not happen but we don't want a crash
            address: txIdToAddress[rawTransaction.txid]!
        ))
    }

    transactions.sort(by: { a, b in a.time < b.time })

    for transaction in transactions {
        if case .deposit = transaction.type,
           // Is a simple transaction
           isManualTransaction(transaction.rawTransaction),
           // None of the inputs are marked as external addresses from previous rounds
           !hasExternalAddressesInputs(transaction)
        {
            // print("Manual Deposit", satsToBtc(amount), transaction.txid)
            // print("vin# \(transaction.rawTransaction.vin.count) (\(transaction.vin.count)) vout# \(transaction.vout.count)")
            print("--- Manual Deposit \(transaction.txid) --- other addresses:")
            for vin in transaction.vin where !internalAddresses.contains(vin.address) {
                internalAddresses.insert(vin.address)
                print(vin.address.id)
            }
        } else if case .deposit(let amount) = transaction.type {
            if hasExternalAddressesInputs(transaction) {
                print("🎉 Marked external from previous round!!")
            }
            print("External Service Deposit", satsToBtc(amount), transaction.txid)
        }
    }

    // Returns the number of addresses added to the internal addresses.
    return internalAddresses.count - internalAddressesList.count
}

func satsToBtc(_ amount: Int) -> String {
    btcFormatter.string(from: Double(amount) / 100000000 as NSNumber)!
}

func btcToSats(_ amount: Double) -> Int {
    Int(amount * 100000000)
}

@MainActor
func buildTransaction(transaction: ElectrumTransaction, address: Address) async -> Transaction {
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
            address: Address(id: vinAddress, scriptHash: vinScriptHash, path: [transaction.txid, address.id] + address.path)
        ))
    }

    var totalOut = 0
    var transactionVout = [TransactionVout]()
    for vout in transaction.vout {
        guard let voutAddress = vout.scriptPubKey.address else {
            continue
        }
        guard let voutScriptHash = getScriptHashForElectrum(vout.scriptPubKey) else {
            print("Could not compute script hash for address \(voutAddress)")
            continue
        }

        let sats = btcToSats(vout.value)
        totalOut += sats
        transactionVout.append(TransactionVout(
            sats: sats,
            address: Address(id: voutAddress, scriptHash: voutScriptHash)
        ))
    }

    let (knownVin, _) = transactionVin.partition { internalAddresses.contains($0.address) }
    let (knownVout, unknownVout) = transactionVout.partition { internalAddresses.contains($0.address) }

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

var no = 1
while no <= 5 {
    let addressesAdded = await round(no: no)
    print("------------------------------")
    print("Round \(no) # addresses added: \(addressesAdded)")
    print("------------------------------")
    no += 1

    if addressesAdded == 0 {
        break
    }
}

print("---- All additional addresses so far 🤔 ---")
for address in internalAddresses where address.path.count > 0 {
    print(address.id, "->", address.path.joined(separator: " -> "))
    print()
}

// let internalAddressesList = internalAddresses.map { $0 }.sorted(by: { $0.id < $1.id })
// let otherReqs = internalAddressesList.map { JSONRPCRequest.getScripthashHistory(scriptHash: $0.scriptHash) }
// if let otherRes: [Result<GetScriptHashHistoryResult, JSONRPCError>] = await client.send(requests: otherReqs) {
//    print("--- OTHER ADDRESSES ---")
//    for (index, res) in otherRes.enumerated() {
//        let address = internalAddressesList[index]
//        print(address.id)
//
//        switch res {
//        case .success(let history):
//            print(history.map { $0.tx_hash })
//        case .failure(let error):
//            if error.historyTooLarge {
//                print("Moving \(address.id) to external addresses")
//                print(internalAddresses.count)
//                internalAddresses.remove(address)
//                print(internalAddresses.count)
//                externalAddresses.insert(address)
//            } else {
//                print("🚨 history request failed", error)
//            }
//        }
//    }
// } else {
//    print("🚨 Failed to fetch history of other addresses")
// }

/*
 BRAIN DUMP:
 - implement error handling in JSONRPCClient to handle this shape of response:
    `{"jsonrpc":"2.0","error":{"code":1,"message":"history too large"},"id":123}`
 - when error message is "history too large" (code: 1) it means the address has too many transactions, so the
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
