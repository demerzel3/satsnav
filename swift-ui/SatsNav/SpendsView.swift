import Foundation
import SwiftUI

private func createDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"

    return formatter
}

struct SpendsView: View {
    let refs: [Ref]
    let dateFormatter: DateFormatter = createDateFormatter()

    var spendsList: [[Ref]] {
        var parents = refs
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
                    Text("\(spendsItem.count) parents: \(spendsItem.map { "\($0.amount) \($0.asset.name)" }.joined(separator: ", "))")
                } else {
                    let item = spendsItem[0]
                    let amount = item.asset.type == .fiat
                        ? "\(formatFiatAmount(item.amount)) \(item.asset.name)"
                        : "\(formatBtcAmount(item.amount)) \(item.asset.name)"
                    let fiatAmount = item.rate.map { " - \(formatFiatAmount($0 * item.amount)) €" }

                    Section("\(amount)\(fiatAmount ?? "")") {
                        ForEach(item.refIds, id: \.self) { refId in
                            Button(action: {
                                UIPasteboard.general.string = refId
                                print("Copied to clipboard: \(refId)")
                            }) { Text(refId) }
                        }
                    }
                }
            }
        }.listStyle(.plain)
    }
}
