import Collections
import Foundation

extension Deque where Element == Ref {
    var sum: Decimal {
        reduce(0) { $0 + $1.amount }
    }

    var knownSum: Decimal {
        filter { $0.rate != nil }.reduce(0) { $0 + $1.amount }
    }

    var unknownSum: Decimal {
        filter { $0.rate == nil }.reduce(0) { $0 + $1.amount }
    }

    var description: String {
        map { "\($0.amount)@\(formatRate($0.rate, spendType: .fiat)) \($0.refId)" }.joined(separator: "\n")
    }
}
