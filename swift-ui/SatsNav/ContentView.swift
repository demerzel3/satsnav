import SwiftUI

struct ContentView: View {
    var credentials: Credentials
    @StateObject private var balances: BalancesManager
    @StateObject private var btc = HistoricPriceProvider()
    @StateObject private var webSocketManager = WebSocketManager()

    init(credentials: Credentials) {
        self.credentials = credentials
        let ledgerRepository = LedgerRepository(credentials: credentials)
        self._balances = StateObject(wrappedValue: BalancesManager(credentials: credentials, ledgerRepository: ledgerRepository))
    }

    var body: some View {
        TabView {
            PortfolioView(balances: balances, btc: btc, webSocketManager: webSocketManager)
                .tabItem {
                    Label("Portfolio", systemImage: "chart.pie.fill")
                }

            HistoryView(balancesManager: balances)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
        .task {
            await balances.update()
        }
        .onAppear {
            webSocketManager.connect()
            btc.load()
        }
    }
}
