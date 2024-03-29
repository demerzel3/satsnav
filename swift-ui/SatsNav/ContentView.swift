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

private enum ChartInterval: Hashable {
    case interval(size: Double, label: String, sampleSize: Int)
    case all
}

private let INTERVALS: [ChartInterval] = [
    .interval(size: 30*24*60*60, label: "1M", sampleSize: 1),
    .interval(size: 3*30*24*60*60, label: "3M", sampleSize: 1),
    .interval(size: 6*30*24*60*60, label: "6M", sampleSize: 1),
    .interval(size: 365*24*60*60, label: "1Y", sampleSize: 3),
    .interval(size: 3*365*24*60*60, label: "4Y", sampleSize: 7),
    .all,
]

struct ContentView: View {
    var credentials: Credentials
    @StateObject private var balances: BalancesManager
    @StateObject private var btc = HistoricPriceProvider()
    @StateObject private var webSocketManager = WebSocketManager()
    @State private var csvImportWizardPresented = false
    @State private var addOnchainWalletWizardPresented = false
    @State private var addServiceAccountWizardPresented = false
    @State private var chartInterval = ChartInterval.all
    @State private var showAllWallets = false

    init(credentials: Credentials) {
        self.credentials = credentials
        _balances = StateObject(wrappedValue: BalancesManager(credentials: credentials))
    }

