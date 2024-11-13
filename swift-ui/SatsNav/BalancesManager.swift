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
    private static var cachedRealm: Realm?

    static func getRealm(credentials: Credentials) throws -> Realm {
        try Realm(configuration: Realm.Configuration(encryptionKey: credentials.localStorageEncryptionKey))
    }
}

@MainActor
final class BalancesState: ObservableObject {
    @Published var history: [PortfolioHistoryItem] = []
    @Published var recap: [WalletRecap] = []
    @Published var changes: [BalanceChange] = []

    var current: PortfolioHistoryItem {
        history.last ?? PortfolioHistoryItem(date: Date.now, total: 0, bonus: 0, spent: 0)
    }

    func update(history: [PortfolioHistoryItem], recap: [WalletRecap], changes: [BalanceChange]) {
        self.history = history
        self.recap = recap
        self.changes = changes
    }
}

@RealmActor
final class CacheRepository {
    private let credentials: Credentials

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    private func getRealm() throws -> Realm {
        return try RealmActor.getRealm(credentials: credentials)
    }

    func loadCache() async throws -> (history: [PortfolioHistoryItem], recap: [WalletRecap])? {
        let realm = try getRealm()

        let maybeHistory: [PortfolioHistoryItem]? = realm.object(ofType: CacheItem.self,
                                                                 forPrimaryKey: CacheKey.balancesManagerHistory)
            .flatMap { try? $0.getValue() }

        let maybeRecap: [WalletRecap]? = realm.object(ofType: CacheItem.self,
                                                      forPrimaryKey: CacheKey.balancesManagerRecap)
            .flatMap { try? $0.getValue() }

        if let history = maybeHistory, let recap = maybeRecap {
            return (history, recap)
        }
        return nil
    }

    func saveCache(history: [PortfolioHistoryItem], recap: [WalletRecap]) async throws {
        let realm = try getRealm()
        try realm.write {
            try realm.add(CacheItem(key: .balancesManagerHistory, value: history), update: .modified)
            try realm.add(CacheItem(key: .balancesManagerRecap, value: recap), update: .modified)
        }
    }
}

final actor BalancesManager {
    private let state: BalancesState
    private let cacheRepository: CacheRepository
    private let ledgerRepository: LedgerRepository
    private let onchainWalletRepository: OnchainWalletRepository
    private var balances = [String: Balance]()

    init(state: BalancesState, cacheRepository: CacheRepository, ledgerRepository: LedgerRepository, onchainWalletRepository: OnchainWalletRepository) async {
        self.state = state
        self.cacheRepository = cacheRepository
        self.onchainWalletRepository = onchainWalletRepository
        self.ledgerRepository = ledgerRepository
    }

    func update() async throws {
        // Load state from cache if possible
        if await state.history.isEmpty, await state.recap.isEmpty {
            if let (history, recap) = try? await cacheRepository.loadCache() {
                await state.update(history: history, recap: recap, changes: [])
            }
        }

        try await updateOnchainWallets()
        // await updateServiceAccounts()
        try await updateComputedValues()

        // Save state to cache
        let history = await state.history
        let recap = await state.recap
        try? await cacheRepository.saveCache(history: history, recap: recap)
    }

    private func updateOnchainWallets() async throws {
        let wallets = try await onchainWalletRepository.getAllOnchainWallets()

        // TODO: add support for multiple onchain wallets
        guard let wallet = wallets.first else {
            return
        }

        let fetcher = await OnchainTransactionsFetcher()
        let ledgers = await fetcher.fetchOnchainTransactions(addresses: wallet.addresses)
        await merge(ledgers)
        await fetcher.shutdown()
    }

    private func updateComputedValues() async throws {
        let start = Date.now
        let ledgers = try await ledgerRepository.getAllLedgerEntries()
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
        await state.update(history: history, recap: recap, changes: changes)
    }

    func merge(_ newEntries: [LedgerEntry]) async {
        print("-- MERGING")
        let mergedCount = try! await ledgerRepository.merge(newEntries)
        print("-- Merged \(mergedCount) entries")
        print("-- MERGING ENDED")
    }

    func addOnchainWallet(_ wallet: OnchainWallet) async throws {
        try await onchainWalletRepository.add(wallet)
    }
}

