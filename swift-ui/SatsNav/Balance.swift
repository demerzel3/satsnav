import Foundation

let BASE_ASSET = Asset(name: "EUR", type: .fiat)

struct Ref: Identifiable, Equatable, Hashable, Encodable {
    let id = UUID()
    let asset: Asset
    let amount: Decimal
    let date: Date
    let rate: Decimal?
}

extension Ref {
    var formattedAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(amount) : formatFiatAmount(amount))"
    }
}

struct BalanceChange: Identifiable, Encodable {
    let id = UUID()
    let transaction: Transaction
    let changes: [RefChange]

    enum RefChange: Identifiable, Hashable, Encodable {
        case create(ref: Ref, wallet: String)
        case remove(ref: Ref, wallet: String)
        case move(ref: Ref, fromWallet: String, toWallet: String)
        case split(originalRef: Ref, resultingRefs: [Ref], wallet: String)
        case join(originalRefs: [Ref], resultingRef: Ref, wallet: String)
        case convert(fromRefs: [Ref], toRef: Ref, wallet: String)

        var id: String {
            switch self {
            case .create(let ref, _): "create-\(ref.id)"
            case .remove(let ref, _): "remove-\(ref.id)"
            case .split(let originalRef, let resultingRefs, _): "split-\(originalRef.id)-\(resultingRefs.map { $0.id.uuidString }.joined(separator: "-"))"
            case .join(let originalRefs, let resultingRef, _): "split-\(originalRefs.map { $0.id.uuidString }.joined(separator: "-"))-\(resultingRef.id)"
            case .move(let ref, _, _): "move-\(ref.id)"
            case .convert(let fromRefs, let toRef, _): "convert-\(fromRefs.map { $0.id.uuidString }.joined(separator: "-"))-\(toRef.id)"
            }
        }
    }
}

extension BalanceChange {
    var isTransfer: Bool {
        guard case .transfer = transaction else { return false }
        return true
    }

    var isTrade: Bool {
        guard case .trade = transaction else { return false }
        return true
    }

    var isSingle: Bool {
        guard case .single = transaction else { return false }
        return true
    }
}

// Constructors
extension Ref {
    func withAmount(_ newAmount: Decimal, rate newRate: Decimal? = nil, date newDate: Date? = nil) -> Ref {
        assert(newAmount > 0, "Invalid amount \(newAmount)")
        return Ref(asset: asset, amount: newAmount, date: newDate ?? date, rate: newRate ?? rate)
    }

    static func join(_ ref1: Ref, _ ref2: Ref) -> Ref {
        assert(ref1.asset == ref2.asset, "Cannot join Refs with different assets")
        assert(ref1.rate == ref2.rate, "Cannot join Refs wit different rates")
        // TODO: `date` is not meaningful anymore, it needs to go!
        return Ref(asset: ref1.asset, amount: ref1.amount + ref2.amount, date: ref1.date, rate: ref1.rate)
    }
}

typealias RefsArray = [Ref]
typealias Balance = [Asset: RefsArray]

/**
 TODO: consolidate Refs without rate if they come from interests/bonus or other kinds of presents
       or maybe just track interest/bonus separately?

 TODO: alert if dust is significantly bigger than a rounding error, doesn't seem the case by inspecting the logs though
 */
