import SwiftUI

struct TransactionDetailView: View {
    let change: BalanceChange
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                transactionHeader
                transactionDetails
                refChanges
            }
            .padding()
        }
        .navigationBarTitle("Transaction Details", displayMode: .inline)
    }
    
    private var transactionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(transactionTypeString)
                .font(.title2)
                .fontWeight(.bold)
            Text(formattedDate)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var transactionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch change.transaction {
            case .single(let entry):
                detailRow("Type", String(describing: entry.type).capitalized)
                detailRow("Wallet", entry.wallet)
                detailRow("Amount", entry.formattedAmount)
            case .trade(let spend, let receive):
                detailRow("Type", "Trade")
                detailRow("Wallet", spend.wallet)
                detailRow("Spend", spend.formattedAbsAmount)
                detailRow("Receive", receive.formattedAmount)
                detailRow("Rate", formatRate(-spend.amount / receive.amount))
            case .transfer(let from, let to):
                detailRow("Type", "Transfer")
                detailRow("From Wallet", from.wallet)
                detailRow("To Wallet", to.wallet)
                detailRow("Amount", to.formattedAmount)
            }
        }
    }
    
    private var refChanges: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Balance Changes")
                .font(.headline)
            
            ForEach(change.changes, id: \.self) { refChange in
                switch refChange {
                case .create(let ref, let wallet):
                    Text("Created: \(ref.formattedAmount) in \(wallet)")
                case .remove(let ref, let wallet):
                    Text("Removed: \(ref.formattedAmount) from \(wallet)")
                case .move(let ref, let fromWallet, let toWallet):
                    Text("Moved: \(ref.formattedAmount) from \(fromWallet) to \(toWallet)")
                case .split(let originalRef, let resultingRefs, let wallet):
                    VStack(alignment: .leading) {
                        Text("Split in \(wallet):")
                        Text("Original: \(originalRef.formattedAmount)")
                        ForEach(resultingRefs, id: \.id) { ref in
                            Text("Result: \(ref.formattedAmount)")
                        }
                    }
                case .join(let originalRefs, let resultingRef, let wallet):
                    VStack(alignment: .leading) {
                        Text("Join in \(wallet):")
                        ForEach(originalRefs, id: \.id) { ref in
                            Text("Original: \(ref.formattedAmount)")
                        }
                        Text("Result: \(resultingRef.formattedAmount)")
                    }
                case .convert(let fromRefs, let toRef, let wallet):
                    VStack(alignment: .leading) {
                        Text("Converted in \(wallet):")
                        ForEach(fromRefs, id: \.id) { ref in
                            Text("From: \(ref.formattedAmount)")
                        }
                        Text("To: \(toRef.formattedAmount)")
                    }
                }
            }
        }
    }
    
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter.string(from: change.transaction.date)
    }
    
    private var transactionTypeString: String {
        switch change.transaction {
        case .single(let entry):
            return "\(String(describing: entry.type).capitalized) - \(entry.wallet)"
        case .trade:
            return "Trade"
        case .transfer:
            return "Transfer"
        }
    }
}