// final class BalancesManager: ObservableObject {
//    @Published var history: [PortfolioHistoryItem] = []
//    @Published var recap: [WalletRecap] = []
//    @Published var changes: [BalanceChange] = []
//    private var ledgerRepository: LedgerRepository
//    private let realmConfiguration: Realm.Configuration
//    private var realm: Realm?
//
//    var current: PortfolioHistoryItem {
//        history.last ?? PortfolioHistoryItem(date: Date.now, total: 0, bonus: 0, spent: 0)
//    }
//
//    private var balances = [String: Balance]()
//
//    init(credentials: Credentials, ledgerRepository: LedgerRepository) {
//        self.realmConfiguration = Realm.Configuration(encryptionKey: credentials.localStorageEncryptionKey)
//        self.ledgerRepository = ledgerRepository
//    }
//
//    func getRefs(byWallet wallet: String, asset: Asset) -> RefsArray {
//        guard let walletBalances = balances[wallet] else {
//            return []
//        }
//
//        guard let assetBalance = walletBalances[asset] else {
//            return []
//        }
//
//        return assetBalance
//    }
//
//    private func updateComputedValues() async {
//        let start = Date.now
//        let ledgers = try await ledgerRepository.getAllLedgerEntries()
//        let ledgersById = Dictionary(uniqueKeysWithValues: ledgers.map { ($0.globalId, $0) })
//        print("Loaded after \(Date.now.timeIntervalSince(start))s ledgers:\(ledgers.count)")
//        let transactions = groupLedgers(ledgers: ledgers)
//        print("Grouped after \(Date.now.timeIntervalSince(start))s transactions:\(transactions.count)")
//        let (balances, changes) = buildBalances(transactions: transactions)
//        print("Built balances after \(Date.now.timeIntervalSince(start))s balances:\(balances.count) changes:\(changes.count)")
//
//        self.balances = balances
//        // TODO: restore verify
//        // verify(balances: balances, getLedgerById: { id in ledgersById[id] })
//
//        let history = buildBtcHistory(balances: balances, getLedgerById: { id in ledgersById[id] })
//        print("Ready after \(Date.now.timeIntervalSince(start))s")
//
//        let recap = balances.map { wallet, balance in
//            WalletRecap(
//                wallet: wallet,
//                // TODO: this is number of refs, should be number of ledger entries
//                count: balance.values.reduce(0) { $0 + $1.count },
//                sumByAsset: balance.mapValues { $0.sum }
//            )
//        }.sorted(by: { a, b in
//            b.sumByAsset[BTC, default: 0] < a.sumByAsset[BTC, default: 0]
//        })
//
//        // Update published values
//        await MainActor.run {
//            self.history = history
//            self.recap = recap
//            self.changes = changes
//        }
//    }
//
//    @RealmActor
//    func update() async {
//        let realm = try! await getRealm()
//        // Read data from cache
//        if history.isEmpty && recap.isEmpty {
//            if let historyCache = realm.object(ofType: CacheItem.self, forPrimaryKey: CacheKey.balancesManagerHistory),
//               let history: [PortfolioHistoryItem] = try? historyCache.getValue()
//            {
//                await MainActor.run { self.history = history }
//            }
//            if let recapCache = realm.object(ofType: CacheItem.self, forPrimaryKey: CacheKey.balancesManagerRecap),
//               let recap: [WalletRecap] = try? recapCache.getValue()
//            {
//                await MainActor.run { self.recap = recap }
//            }
//        }
//
//        await updateOnchainWallets()
//        await updateServiceAccounts()
//        await updateComputedValues()
//
//        // Store computed values in cache
//        do {
//            try realm.write {
//                try realm.add(CacheItem(key: .balancesManagerHistory, value: history), update: .modified)
//                try realm.add(CacheItem(key: .balancesManagerRecap, value: recap), update: .modified)
//            }
//        } catch {
//            print("Error while writing to cache", error)
//        }
//    }
//
//    @RealmActor
//    private func updateOnchainWallets() async {
//        let realm = try! await getRealm()
//        let wallets = realm.objects(OnchainWallet.self)
//
//        // TODO: add support for multiple onchain wallets
//        guard let wallet = wallets.first else {
//            return
//        }
//
//        let fetcher = await OnchainTransactionsFetcher()
//        defer {
//            fetcher.shutdown()
//        }
//
//        let ledgers = await fetcher.fetchOnchainTransactions(addresses: wallet.addresses.map { $0.toAddress() })
//        await merge(ledgers)
//    }
//
//    @RealmActor
//    private func updateServiceAccounts() async {
//        let realm = try! await getRealm()
//        let accounts = realm.objects(ServiceAccount.self)
//
//        // TODO: Add support for multiple accounts
//        guard let account = accounts.first else {
//            return
//        }
//
//        let maybeLastKrakenLedger = realm.objects(RealmLedgerEntry.self)
//            .filter { $0.wallet == "Kraken" && $0.id.starts(with: "L") }
//            .sorted { a, b in a.date < b.date }.last
//        guard let lastKrakenLedger = maybeLastKrakenLedger else {
//            // TODO: inform the user that they must import data via CSV as a baseline to avoid too many API calls
//            return
//        }
//
//        let client = KrakenClient(apiKey: account.apiKey, apiSecret: account.apiSecret)
//        let ledgers = await client.getLedgers(afterLedgerId: lastKrakenLedger.id)
//
//        await merge(ledgers)
//    }
//
//    func merge(_ newEntries: [LedgerEntry]) async {
//        print("-- MERGING")
//        let mergedCount = try! await ledgerRepository.merge(newEntries)
//        print("-- Merged \(mergedCount) entries")
//        print("-- MERGING ENDED")
//    }
//
//    @RealmActor
//    func addOnchainWallet(_ wallet: OnchainWallet) async {
//        let realm = try! await getRealm()
//        try! realm.write {
//            realm.add(wallet)
//        }
//
//        await update()
//    }
//
//    @RealmActor
//    func addServiceAccount(_ account: ServiceAccount) async {
//        let realm = try! await getRealm()
//        try! realm.write {
//            realm.add(account)
//        }
//
//        await update()
//    }
//
//    private func getRealm() async throws -> Realm {
//        if realm == nil {
//            realm = try await Realm(configuration: realmConfiguration, actor: RealmActor.shared)
//        }
//
//        return realm!
//    }
// }