func buildBalances(transactions: [Transaction]) -> (balances: [String: Balance], changes: [BalanceChange]) {
    var balanceChanges: [BalanceChange] = []
    var currentBalances: [String: [Asset: RefsArray]] = [:]

    for transaction in transactions {
        var changes: [BalanceChange.RefChange] = []

        switch transaction {
        case .single(let entry):
            // TODO: we have a non-negligible amount of entries with 0 amount, maybe avoid ingesting them in the first place
            guard entry.amount != 0 else {
                continue
            }

            let balanceBefore = currentBalances[entry.wallet, default: [:]][entry.asset, default: []].sum
            if entry.amount > 0, entry.asset == BASE_ASSET {
                let newRef = Ref(asset: entry.asset, amount: entry.amount, date: entry.date, rate: 1)
                changes.append(.create(ref: newRef, wallet: entry.wallet))
                let balance = currentBalances[entry.wallet, default: [:]][entry.asset, default: []]
                assert(balance.count < 2, "Invalid balance for BASE_ASSET, should have at most one item")
                if let currentRef = balance.first {
                    let joinedRef = Ref.join(newRef, currentRef)
                    changes.append(.join(originalRefs: [currentRef, newRef], resultingRef: joinedRef, wallet: entry.wallet))
                    currentBalances[entry.wallet, default: [:]][entry.asset] = [joinedRef]
                } else {
                    currentBalances[entry.wallet, default: [:]][entry.asset] = [newRef]
                }
            } else if entry.amount > 0 {
                let rate = ledgersMeta[entry.globalId].flatMap { $0.rate }

                if let userProvidedRate = rate {
                    print("🚨🚨🚨 Using user-provided rate for \(entry), rate: \(userProvidedRate)")
                }

                let newRef = Ref(asset: entry.asset, amount: entry.amount, date: entry.date, rate: rate)
                changes.append(.create(ref: newRef, wallet: entry.wallet))
                if let lastRef = currentBalances[entry.wallet, default: [:]][entry.asset, default: []].last,
                   lastRef.rate == newRef.rate
                {
                    let joinedRef = Ref.join(lastRef, newRef)
                    changes.append(.join(originalRefs: [lastRef, newRef], resultingRef: joinedRef, wallet: entry.wallet))
                    _ = currentBalances[entry.wallet, default: [:]][entry.asset, default: []].popLast()
                    currentBalances[entry.wallet, default: [:]][entry.asset, default: []].append(joinedRef)
                } else {
                    currentBalances[entry.wallet, default: [:]][entry.asset, default: []].append(newRef)
                }
            } else {
                var refs = currentBalances[entry.wallet, default: [:]][entry.asset, default: []]
                let (removedRefs, splitInfo) = subtract(refs: &refs, amount: -entry.amount)
                if let split = splitInfo {
                    changes.append(.split(originalRef: split.original, resultingRefs: [split.left, split.right], wallet: entry.wallet))
                }
                changes.append(contentsOf: removedRefs.map { .remove(ref: $0, wallet: entry.wallet) })
                currentBalances[entry.wallet, default: [:]][entry.asset] = refs
            }
            let balanceAfter = currentBalances[entry.wallet, default: [:]][entry.asset, default: []].sum
            assert(balanceAfter == balanceBefore + entry.amount, "Balances before and after must match")

        case .transfer(let from, let to):
            assert(from.amount != 0 && to.amount != 0, "invalid transfer amount \(from) -> \(to)")
            // TODO: handle from and to amount mismatches
            // assert(abs(from.amount) == abs(to.amount), "from and to amount mismatch \(from.amount) -> \(to.amount)")

            guard var fromRefs = currentBalances[from.wallet]?[from.asset] else {
                fatalError("Transfer failed, \(from.wallet) balance is empty")
            }

            let fromBalanceBefore = currentBalances[from.wallet, default: [:]][from.asset, default: []].sum
            let toBalanceBefore = currentBalances[to.wallet, default: [:]][to.asset, default: []].sum
            let (removedRefs, splitInfo) = subtract(refs: &fromRefs, amount: to.amount)
            if let split = splitInfo {
                changes.append(.split(originalRef: split.original, resultingRefs: [split.left, split.right], wallet: from.wallet))
            }
            changes.append(contentsOf: removedRefs.map { .move(ref: $0, fromWallet: from.wallet, toWallet: to.wallet) })
            currentBalances[from.wallet, default: [:]][from.asset] = fromRefs
            if let lastRef = currentBalances[to.wallet, default: [:]][to.asset, default: []].last,
               let firstRemovedRef = removedRefs.first,
               lastRef.rate == firstRemovedRef.rate
            {
                let joinedRef = Ref.join(lastRef, firstRemovedRef)
                changes.append(.join(originalRefs: [lastRef, firstRemovedRef], resultingRef: joinedRef, wallet: to.wallet))
                _ = currentBalances[to.wallet, default: [:]][to.asset, default: []].popLast()
                currentBalances[to.wallet, default: [:]][to.asset, default: []].append(joinedRef)
                currentBalances[to.wallet, default: [:]][to.asset, default: []].append(contentsOf: removedRefs.dropFirst())
            } else {
                currentBalances[to.wallet, default: [:]][to.asset, default: []].append(contentsOf: removedRefs)
            }
            let fromBalanceAfter = currentBalances[from.wallet, default: [:]][from.asset, default: []].sum
            let toBalanceAfter = currentBalances[to.wallet, default: [:]][to.asset, default: []].sum
            if from.wallet != to.wallet {
                // TODO: enable assertions when the from-to amounts mismatch is handled correctly
                // assert(fromBalanceAfter == fromBalanceBefore - abs(from.amount), "Balances before and after must match. Expected \(fromBalanceBefore - abs(from.amount)), is: \(fromBalanceAfter)")
                // assert(toBalanceAfter == toBalanceBefore + abs(to.amount), "Balances before and after must match. Expected \(toBalanceBefore + abs(to.amount)), is: \(toBalanceAfter)")
            }

        case .trade(let spend, let receive):
            assert(spend.amount != 0 && receive.amount != 0, "invalid trade amount \(spend) -> \(receive)")
            assert(spend.wallet == receive.wallet, "trade: spend and receive wallets must match")
            assert(spend.asset != receive.asset, "trade: spend and receive assets must be different")
            let wallet = spend.wallet
            let rate = (-spend.amount / receive.amount)

            // Move refs to receive balance
            var refs = currentBalances[wallet, default: [:]][spend.asset, default: []]
            refs.forEach { assert($0.amount > 0, "invalid ref before subtract \($0)") }
            let (removedRefs, splitInfo) = subtract(refs: &refs, amount: -spend.amount)
            refs.forEach { assert($0.amount > 0, "invalid ref after subtract \($0)") }
            removedRefs.forEach { assert($0.amount > 0, "invalid subtracted ref \($0)") }

            currentBalances[wallet, default: Balance()][spend.asset] = refs

            if let split = splitInfo {
                changes.append(.split(originalRef: split.original, resultingRefs: [split.left, split.right], wallet: wallet))
            }

            if receive.asset == BASE_ASSET {
                let newRef = Ref(asset: BASE_ASSET, amount: receive.amount, date: receive.date, rate: 1)
                changes.append(.convert(fromRefs: removedRefs, toRef: newRef, wallet: wallet))
                let balance = currentBalances[wallet, default: [:]][receive.asset, default: []]
                assert(balance.count < 2, "Invalid balance for BASE_ASSET, should have at most one item")
                if let currentRef = balance.first {
                    let joinedRef = Ref.join(currentRef, newRef)
                    changes.append(.join(originalRefs: [currentRef, newRef], resultingRef: joinedRef, wallet: wallet))
                    currentBalances[wallet, default: [:]][receive.asset] = [joinedRef]
                } else {
                    currentBalances[wallet, default: [:]][receive.asset] = [newRef]
                }
            } else {
                let precision = max(10, receive.amount.significantFractionalDecimalDigits)
                // Split refs between dust ones (conversion make them a rounding error) and actual ones
                let (nonDustRefs, dustRefs) = removedRefs.partition { ref in
                    round(ref.amount / rate, precision: precision) > 0
                }

                // Register dust refs as removed
                changes.append(contentsOf: dustRefs.map { .remove(ref: $0, wallet: wallet) })

                // Propagate rate to receive side
                var receiveRefs = nonDustRefs.map { ref -> Ref in
                    let nextRate = ref.rate.map { $0 * rate }.map { round($0, precision: precision) }
                    // TODO: if possible avoid doing amount calculation twice
                    let nextAmount = round(ref.amount / rate, precision: precision)

                    assert(nextAmount > 0, "Ok this should definitely never happen")

                    return Ref(asset: receive.asset, amount: nextAmount, date: receive.date, rate: nextRate)
                }

                receiveRefs.forEach {
                    assert($0.amount > 0, "Something went wrong with our friends the receiveRefs")
                }

                // There can still be some dust left
                let dust = receive.amount - receiveRefs.sum
                // TODO: alert if dust is significantly bigger than a rounding error
                if dust > 0 {
                    guard let first = receiveRefs.first else {
                        fatalError("Cannot fix rounding error, no elements")
                    }

                    // TODO: since there is now this dust amount, is the rate changed slightly?
                    receiveRefs[0] = first.withAmount(first.amount + dust)
                } else if dust < 0 {
                    // Drop refs up to the dust amount
                    _ = subtract(refs: &receiveRefs, amount: -dust)

                    receiveRefs.forEach {
                        assert($0.amount > 0, "Something went wrong with our friends the receiveRefs after subtract")
                    }
                }

                assert(receiveRefs.sum == receive.amount, "Trade balance update error, should be \(receive.amount), is \(receiveRefs.sum)")

                // Register conversions
                assert(receiveRefs.count == nonDustRefs.count, "Trade balance update error, removed \(nonDustRefs.count - receiveRefs.count) dust refs")
                changes.append(contentsOf: receiveRefs.enumerated().map { index, ref in
                    .convert(fromRefs: [nonDustRefs[index]], toRef: ref, wallet: wallet)
                })
                if let lastRef = currentBalances[wallet, default: [:]][receive.asset, default: []].last,
                   let firstReceiveRef = receiveRefs.first,
                   lastRef.rate == firstReceiveRef.rate
                {
                    let joinedRef = Ref.join(lastRef, firstReceiveRef)
                    changes.append(.join(originalRefs: [lastRef, firstReceiveRef], resultingRef: joinedRef, wallet: wallet))
                    _ = currentBalances[wallet, default: [:]][receive.asset, default: []].popLast()
                    currentBalances[wallet, default: [:]][receive.asset, default: []].append(joinedRef)
                    currentBalances[wallet, default: [:]][receive.asset, default: []] += receiveRefs.dropFirst()
                } else {
                    currentBalances[wallet, default: [:]][receive.asset, default: []] += receiveRefs
                }
            }
        }

        assert(!changes.isEmpty, "Transaction resulted in no changes \(transaction)")
        balanceChanges.append(BalanceChange(transaction: transaction, changes: changes))
    }

    // After processing all transactions, calculate totals
    var totalRefs = 0
    var totalContiguousRefs = 0

    for wallet in currentBalances.values {
        for refs in wallet.values {
            totalRefs += refs.count

            var contiguousCount = 0
            var lastRate: Decimal?

            for ref in refs {
                if ref.rate == lastRate {
                    contiguousCount += 1
                } else {
                    totalContiguousRefs += contiguousCount > 0 ? 1 : 0
                    contiguousCount = 1
                    lastRate = ref.rate
                }
            }
            totalContiguousRefs += contiguousCount > 0 ? 1 : 0
        }
    }

    // Print the results
    print("Total number of refs: \(totalRefs)")
    print("Total number of contiguous refs with the same asset and rate: \(totalContiguousRefs)")

    return (balances: currentBalances, changes: balanceChanges)
}
