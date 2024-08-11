import Foundation
import SwiftUI

private func createDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"

    return formatter
}

struct SpendsView: View {
    let ref: Ref
    let dateFormatter: DateFormatter = createDateFormatter()

    var spendsList: [[Ref]] {
        var parents = [ref]
        var list = [[Ref]]()
        while parents.count == 1 {
            list.append(parents)
            parents = parents[0].spends
        }

        if parents.count > 1 {
            list.append(parents)
        }
        return list
    }

    var body: some View {
        List {
            ForEach(spendsList, id: \.first!) { spendsItem in
                if spendsItem.count > 1 {
                    Section("Multiple parents") {
                        ForEach(spendsItem) { item in
                            NavigationLink(destination: { SpendsView(ref: item) }) {
                                Text("\(item.amount) \(item.asset.name)")
                            }
                        }
                    }
                } else {
                    let item = spendsItem[0]
                    let amount = item.asset.type == .fiat
                        ? "\(formatFiatAmount(item.amount)) \(item.asset.name)"
                        : "\(formatBtcAmount(item.amount)) \(item.asset.name)"
                    let fiatAmount = item.rate.map { " - \(formatFiatAmount($0 * item.amount)) €" }

                    Section("\(amount)\(fiatAmount ?? "")") {
                        switch item.transaction {
                        case .single(let entry):
                            Text("\(entry)")
                        case .trade(let spend, let receive):
                            Text("\(spend.asset.name) -> \(receive.asset.name)")
                        case .transfer(let from, let to):
                            Text("\(from.wallet) -> \(to.wallet)")
                        }
                    }
                }
            }
        }.listStyle(.plain)
    }
}
