import Charts
import SwiftData
import SwiftUI

struct ToyShape: Identifiable {
    var color: String
    var type: String
    var count: Double
    var id = UUID()
}

var stackedBarData: [ToyShape] = [
    .init(color: "Green", type: "Cube", count: 2),
    .init(color: "Green", type: "Sphere", count: 0),
    .init(color: "Green", type: "Pyramid", count: 1),
    .init(color: "Purple", type: "Cube", count: 1),
    .init(color: "Purple", type: "Sphere", count: 1),
    .init(color: "Purple", type: "Pyramid", count: 1),
    .init(color: "Pink", type: "Cube", count: 1),
    .init(color: "Pink", type: "Sphere", count: 2),
    .init(color: "Pink", type: "Pyramid", count: 0),
    .init(color: "Yellow", type: "Cube", count: 1),
    .init(color: "Yellow", type: "Sphere", count: 1),
    .init(color: "Yellow", type: "Pyramid", count: 2)
]

struct ContentView: View {
    @Binding var balances: [String: Balance]
    @Binding var btcPrice: Decimal
    @State var coldStorage: RefsArray = []

    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var portfolioTotal: Decimal {
        return balances.values.reduce(0) { $0 + ($1[BTC]?.sum ?? 0) }
    }

    var totalAcquisitionCost: Decimal {
        return balances.values.reduce(0) { $0 + ($1[BTC]?.reduce(0) { tot, ref in tot + ref.amount * (ref.rate ?? 0) } ?? 0) }
    }

    var header: some View {
        VStack {
            (Text("BTC ") + Text(portfolioTotal as NSNumber, formatter: btcFormatter)).font(.title)
            (Text("€ ") + Text((portfolioTotal * btcPrice) as NSNumber, formatter: fiatFormatter)).font(.title3).foregroundStyle(.secondary)
            (Text("BTC 1 = € ") + Text(btcPrice as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
            (Text("cost basis € ") + Text((totalAcquisitionCost / portfolioTotal) as NSNumber, formatter: fiatFormatter)).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    var chart: some View {
        Chart {
            ForEach(coldStorage) { ref in
                BarMark(
                    x: .value("Date", ref.date),
                    y: .value("Rate", ref.rate ?? 0),
                    stacking: .unstacked
                )
                // .foregroundStyle(by: .value("Amount", ref.amount * (ref.rate ?? 0) > 0 ? "Green" : "Red"))
            }
        }
        .chartScrollableAxes(.horizontal)
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
        .onAppear { prepareBalances() }
        .onChange(of: balances) { prepareBalances() }
    }

    private func prepareBalances() {
        if let cs = balances["❄️"]?[BTC] {
            coldStorage = cs
                .sorted { a, b in a.rate ?? 0 < b.rate ?? 0 }
            // .sorted { a, b in a.date > b.date }
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

    return ContentView(balances: .constant(mockBalances), btcPrice: .constant(35000))
        .modelContainer(for: Item.self, inMemory: true)
}
