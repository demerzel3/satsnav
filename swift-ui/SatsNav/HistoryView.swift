import SwiftUI

struct HistoryView: View {
    @ObservedObject var balancesManager: BalancesManager
    @State private var showingAlert = false

    var body: some View {
        NavigationView {
            List {
                ForEach(balancesManager.changes) { change in
                    NavigationLink(destination: TransactionDetailView(change: change)) {
                        TransactionRow(change: change)
                    }
                }
            }
            .listStyle(PlainListStyle())
            .navigationBarTitle("Transaction History", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: copyJSONToClipboard) {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("JSON Copied"), message: Text("The transaction history has been copied to the clipboard as JSON."), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func copyJSONToClipboard() {
        if let jsonString = balanceChangesToJSON(balancesManager.changes) {
            UIPasteboard.general.string = jsonString
            showingAlert = true
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
        case .transfer(_, let to):
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

func balanceChangesToJSON(_ changes: [BalanceChange]) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    do {
        let jsonData = try encoder.encode(changes)
        return String(data: jsonData, encoding: .utf8)
    } catch {
        print("Error encoding to JSON: \(error)")
        return nil
    }
}
