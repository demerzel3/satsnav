import Charts
import RealmSwift
import SwiftData
import SwiftUI

struct ChartDataItem: Identifiable {
    let source: String
    let date: Date
    let amount: Decimal

    var id: String {
        return "\(source)-\(date)"
    }
}

struct ContentView: View {
    var credentials: Credentials
    @StateObject private var balances: BalancesManager
    @StateObject private var btc = HistoricPriceProvider()
    @StateObject private var webSocketManager = WebSocketManager()
    @State var coldStorage: RefsArray = []
    @State private var addWalletWizardPresented = false

    init(credentials: Credentials) {
        self.credentials = credentials
        _balances = StateObject(wrappedValue: BalancesManager(credentials: credentials))
    }

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
                        if balances.recap.count > 0 {
                            ForEach(balances.recap) { item in
                                HStack {
                                    Text(item.wallet)
                                    Spacer()
                                    Text("\(item.count)")
                                }
                            }

//                            ForEach(coldStorage) { ref in
//                                VStack(alignment: .leading) {
//                                    Text(ref.date, format: Date.FormatStyle(date: .numeric, time: .standard))
//                                    Text("BTC ") + Text(ref.amount as NSNumber, formatter: btcFormatter)
//                                        + Text(" (\(ref.refIds.count))")
//                                    Text(ref.refId)
//                                    if let rate = ref.rate {
//                                        Text("€ ") + Text(rate as NSNumber, formatter: fiatFormatter)
//                                    } else {
//                                        Text("€ -")
//                                    }
//                                }

//                                Text(verbatim: "\(ref)")
//                                NavigationLink {
//                                    Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
//                                } label: {
//                                    Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
//                                }
//                            }
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
                    Menu {
                        Button("Import from CSV") {
                            addWalletWizardPresented.toggle()
                        }
                        Button("Onchain wallet") {
                            // Handle new onchain wallet
                        }
                        Button("Exchange account") {
                            // Handle new exchange account
                        }
                    }
                    label: {
                        Label("Add", systemImage: "plus")
                    }
//                    Button(action: { addWalletWizardPresented.toggle() }) {
//                        Text("Add wallet")
//                    }
                }
            }
            .navigationBarTitle("Portfolio", displayMode: .inline)
        }
        .fullScreenCover(isPresented: $addWalletWizardPresented) {
            CSVImportView(onDone: { newEntries in
                addWalletWizardPresented.toggle()

                guard let entries = newEntries else {
                    return
                }

                // TODO: loading closes before this is done, should probably keep it open while merging
                Task {
                    await balances.merge(entries)
                }
            })
        }
        .task {
            await balances.load()
        }
        .onAppear {
            webSocketManager.connect()
            btc.load()
        }
    }
}

#Preview {
    ContentView(credentials: try! Credentials())
}
