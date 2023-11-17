import Foundation

extension Array {
    func partition(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        let first = self.filter(predicate)
        let second = self.filter { !predicate($0) }
        return (first, second)
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
