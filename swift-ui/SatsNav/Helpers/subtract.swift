import Foundation

typealias SplitInfo = (original: Ref, left: Ref, right: Ref)

/**
 Removes refs from asset balance using LIFO strategy, keeps track of splits
 */
func subtract(refs: inout RefsArray, amount: Decimal) -> (removed: RefsArray, split: SplitInfo?) {
    assert(amount >= 0, "amount must be positive")
    let balanceBefore = refs.sum
    // assert(amount <= balanceBefore, "amount must be less than or equal to balance (\(amount), \(balanceBefore))")

    var subtractedRefs = RefsArray()
    var totalRemoved: Decimal = 0
    var splitInfo: SplitInfo?

    while !refs.isEmpty, totalRemoved < amount {
        let removed = refs.removeLast()
        totalRemoved += removed.amount
        subtractedRefs.append(removed)
    }

    if totalRemoved > amount {
        let leftOnBalance = totalRemoved - amount
        guard let last = subtractedRefs.popLast() else {
            fatalError("This should definitely never happen")
        }
        let splitLeft = last.withAmount(leftOnBalance)
        let splitRight = last.withAmount(last.amount - leftOnBalance)
        // Record the split
        splitInfo = (original: last, left: splitLeft, right: splitRight)
        // Put leftover back to the bottom of refs
        refs.append(splitLeft)
        // Add rest to removed refs
        subtractedRefs.append(splitRight)
    }

    assert(refs.sum + subtractedRefs.sum == balanceBefore,
           "Balance subtract error, should be \(balanceBefore), it's \(refs.sum + subtractedRefs.sum)")

    return (subtractedRefs.reversed(), splitInfo)
}
