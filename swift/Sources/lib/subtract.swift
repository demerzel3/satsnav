import Foundation

/**
 Removes refs from asset balance using FIFO strategy
 */
func subtract(refs: inout RefsDeque, amount: Decimal) -> RefsArray {
    guard amount >= 0 else {
        fatalError("amount must be positive")
    }

    // Remove refs from asset balance using FIFO strategy
    var subtractedRefs = RefsArray()
    var totalRemoved: Decimal = 0
    while !refs.isEmpty && totalRemoved < amount {
        let removed = refs.removeFirst()
        totalRemoved += removed.amount
        subtractedRefs.append(removed)
    }

    if totalRemoved > amount {
        let leftOnBalance = totalRemoved - amount
        guard let last = subtractedRefs.popLast() else {
            fatalError("This should definitely never happen")
        }
        // Put leftover back to top of refs
        refs.insert(Ref(wallet: last.wallet, id: last.id, amount: leftOnBalance, rate: last.rate), at: 0)
        // Add rest to removed refs
        subtractedRefs.append(Ref(wallet: last.wallet, id: last.id, amount: last.amount - leftOnBalance, rate: last.rate))
    }

    return subtractedRefs
}
