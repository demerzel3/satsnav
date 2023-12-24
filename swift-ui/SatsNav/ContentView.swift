import Charts
import RealmSwift
import SwiftData
import SwiftUI

struct WalletProvider: Identifiable, Hashable {
    let name: String
    let defaultWalletName: String

    var id: String {
        return name
    }
}

let walletProviders = [
    WalletProvider(name: "Coinbase", defaultWalletName: "Coinbase"),
    WalletProvider(name: "Kraken", defaultWalletName: "Kraken"),
    WalletProvider(name: "Ledn", defaultWalletName: "Ledn"),
    WalletProvider(name: "BlockFi", defaultWalletName: "BlockFi"),
    WalletProvider(name: "Celsius", defaultWalletName: "Celsius"),
    WalletProvider(name: "Coinify", defaultWalletName: "Coinify"),
    WalletProvider(name: "BTC (on-chain)", defaultWalletName: "BTC"),
    WalletProvider(name: "Liquid BTC (on-chain)", defaultWalletName: "Liquid"),
    WalletProvider(name: "LTC (on-chain)", defaultWalletName: "LTC"),
    WalletProvider(name: "ETH (on-chain)", defaultWalletName: "ETH"),
    WalletProvider(name: "XRP (on-chain)", defaultWalletName: "XRP"),
    WalletProvider(name: "DOGE (on-chain)", defaultWalletName: "DOGE"),
    WalletProvider(name: "Custom data", defaultWalletName: "Custom"),
]

struct ChartDataItem: Identifiable {
    let source: String
    let date: Date
    let amount: Decimal

    var id: String {
        return "\(source)-\(date)"
    }
}

struct ContentView: View {
    @StateObject private var balances = BalancesManager()
    // TODO: consolidate live price and historic prices into a single observable object
    @StateObject private var btc = HistoricPriceProvider()
    @StateObject private var webSocketManager = WebSocketManager()
    @State var coldStorage: RefsArray = []
    @State private var addWalletWizardPresented = false

    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var header: some View {
        VStack {
            (Text("BTC ") + Text(balances.current.total as NSNumber, formatter: btcFormatter)).font(.title)
            (Text("€ ") + Text((balances.current.total * webSocketManager.btcPrice) as NSNumber, formatter: fiatFormatter)).font(.title3).foregroundStyle(.secondary)
            (Text("BTC 1 = € ") + Text(webSocketManager.btcPrice as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
            (Text("cost basis € ") + Text((balances.current.spent / balances.current.total) as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    var chartData: [ChartDataItem] {
        balances.history.flatMap {
            let price = btc.prices[$0.date] ?? webSocketManager.btcPrice
            return [
                ChartDataItem(source: "capital", date: $0.date, amount: $0.spent),
                ChartDataItem(source: "bonuses", date: $0.date, amount: $0.bonus * price),
                ChartDataItem(source: "value", date: $0.date, amount: ($0.total - $0.bonus) * price),
            ]
        }
    }

    var chart: some View {
        Chart {
            ForEach(chartData) { item in
                AreaMark(
                    x: .value("Date", item.date),
                    // Using this trick with capital so that it is present in the legend.
                    y: .value("Amount", item.source == "capital" ? 0 : item.amount)
                )
                .foregroundStyle(by: .value("Source", item.source))
            }

            ForEach(chartData.filter { $0.source == "capital" }) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Amount", item.amount)
                )
            }
        }
        // .frame(width: nil, height: 200)
        .padding()
    }

    var body: some View {
        NavigationView {
            VStack {
                self.header
                self.chart

                List {
                    Group {
                        if coldStorage.count > 0 {
                            ForEach(coldStorage) { ref in
                                VStack(alignment: .leading) {
                                    Text(ref.date, format: Date.FormatStyle(date: .numeric, time: .standard))
                                    Text("BTC ") + Text(ref.amount as NSNumber, formatter: btcFormatter)
                                        + Text(" (\(ref.refIds.count))")
                                    Text(ref.refId)
                                    if let rate = ref.rate {
                                        Text("€ ") + Text(rate as NSNumber, formatter: fiatFormatter)
                                    } else {
                                        Text("€ -")
                                    }
                                }

//                                Text(verbatim: "\(ref)")
//                                NavigationLink {
//                                    Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
//                                } label: {
//                                    Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
//                                }
                            }
                            // .onDelete(perform: deleteItems)
                        } else {
                            HStack {
                                Spacer()
                                Text("Loading...")
                                Spacer()
                            }.listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { addWalletWizardPresented.toggle() }) {
                        Text("Add wallet")
                    }
                }
            }
            .navigationBarTitle("Portfolio", displayMode: .inline)
        }
        .fullScreenCover(isPresented: $addWalletWizardPresented) {
            AddWalletView(onDone: { addWalletWizardPresented.toggle() })
        }
        .task {
            await balances.load()
        }
        .onAppear {
            webSocketManager.connect()
            btc.load()
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    let mockBalances = [String: Balance]()

    return ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
