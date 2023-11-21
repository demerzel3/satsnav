import Collections
import CryptoKit
import Foundation
import Grammar
import JSON
import JSONDecoding
import KrakenAPI
import SwiftCSV

let btcFormatter = createNumberFormatter(minimumFractionDigits: 8, maximumFranctionDigits: 8)
let fiatFormatter = createNumberFormatter(minimumFractionDigits: 2, maximumFranctionDigits: 2)
private let cryptoRateFormatter = createNumberFormatter(minimumFractionDigits: 0, maximumFranctionDigits: 6)
private let fiatRateFormatter = createNumberFormatter(minimumFractionDigits: 0, maximumFranctionDigits: 2)

private let client = JSONRPCClient(hostName: "electrum1.bluewallet.io", port: 50001)
// private let client = JSONRPCClient(hostName: "bitcoin.lu.ke", port: 50001)
client.start()

private let storage = TransactionStorage()
// Restore transactions storage from disk
await storage.read()

// Addresses that are part of the onchain wallet
private let internalAddresses = Set<Address>(knownAddresses)

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

@MainActor
private func fetchOnchainTransactions(cacheOnly: Bool = false) async -> [LedgerEntry] {
    func writeCache(txIds: [String]) {
        let filePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("rootTransactionIds.plist")
        print(filePath)
        do {
            let data = try PropertyListEncoder().encode(txIds)
            try data.write(to: filePath)
            print("Root tx ids saved successfully!")
        } catch {
            fatalError("Error saving root tx ids: \(error)")
        }
    }

    func readCache() -> [String] {
        let filePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("rootTransactionIds.plist")
        print(filePath)
        do {
            let data = try Data(contentsOf: filePath)
            let txIds = try PropertyListDecoder().decode([String].self, from: data)
            print("Retrieved root tx ids from disk: \(txIds.count)")

            return txIds
        } catch {
            fatalError("Error retrieving root tx ids: \(error)")
        }
    }

    func fetchRootTransactionIds() async -> [String] {
        let internalAddressesList = internalAddresses.map { $0 }
        let historyRequests = internalAddressesList
            .map { address in
                JSONRPCRequest.getScripthashHistory(scriptHash: address.scriptHash)
            }
        print("Requesting transactions for \(historyRequests.count) addresses")
        guard let history: [Result<GetScriptHashHistoryResult, JSONRPCError>] = await client.send(requests: historyRequests) else {
            fatalError("🚨 Unable to get history")
        }

        // Collect transaction ids and log failures.
        var txIds = [String]()
        for (address, res) in zip(internalAddressesList, history) {
            switch res {
            case .success(let history):
                txIds.append(contentsOf: history.map { $0.tx_hash })
            case .failure(let error):
                print("🚨 history request failed for address \(address.id)", error)
            }
        }
        // Save collected txids to cache
        writeCache(txIds: txIds)

        return txIds
    }

    let txIds = cacheOnly ? readCache() : await fetchRootTransactionIds()
    let rootTransactions = await retrieveAndStoreTransactions(txIds: txIds)
    let refTransactionIds = rootTransactions
        .filter { isManualTransaction($0) }
        .flatMap { transaction in transaction.vin.map { $0.txid } }
        .compactMap { $0 }
    _ = await retrieveAndStoreTransactions(txIds: refTransactionIds)

    var entries = [LedgerEntry]()
    for rawTransaction in rootTransactions {
        entries.append(contentsOf: await electrumTransactionToLedgerEntries(rawTransaction))
    }

    return entries
}

func round(_ value: Decimal, precision: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
    var decimalValue = value
    var roundedValue = Decimal()
    NSDecimalRound(&roundedValue, &decimalValue, precision, mode)

    return roundedValue
}

/**
 Convert Double to Decimal, truncating at the 8th decimal
 */
func readBtcAmount(_ amount: Double) -> Decimal {
    var decimalValue = Decimal(amount)
    var roundedValue = Decimal()
    NSDecimalRound(&roundedValue, &decimalValue, 8, .plain)

    return roundedValue
}

