import Foundation
import SwiftUI

struct RefIdsView: View {
    let refIds: [String]

    var body: some View {
        List {
            ForEach(refIds, id: \.self) { item in
                Button(action: {
                    UIPasteboard.general.string = item
                    print("Copied to clipboard: \(item)")
                }) {
                    Text(item)
                }
            }
        }.listStyle(.plain)
    }
}
