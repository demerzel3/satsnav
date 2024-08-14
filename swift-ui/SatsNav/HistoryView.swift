import SwiftUI

struct HistoryView: View {
    @ObservedObject var balancesManager: BalancesManager

    var body: some View {
        NavigationView {
            Text("Transaction History")
                .navigationBarTitle("History", displayMode: .inline)
        }
    }
}
