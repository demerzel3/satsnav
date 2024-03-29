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
        NavigationView {
            List {
                ForEach(refs.reversed()) { item in
                    NavigationLink(destination: { RefIdsView(refIds: item.refIds) }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(formatBtcAmount(item.amount)) BTC")
                                if let rate = item.rate {
                                    Text("\(formatFiatAmount(rate)) EUR")
                                } else {
                                    Text("No rate")
                                }
                            }
                            Spacer()
                            Text("\(dateFormatter.string(from: item.date))")
                        }
                    }
                }
            }.listStyle(.plain)
        }
    }
}
