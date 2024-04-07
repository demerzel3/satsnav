import SwiftUI

private func createDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"

    return formatter
}

struct RefsView: View {
    let refs: RefsArray
    let dateFormatter: DateFormatter = createDateFormatter()

    var body: some View {
        List {
            ForEach(refs.reversed().filter { $0.amount != 0.0001 }) { item in
                let listItem = HStack {
                    VStack(alignment: .leading) {
                        Text(item.asset.type == .fiat
                            ? "\(formatFiatAmount(item.amount)) \(item.asset.name)"
                            : "\(formatBtcAmount(item.amount)) \(item.asset.name)"
                        )
                        if let rate = item.rate {
                            Text("\(formatFiatAmount(rate)) EUR")
                        } else {
                            Text("No rate")
                        }
                    }
                    Spacer()
                    Text("\(dateFormatter.string(from: item.date))")
                }

                if item.spends.isEmpty {
                    listItem
                } else {
                    NavigationLink(destination: { SpendsView(refs: item.spends) }) { listItem }
                }
            }
        }.listStyle(.plain)
    }
}
