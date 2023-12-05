import Charts
import SwiftData
import SwiftUI

struct ToyShape: Identifiable {
    var color: String
    var type: String
    var count: Double
    var id = UUID()
}

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
    @Binding var btcPrice: Decimal
    @State var coldStorage: RefsArray = []

    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var header: some View {
        VStack {
            (Text("BTC ") + Text(balances.portfolioTotal as NSNumber, formatter: btcFormatter)).font(.title)
            (Text("€ ") + Text((balances.portfolioTotal * btcPrice) as NSNumber, formatter: fiatFormatter)).font(.title3).foregroundStyle(.secondary)
            (Text("BTC 1 = € ") + Text(btcPrice as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
            (Text("cost basis € ") + Text((balances.totalAcquisitionCost / balances.portfolioTotal) as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    var chartData: [ChartDataItem] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date.now)!
        let now = Date.now

        return balances.portfolioHistory.flatMap {
            [
                ChartDataItem(source: "capital", date: $0.date, amount: $0.spent),
                ChartDataItem(source: "appreciation", date: $0.date, amount: ($0.total - $0.bonus) * btcPrice - $0.spent),
                ChartDataItem(source: "bonuses", date: $0.date, amount: $0.bonus * btcPrice),
            ]
        } + [
            ChartDataItem(source: "capital", date: now, amount: balances.totalAcquisitionCost),
            ChartDataItem(source: "appreciation", date: now, amount: (balances.portfolioTotal * btcPrice) - balances.totalAcquisitionCost),
        ]
    }

    var chart: some View {
        Chart {
            ForEach(chartData) { item in
                AreaMark(
                    x: .value("Date", item.date),
                    y: .value("Amount", item.amount)
                )
                .foregroundStyle(by: .value("Source", item.source))
            }
        }
        .frame(width: nil, height: 200)
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: addItem) {
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await balances.update()
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

    return ContentView(btcPrice: .constant(35000))
        .modelContainer(for: Item.self, inMemory: true)
}
