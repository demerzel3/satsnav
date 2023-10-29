import Foundation

extension Array {
    func partition(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        let first = self.filter(predicate)
        let second = self.filter { !predicate($0) }
        return (first, second)
    }
}
