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
    @Published var history: [PortfolioHistoryItem] = []
    @Published var recap: [WalletRecap] = []
    @Published var changes: [BalanceChange] = []
    private var ledgerRepository: LedgerRepository
    private let realmConfiguration: Realm.Configuration
    private var realm: Realm?

    var current: PortfolioHistoryItem {
        history.last ?? PortfolioHistoryItem(date: Date.now, total: 0, bonus: 0, spent: 0)
    }

    private var balances = [String: Balance]()

    init(credentials: Credentials, ledgerRepository: LedgerRepository) {
        self.realmConfiguration = Realm.Configuration(encryptionKey: credentials.localStorageEncryptionKey)
        self.ledgerRepository = ledgerRepository
    }

    func getRefs(byWallet wallet: String, asset: Asset) -> RefsArray {
        guard let walletBalances = balances[wallet] else {
            return []
        }

        guard let assetBalance = walletBalances[asset] else {
            return []
        }

        return assetBalance
    }

    private func updateComputedValues() async {
        let start = Date.now
        let ledgers = await ledgerRepository.getAllLedgerEntries()
        let ledgersById = Dictionary(uniqueKeysWithValues: ledgers.map { ($0.globalId, $0) })
        print("Loaded after \(Date.now.timeIntervalSince(start))s ledgers:\(ledgers.count)")
        let transactions = groupLedgers(ledgers: ledgers)
        print("Grouped after \(Date.now.timeIntervalSince(start))s transactions:\(transactions.count)")
        let (balances, changes) = buildBalances(transactions: transactions)
        print("Built balances after \(Date.now.timeIntervalSince(start))s balances:\(balances.count) changes:\(changes.count)")

        self.balances = balances
        // TODO: restore verify
        // verify(balances: balances, getLedgerById: { id in ledgersById[id] })

        let history = buildBtcHistory(balances: balances, getLedgerById: { id in ledgersById[id] })
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
            self.changes = changes
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

        let maybeLastKrakenLedger = realm.objects(RealmLedgerEntry.self)
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

    func merge(_ newEntries: [LedgerEntry]) async {
        print("-- MERGING")
        let mergedCount = try! await ledgerRepository.merge(newEntries)
        print("-- Merged \(mergedCount) entries")
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

//    private func verify(balances: [String: Balance], getLedgerById: (String) -> LedgerEntry?) {
//        if let btcColdStorage = balances["❄️"]?[BTC] {
//            verifyBalance(balance: btcColdStorage, description: "Cold storage", getLedgerById: getLedgerById)
//        }
//        if let btcKraken = balances["Kraken"]?[BTC] {
//            verifyBalance(balance: btcKraken, description: "Kraken", getLedgerById: getLedgerById)
//        }
//    }
//
//    private func verifyBalance(balance: RefsArray, description: String, getLedgerById: (String) -> LedgerEntry?) {
//        print("-- \(description) --")
//        print("total", balance.sum)
//
//        let enrichedRefs: [(ref: Ref, entry: LedgerEntry, comment: String?)] = balance
//            .compactMap {
//                switch $0.transaction {
//                case .single(let entry):
//                    return ($0, entry, ledgersMeta[entry.globalId].flatMap { $0.comment })
//                case .trade(let spend, let receive):
//                    return ($0, receive, ledgersMeta[receive.globalId].flatMap { $0.comment })
//                case .transfer(let from, let to):
//                    return ($0, to, ledgersMeta[to.globalId].flatMap { $0.comment })
//                }
//            }
//
//        let withoutRate = enrichedRefs
//            .filter { $0.entry.type != .bonus && $0.entry.type != .interest && $0.ref.rate == nil }
//            .map { $0.ref }
//            .sum
//        print("Without rate \(withoutRate)")
//
//        let oneSat = Decimal(string: "0.00000001")!
//        print("Below 1 sat:", enrichedRefs.filter { $0.ref.amount < oneSat }.count, "/", enrichedRefs.count)
//    }

    private func getRealm() async throws -> Realm {
        if realm == nil {
            realm = try await Realm(configuration: realmConfiguration, actor: RealmActor.shared)
        }

        return realm!
    }
}
