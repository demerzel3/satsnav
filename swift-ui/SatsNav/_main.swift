// import Collections
// import CryptoKit
import Foundation
// import SwiftCSV
//
//
// private let client = JSONRPCClient(hostName: "electrum1.bluewallet.io", port: 50001)
//// private let client = JSONRPCClient(hostName: "bitcoin.lu.ke", port: 50001)
// client.start()
//
// private let storage = TransactionStorage()
//// Restore transactions storage from disk
// await storage.read()
//
//

// private var ledgers = try await readCSVFiles(config: [
//    (CoinbaseCSVReader(), "../data/Coinbase.csv"),
//    (CelsiusCSVReader(), "../data/Celsius.csv"),
//    (KrakenCSVReader(), "../data/Kraken.csv"),
//    (BlockFiCSVReader(), "../data/BlockFi.csv"),
//    (LednCSVReader(), "../data/Ledn.csv"),
//    (CoinifyCSVReader(), "../data/Coinify.csv"),
//
//    // TODO: add proper blockchain support?
//    (EtherscanCSVReader(), "../data/Eth.csv"),
//    (CryptoIdCSVReader(), "../data/Ltc.csv"),
//    (DogeCSVReader(), "../data/Doge.csv"),
//    (RippleCSVReader(), "../data/Ripple.csv"),
//    (DefiCSVReader(), "../data/Defi.csv"),
//    (LiquidCSVReader(), "../data/Liquid.csv"),
// ])
// ledgers.append(contentsOf: await fetchOnchainTransactions(cacheOnly: true))
// let ledgersCountBeforeIgnore = ledgers.count
// ledgers = ledgers.filter { ledgersMeta["\($0.wallet)-\($0.id)"].map { !$0.ignored } ?? true }
// guard ledgers.count - ledgersCountBeforeIgnore < ledgersMeta.map({ $1.ignored }).count else {
//    fatalError("Some entries in blocklist were not found in the ledger")
// }
//
// ledgers.sort(by: { a, b in a.date < b.date })
//
// let ledgersIndex = ledgers.reduce(into: [String: LedgerEntry]()) { index, entry in
//    assert(index[entry.globalId] == nil, "global id \(entry.globalId) already exist")
//
//    index[entry.globalId] = entry
// }
//
// let BTC = LedgerEntry.Asset(name: "BTC", type: .crypto)
// let groupedLedgers: [GroupedLedger] = groupLedgers(ledgers: ledgers)
//
// let unmatchedTransfers = groupedLedgers.compactMap {
//    if case .single(let entry) = $0,
//       entry.asset != BTC,
//       entry.asset.name != "DOGE",
//       entry.asset.name != "ETH",
//       entry.asset.name != "LTC",
//       entry.asset.type == .crypto,
//       entry.type == .deposit || entry.type == .withdrawal
//    {
//        return entry
//    }
//    return nil
// }
//
// print("--- UNMATCHED TRANSFERS [\(unmatchedTransfers.count)] ---")
// for entry in unmatchedTransfers {
//    print(abs(entry.amount) > 0.01 ? "‼️" : "", entry)
// }
//
// let balances = buildBalances(groupedLedgers: groupedLedgers)
// if let btcColdStorage = balances["❄️"]?[BTC] {
//    print("-- Cold storage --")
//    print("total", btcColdStorage.sum)
//
//    let enrichedRefs: [(ref: Ref, entry: LedgerEntry, comment: String?)] = btcColdStorage
//        .compactMap {
//            guard let entry = ledgersIndex[$0.refId] else {
//                print("Entry not found \($0.refId)")
//                return nil
//            }
//
//            return ($0, entry, ledgersMeta[$0.refId].flatMap { $0.comment })
//        }
//        .filter { $0.entry.type != .bonus && $0.entry.type != .interest }
//        .sorted { a, b in a.ref.refIds.count > b.ref.refIds.count }
//    // .sorted { a, b in a.ref.date < b.ref.date }
//
//    for (ref, _, comment) in enrichedRefs {
//        // let spent = formatFiatAmount(ref.amount * (ref.rate ?? 0))
//        let rate = formatFiatAmount(ref.rate ?? 0)
//        let amount = formatBtcAmount(ref.amount)
//        print("\(ref.date) \(amount) \(rate) (\(ref.count))\(comment.map { _ in " 💬" } ?? "")")
////        for refId in ref.refIds {
////            print(ledgersIndex[refId]!)
////        }
////        break
//    }
// }
//
//// TODO: some ledger ids are not unique, need to find and correct them since we now use them as global references
