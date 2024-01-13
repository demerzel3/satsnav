import Foundation

extension Array {
    func partition(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        let first = self.filter(predicate)
        let second = self.filter { !predicate($0) }
        return (first, second)
    }

    func sample(every step: Int) -> [Element] {
        guard step > 0, !isEmpty else { return [] }
        var result = stride(from: 0, to: count - 1, by: step).map { self[$0] }
        // Ensure the last element is always included
        if let last = self.last {
            result.append(last)
        }

        return result
    }
}

extension Array where Element == Ref {
    var sum: Decimal {
        reduce(0) { $0 + $1.amount }
    }

    var description: String {
        map { "\($0.amount)@\(formatRate($0.rate, spendType: .fiat))" }.joined(separator: ",")
    }
}
