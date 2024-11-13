import SwiftUI

@MainActor
class BalancesCoordinator: ObservableObject {
    let balances = BalancesState()
    private let credentials: Credentials
    private var manager: BalancesManager?

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    func setup() async throws {
        let manager = await BalancesManager(
            state: balances,
            cacheRepository: await CacheRepository(credentials: credentials),
            ledgerRepository: await LedgerRepository(credentials: credentials),
            onchainWalletRepository: await OnchainWalletRepository(credentials: credentials)
        )
        self.manager = manager

        try await manager.update()
    }

    var history: [PortfolioHistoryItem] { balances.history }
    var changes: [BalanceChange] { balances.changes }

    func mergeAndUpdate(entries: [LedgerEntry]) async throws {
        if let manager {
            await manager.merge(entries)
            try await manager.update()
        }
    }

    func addOnchainWallet(_ wallet: OnchainWallet) async throws {
        if let manager {
            try await manager.addOnchainWallet(wallet)
            try await manager.update()
        }
    }

    func addServiceAccount(_ account: ServiceAccount) async throws {
        // TODO: implement
    }
}

struct ContentView: View {
    var credentials: Credentials
    @StateObject private var coordinator: BalancesCoordinator
    // @StateObject private var balances: BalancesManager
    @StateObject private var btc = HistoricPriceProvider()
    @StateObject private var webSocketManager = WebSocketManager()

    init(credentials: Credentials) {
        self.credentials = credentials
        self._coordinator = StateObject(wrappedValue: BalancesCoordinator(credentials: credentials))
    }

    var body: some View {
        TabView {
            PortfolioView(balances: self.coordinator, btc: self.btc, webSocketManager: self.webSocketManager)
                .tabItem {
                    Label("Portfolio", systemImage: "chart.pie.fill")
                }

            HistoryView(balances: self.coordinator)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
        .task {
            try! await self.coordinator.setup()
        }
        .onAppear {
            self.webSocketManager.connect()
            self.btc.load()
        }
    }
}