@MainActor
func electrumTransactionToLedgerEntries(_ transaction: ElectrumTransaction) async -> [LedgerEntry] {
    var totalIn: Decimal = 0
    var transactionVin = [OnchainTransaction.Vin]()
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
        let amount = readBtcAmount(vout.value)

        guard let vinAddress = vout.scriptPubKey.address else {
            print("\(vinTxId):\(voutIndex) has no address")
            continue
        }
        guard let vinScriptHash = getScriptHashForElectrum(vout.scriptPubKey) else {
            print("Could not compute script hash for address \(vinAddress)")
            continue
        }

        totalIn += amount
        transactionVin.append(OnchainTransaction.Vin(
            txid: vinTxId,
            voutIndex: voutIndex,
            amount: amount,
            address: Address(id: vinAddress, scriptHash: vinScriptHash)
        ))
    }

    var totalOut: Decimal = 0
    var transactionVout = [OnchainTransaction.Vout]()
    for vout in transaction.vout {
        guard let voutAddress = vout.scriptPubKey.address else {
            continue
        }
        guard let voutScriptHash = getScriptHashForElectrum(vout.scriptPubKey) else {
            print("Could not compute script hash for address \(voutAddress)")
            continue
        }

        let amount = readBtcAmount(vout.value)
        totalOut += amount
        transactionVout.append(OnchainTransaction.Vout(
            amount: amount,
            address: Address(id: voutAddress, scriptHash: voutScriptHash)
        ))
    }

    let (knownVin, _) = transactionVin.partition { internalAddresses.contains($0.address) }
    let (knownVout, unknownVout) = transactionVout.partition { internalAddresses.contains($0.address) }

    let fees = totalIn - totalOut
    let types: [(LedgerEntry.LedgerEntryType, Decimal)] = if
        knownVin.count == transaction.vin.count,
        knownVout.count == transaction.vout.count
    {
        // vin and vout are all known, it's consolidation or internal transaction, we only track the fees
        [(.fee, -fees)]
    } else if knownVin.count == transaction.vin.count {
        // All vin known, it must be a transfer out of some kind
        [
            (.withdrawal, -unknownVout.reduce(0) { sum, vout in sum + vout.amount }),
            (.fee, -fees),
        ]
    } else if knownVin.count == 0 {
        // No vin is known, must be a deposit.
        // Split by vout in case we are receiving multiple from different sources, easier to match.
        knownVout.map { (.deposit, $0.amount) }
    } else {
        [(.transfer, 0)]
    }

    let date = Date(timeIntervalSince1970: TimeInterval(transaction.time ?? 0))

    return types.map { type, amount in LedgerEntry(
        wallet: "❄️",
        id: transaction.txid,
        groupId: transaction.txid,
        date: date,
        type: type,
        amount: amount,
        asset: .init(name: "BTC", type: .crypto)
    ) }
}

func formatRate(_ optionalRate: Decimal?, spendType: LedgerEntry.AssetType = .crypto) -> String {
    guard let rate = optionalRate else {
        return "unknown"
    }

    switch spendType {
    case .crypto: return cryptoRateFormatter.string(from: rate as NSNumber)!
    case .fiat: return fiatRateFormatter.string(from: rate as NSNumber)!
    }
}

private var ledgers = try await readCSVFiles(config: [
    (CoinbaseCSVReader(), "../data/Coinbase.csv"),
    (CelsiusCSVReader(), "../data/Celsius.csv"),
    (KrakenCSVReader(), "../data/Kraken.csv"),
    (BlockFiCSVReader(), "../data/BlockFi.csv"),
    (LednCSVReader(), "../data/Ledn.csv"),
    (CoinifyCSVReader(), "../data/Coinify.csv"),

    // TODO: add proper blockchain support?
    (EtherscanCSVReader(), "../data/Eth.csv"),
    (CryptoIdCSVReader(), "../data/Ltc.csv"),
    (DogeCSVReader(), "../data/Doge.csv"),
    (RippleCSVReader(), "../data/Ripple.csv"),
])
ledgers.append(contentsOf: await fetchOnchainTransactions(cacheOnly: true))
ledgers.sort(by: { a, b in a.date < b.date })

let BTC = LedgerEntry.Asset(name: "BTC", type: .crypto)
let groupedLedgers: [GroupedLedger] = groupLedgers(ledgers: ledgers)

let unmatchedTransfers = groupedLedgers.compactMap {
    if case .single(let entry) = $0,
       entry.asset != BTC,
       entry.asset.name != "DOGE",
       entry.asset.name != "ETH",
       entry.asset.name != "LTC",
       entry.asset.type == .crypto,
       entry.type == .deposit || entry.type == .withdrawal
    {
        return entry
    }
    return nil
}

print("--- UNMATCHED TRANSFERS [\(unmatchedTransfers.count)] ---")
for entry in unmatchedTransfers {
    print(abs(entry.amount) > 0.01 ? "‼️" : "", entry)
}

let balances = buildBalances(groupedLedgers: groupedLedgers)
if let btcColdStorage = balances["❄️"]?[BTC] {
    print("total interest BTC", ledgers.filter { $0.asset == BTC && ($0.type == .bonus || $0.type == .interest) }.reduce(0) { $0 + $1.amount })
    print("-- Cold storage --")
    print("total", btcColdStorage.sum)
    print("total without rate", btcColdStorage.unknownSum)
    print("refs without rate, sorted", btcColdStorage.filter { $0.amount > 0.01 && $0.rate == nil }.sorted(by: { a, b in
        a.amount < b.amount
    }).map { "\($0.amount) \($0.wallet)-\($0.id)" })
}
