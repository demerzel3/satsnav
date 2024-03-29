import Foundation
import RealmSwift

struct WalletRecap: Identifiable, Codable {
    let wallet: String
    let count: Int
    let sumByAsset: [Asset: Decimal]

    var id: String { wallet }
}

enum CacheKey: String, PersistableEnum {
    case balancesManagerHistory
    case balancesManagerRecap
}

final class CacheItem: Object {
    @Persisted(primaryKey: true) var key: CacheKey
    @Persisted var data: Data

    convenience init(key: CacheKey, value: any Codable) throws {
        self.init()
        self.key = key
        self.data = try JSONEncoder().encode(value)
    }

    func getValue<T: Codable>() throws -> T {
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@globalActor actor RealmActor: GlobalActor {
    static var shared = RealmActor()
}

final class BalancesManager: ObservableObject {
    @Published var history = [PortfolioHistoryItem]()
    @Published var recap = [WalletRecap]()
    private let realmConfiguration: Realm.Configuration
    private var realm: Realm?

    var current: PortfolioHistoryItem {
        history.last ?? PortfolioHistoryItem(date: Date.now, total: 0, bonus: 0, spent: 0)
    }

    private var balances = [String: Balance]()

    init(credentials: Credentials) {
        self.realmConfiguration = Realm.Configuration(encryptionKey: credentials.localStorageEncryptionKey)
    }

    func getRefs(byWallet wallet: String, asset: Asset) -> RefsArray {
        guard let walletBalances = balances[wallet] else {
            return RefsArray()
        }

        guard let assetBalance = walletBalances[asset] else {
            return RefsArray()
        }

        return assetBalance
    }

    @RealmActor
    private func updateComputedValues() async {
        let start = Date.now
        let realm = try! await getRealm()
        let ledgers = realm.objects(LedgerEntry.self).sorted { a, b in a.date < b.date }
        print("Loaded after \(Date.now.timeIntervalSince(start))s \(ledgers.count)")
        let groupedLedgers = groupLedgers(ledgers: ledgers)
        print("Grouped after \(Date.now.timeIntervalSince(start))s \(groupedLedgers.count)")
        balances = buildBalances(groupedLedgers: groupedLedgers, debug: false)
        print("Built balances after \(Date.now.timeIntervalSince(start))s \(balances.count)")

        verify(balances: balances, getLedgerById: { id in
            realm.object(ofType: LedgerEntry.self, forPrimaryKey: id)
        })

        let history = buildBtcHistory(balances: balances, getLedgerById: { id in
            realm.object(ofType: LedgerEntry.self, forPrimaryKey: id)
        })
        print("Ready after \(Date.now.timeIntervalSince(start))s")

        let recap = balances.map { wallet, balance in
            WalletRecap(
                wallet: wallet,
                // TODO: this is number of refs, should be number of ledger entries
                count: balance.values.reduce(0) { $0 + $1.count },
                sumByAsset: balance.mapValues { $0.sum }
            )
        }.sorted(by: { a, b in
            b.sumByAsset[BTC, default: 0] < a.sumByAsset[BTC, default: 0]
        })

        // Update published values
        await MainActor.run {
            self.history = history
            self.recap = recap
        }
    }

    @RealmActor
    func update() async {
        let realm = try! await getRealm()
        // Read data from cache
        if history.isEmpty && recap.isEmpty {
            if let historyCache = realm.object(ofType: CacheItem.self, forPrimaryKey: CacheKey.balancesManagerHistory),
               let history: [PortfolioHistoryItem] = try? historyCache.getValue()
            {
                await MainActor.run { self.history = history }
            }
            if let recapCache = realm.object(ofType: CacheItem.self, forPrimaryKey: CacheKey.balancesManagerRecap),
               let recap: [WalletRecap] = try? recapCache.getValue()
            {
                await MainActor.run { self.recap = recap }
            }
        }

        await updateOnchainWallets()
        await updateServiceAccounts()
        await updateComputedValues()

        // Store computed values in cache
        do {
            try realm.write {
                try realm.add(CacheItem(key: .balancesManagerHistory, value: history), update: .modified)
                try realm.add(CacheItem(key: .balancesManagerRecap, value: recap), update: .modified)
            }
        } catch {
            print("Error while writing to cache", error)
        }
    }

    @RealmActor
    private func updateOnchainWallets() async {
        let realm = try! await getRealm()
        let wallets = realm.objects(OnchainWallet.self)

        // TODO: add support for multiple onchain wallets
        guard let wallet = wallets.first else {
            return
        }

        let fetcher = await OnchainTransactionsFetcher()
        defer {
            fetcher.shutdown()
        }

        let ledgers = await fetcher.fetchOnchainTransactions(addresses: wallet.addresses.map { $0.toAddress() })
        await merge(ledgers)
    }

    @RealmActor
    private func updateServiceAccounts() async {
        let realm = try! await getRealm()
        let accounts = realm.objects(ServiceAccount.self)

        // TODO: Add support for multiple accounts
        guard let account = accounts.first else {
            return
        }

        let maybeLastKrakenLedger = realm.objects(LedgerEntry.self)
            .filter { $0.wallet == "Kraken" && $0.id.starts(with: "L") }
            .sorted { a, b in a.date < b.date }.last
        guard let lastKrakenLedger = maybeLastKrakenLedger else {
            // TODO: inform the user that they must import data via CSV as a baseline to avoid too many API calls
            return
        }

        let client = KrakenClient(apiKey: account.apiKey, apiSecret: account.apiSecret)
        let ledgers = await client.getLedgers(afterLedgerId: lastKrakenLedger.id)

        await merge(ledgers)
    }

    @RealmActor
    func merge(_ newEntries: [LedgerEntry]) async {
        let realm = try! await getRealm()
        print("-- MERGING")
        try! realm.write {
            var deletedCount = 0
            for entry in newEntries {
                if let oldEntry = realm.object(ofType: LedgerEntry.self, forPrimaryKey: entry.globalId) {
                    realm.delete(oldEntry)
                    deletedCount += 1
                }
                realm.add(entry)
            }
            print("-- Deleted \(deletedCount) entries")
            print("-- Added \(newEntries.count) entries")
        }
        print("-- MERGING ENDED")
    }

    @RealmActor
    func addOnchainWallet(_ wallet: OnchainWallet) async {
        let realm = try! await getRealm()
        try! realm.write {
            realm.add(wallet)
        }

        await update()
    }

    @RealmActor
    func addServiceAccount(_ account: ServiceAccount) async {
        let realm = try! await getRealm()
        try! realm.write {
            realm.add(account)
        }

        await update()
    }

    private func verify(balances: [String: Balance], getLedgerById: (String) -> LedgerEntry?) {
        if let btcColdStorage = balances["❄️"]?[BTC] {
            print("-- Cold storage --")
            print("total", btcColdStorage.sum)

            let enrichedRefs: [(ref: Ref, entry: LedgerEntry, comment: String?)] = btcColdStorage
                .compactMap {
                    guard let entry = getLedgerById($0.refId) else {
                        print("Entry not found \($0.refId)")
                        return nil
                    }

                    return ($0, entry, ledgersMeta[$0.refId].flatMap { $0.comment })
                }
            // .filter { $0.entry.type != .bonus && $0.entry.type != .interest }
            // .filter { $0.ref.rate == nil }
            // .sorted { a, b in a.ref.refIds.count > b.ref.refIds.count }
            // .sorted { a, b in a.ref.date < b.ref.date }
            // .sorted { a, b in a.ref.rate ?? 0 < b.ref.rate ?? 0 }

            let withoutRate = enrichedRefs
                .filter { $0.entry.type != .bonus && $0.entry.type != .interest && $0.ref.rate == nil }
                .map { $0.ref }
                .sum
            print("Without rate \(withoutRate)")
            // assert(withoutRate < 0.032, "Something broke in the grouping")

            let oneSat = Decimal(string: "0.00000001")!
            print("Below 1 sat:", enrichedRefs.filter { $0.ref.amount < oneSat }.count, "/", enrichedRefs.count)
//            for (ref, _, comment) in enrichedRefs where ref.amount < oneSat {
//                // let spent = formatFiatAmount(ref.amount * (ref.rate ?? 0))
//                let rate = formatFiatAmount(ref.rate ?? 0)
//                let amount = formatBtcAmount(ref.amount)
//                print("\(ref.date) \(amount) \(rate) (\(ref.count))\(comment.map { _ in " 💬" } ?? "")")
            ////                for refId in ref.refIds {
            ////                    print(ledgersIndex[refId]!)
            ////                }
            ////                break
//            }
        }
        if let btcKraken = balances["Kraken"]?[BTC] {
            print("-- Kraken --")
            print("total", btcKraken.sum)
        }
    }

    private func getRealm() async throws -> Realm {
        if realm == nil {
            realm = try await Realm(configuration: realmConfiguration, actor: RealmActor.shared)
        }

        return realm!
    }
}
