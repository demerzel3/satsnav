import SwiftUI

struct HistoryView: View {
    @ObservedObject var balancesManager: BalancesManager

    var body: some View {
        NavigationView {
            List {
                ForEach(balancesManager.changes) { change in
                    TransactionRow(change: change)
                }
            }
            .listStyle(PlainListStyle())
            .navigationBarTitle("Transaction History", displayMode: .inline)
        }
    }
}

struct TransactionRow: View {
    let change: BalanceChange

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(transactionTypeString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(spacing: 4) {
                Text(formattedAmount)
                    .font(.headline)

                if case .trade(let spend, let receive) = change.transaction {
                    Text("Rate: \(formatRate(-spend.amount / receive.amount))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: change.transaction.date)
    }

    private var formattedAmount: String {
        switch change.transaction {
        case .single(let entry):
            return entry.formattedAmount
        case .trade(let spend, let receive):
            return "\(spend.formattedAbsAmount)\n\(receive.formattedAmount)"
        case .transfer(let from, let to):
            return "\(to.formattedAmount)"
        }
    }

    private var transactionTypeString: String {
        switch change.transaction {
        case .single(let entry) where entry.type == .trade:
            return "Unknown - \(entry.wallet)"
        case .single(let entry):
            return "\(String(describing: entry.type).capitalized) - \(entry.wallet)"
        case .trade(let spend, _):
            return "Trade - \(spend.wallet)"
        case .transfer(let from, let to):
            return "Transfer: \(from.wallet) → \(to.wallet)"
        }
    }
}
