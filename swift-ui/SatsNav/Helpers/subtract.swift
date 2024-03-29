import Foundation

/**
 Removes refs from asset balance using LIFO strategy
 */
func subtract(refs: inout RefsArray, amount: Decimal) -> RefsArray {
    assert(amount >= 0, "amount must be positive")
    let balanceBefore = refs.sum

    // Remove refs from asset balance using LIFO strategy
    var subtractedRefs = RefsArray()
    var totalRemoved: Decimal = 0
    while !refs.isEmpty && totalRemoved < amount {
        let removed = refs.removeLast()
        totalRemoved += removed.amount
        subtractedRefs.append(removed)
    }

    if totalRemoved > amount {
        let leftOnBalance = totalRemoved - amount
        guard let last = subtractedRefs.popLast() else {
            fatalError("This should definitely never happen")
        }
        // Put leftover back to the bottom of refs
        refs.append(last.withAmount(leftOnBalance))
        // Add rest to removed refs
        subtractedRefs.append(last.withAmount(last.amount - leftOnBalance))
    }

    assert(refs.sum + subtractedRefs.sum == balanceBefore,
           "Balance subtract error, should be \(balanceBefore), it's \(refs.sum + subtractedRefs.sum)")

    return subtractedRefs.reversed()
}