    var header: some View {
        VStack {
            (Text("BTC ") + Text(balances.current.total as NSNumber, formatter: btcFormatter)).font(.title)
            (Text("€ ") + Text((balances.current.total*webSocketManager.btcPrice) as NSNumber, formatter: fiatFormatter)).font(.title3).foregroundStyle(.secondary)
            (Text("BTC 1 = € ") + Text(webSocketManager.btcPrice as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
            (Text("cost basis € ") + Text((balances.current.spent / balances.current.total) as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    var chartData: [ChartDataItem] {
        var history: [PortfolioHistoryItem]
        switch chartInterval {
        case .interval(let size, _, let sampleSize):
            let fromIndex = balances.history.lastIndex { $0.date.timeIntervalSinceNow < -size }
            history = (fromIndex.map { Array(balances.history[$0...]) } ?? balances.history).sample(every: sampleSize)
        case .all:
            history = balances.history.sample(every: 14)
        }

        return history.flatMap {
            let price = btc.prices[$0.date] ?? webSocketManager.btcPrice
            return [
                ChartDataItem(source: "capital", date: $0.date, amount: $0.spent),
                ChartDataItem(source: "bonuses", date: $0.date, amount: $0.bonus*price),
                ChartDataItem(source: "value", date: $0.date, amount: ($0.total - $0.bonus)*price),
            ]
        }
    }

    var recapToDisplay: [WalletRecap] {
        guard webSocketManager.btcPrice > 0 else {
            return []
        }

        if showAllWallets {
            return balances.recap
        }

        guard let lastItemIndexToDisplay = balances.recap.lastIndex(where: { item in
            let btcAmount = item.sumByAsset[BTC, default: 0]
            let oneEuroInBtc = 1 / webSocketManager.btcPrice

            return btcAmount >= oneEuroInBtc
        }) else {
            return []
        }

        return [WalletRecap](balances.recap[...lastItemIndexToDisplay])
    }

    var chart: some View {
        VStack {
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
            .chartYScale(domain: [0, 750_000])
            .chartYAxis {
                AxisMarks(
                    // format: Decimal.FormatStyle.Currency(code: "EUR"),
                    values: .automatic(desiredCount: 14)
                ) {
                    AxisGridLine()
                }

                AxisMarks(
                    values: [0, 250_000, 500_000, 750_000]
                ) {
                    let value = $0.as(Int.self)!
                    AxisValueLabel {
                        Text(formatYAxis(value))
                    }
                }

                if let lastItem = balances.history.last {
                    // Capital Mark
                    AxisMarks(
                        values: [lastItem.spent]
                    ) {
                        let value = $0.as(Int.self)!
                        AxisValueLabel {
                            Text(formatYAxis(value)).foregroundStyle(Color(.blue)).fontWeight(.bold)
                        }
                    }

                    // Total Mark
                    AxisMarks(
                        values: [lastItem.total*webSocketManager.btcPrice]
                    ) {
                        let value = $0.as(Int.self)!
                        AxisValueLabel {
                            Text(formatYAxis(value)).foregroundStyle(Color(.orange)).fontWeight(.bold)
                        }
                    }
                }
            }

            Picker("Chart Interval", selection: $chartInterval) {
                ForEach(INTERVALS, id: \.self) {
                    switch $0 {
                    case .interval(_, let label, _):
                        Text(label)
                    case .all:
                        Text("All")
                    }
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
    }

    var list: some View {
        List {
            let wallets = recapToDisplay
            if wallets.count > 0 {
                ForEach(wallets) { item in
                    let btcAmount = item.sumByAsset[BTC, default: 0]
                    let oneEuroInBtc = 1 / webSocketManager.btcPrice
                    let hasBtc = btcAmount >= oneEuroInBtc

                    NavigationLink(destination: RefsView(refs: balances.getRefs(byWallet: item.wallet, asset: BTC))) {
                        // Text(item.wallet).foregroundStyle(hasBtc ? .primary : .secondary)
                        HStack {
                            Text(item.wallet).foregroundStyle(hasBtc ? .primary : .secondary)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("BTC \(formatBtcAmount(btcAmount))").foregroundStyle(hasBtc ? .primary : .secondary)
                                Text("entries \(item.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if balances.recap.count > wallets.count {
                    HStack {
                        Spacer()
                        Button(action: { showAllWallets = true }) {
                            Text("Show small balances")
                        }.foregroundColor(.blue)
                        Spacer()
                    }.listRowSeparator(.hidden)
                } else if showAllWallets {
                    HStack {
                        Spacer()
                        Button(action: { showAllWallets = false }) {
                            Text("Hide small balances")
                        }.foregroundColor(.blue)
                        Spacer()
                    }.listRowSeparator(.hidden)
                }
            } else {
                HStack {
                    Spacer()
                    Text("Loading...").foregroundStyle(.secondary)
                    Spacer()
                }.listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    var body: some View {
        NavigationView {
            VStack {
                self.header
                self.chart
                self.list
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // FIXME: the menu closes on data update from websockets.
                    Menu {
                        Button("Import from CSV") {
                            csvImportWizardPresented.toggle()
                        }
                        Button("Onchain wallet") {
                            addOnchainWalletWizardPresented.toggle()
                        }
                        Button("Exchange account") {
                            addServiceAccountWizardPresented.toggle()
                        }
                    }
                    label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .navigationBarTitle("Portfolio", displayMode: .inline)
        }
        .fullScreenCover(isPresented: $csvImportWizardPresented) {
            CSVImportView(onDone: { newEntries in
                csvImportWizardPresented.toggle()

                guard let entries = newEntries else {
                    return
                }

                // TODO: communicate progress while this is ongoing...
                Task {
                    await balances.merge(entries)
                    await balances.update()
                }
            })
        }
        .fullScreenCover(isPresented: $addOnchainWalletWizardPresented) {
            AddOnchainWalletView(onDone: { newWallet in
                addOnchainWalletWizardPresented.toggle()

                guard let wallet = newWallet else {
                    return
                }

                // TODO: communicate progress while this is ongoing...
                Task {
                    await balances.addOnchainWallet(wallet)
                }
            })
        }
        .fullScreenCover(isPresented: $addServiceAccountWizardPresented) {
            AddServiceAccountView(onDone: { newAccount in
                addServiceAccountWizardPresented.toggle()

                guard let account = newAccount else {
                    return
                }

                // TODO: communicate progress while this is ongoing...
                Task {
                    await balances.addServiceAccount(account)
                }
            })
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

private func formatYAxis(_ number: Int) -> String {
    if number == 0 {
        return "0"
    }

    let number = Double(number)
    switch number {
    case 1_000_000...:
        return String(format: "%.1fM", number / 100_000)
    case 100_000...:
        return String(format: "%.0fK", number / 1_000)
    default:
        return "\(number)"
    }
}

#Preview {
    ContentView(credentials: try! Credentials())
}
