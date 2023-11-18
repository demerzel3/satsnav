import Collections
import Foundation

private let BASE_ASSET = LedgerEntry.Asset(name: "EUR", type: .fiat)

struct Ref {
    // "\(wallet)-\(id)"
    let wallet: String
    let id: String
    let amount: Decimal
    let rate: Decimal?
}

typealias RefsDeque = Deque<Ref>
typealias RefsArray = [Ref]
typealias Balance = [LedgerEntry.Asset: RefsDeque]

/**
 TODO: alert if dust is significantly bigger than a rounding error
 */

func buildBalances(groupedLedgers: [GroupedLedger]) -> [String: Balance] {
    //             [Wallet: Balance]
    var balances = [String: Balance]()
    for (index, group) in groupedLedgers.enumerated() {
        print("Entry #\(index)")
        switch group {
        case .single(let entry):
            print("\(entry.wallet) \(entry.type) \(entry.formattedAmount) - \(entry.id)")

            // Not keeping track of base asset
            guard entry.asset != BASE_ASSET else {
                continue
            }

            var refs = balances[entry.wallet, default: Balance()][entry.asset, default: RefsDeque()]
            if entry.amount > 0 {
                refs.append(Ref(wallet: entry.wallet, id: entry.id, amount: entry.amount, rate: nil))
            } else {
                let removedRefs = subtract(refs: &refs, amount: -entry.amount)

                if entry.type == .withdrawal {
                    let refsString = refs.map { "\($0.amount)@\(formatRate($0.rate, spendType: .fiat))" }.joined(separator: ", ")
                    let removedRefsString = removedRefs.map { "\($0.amount)@\(formatRate($0.rate, spendType: .fiat))" }.joined(separator: ", ")
                    print("  refs: \(removedRefsString)")
                    print("  balance: \(refsString)")
                    // fatalError("can we match this one?")
                } else if entry.type == .deposit {
                    // fatalError("can we match this one?")
                }
            }
            balances[entry.wallet, default: Balance()][entry.asset] = refs
        case .transfer(let from, let to):
            if from.wallet == to.wallet {
                print("noop internal transfer \(from.wallet) \(to.formattedAmount)")
                continue
            }
            print("TRANSFER! \(from.wallet) -> \(to.wallet) \(to.formattedAmount)")
            guard var fromRefs = balances[from.wallet]?[from.asset] else {
                fatalError("Transfer failed, balance is empty")
            }

            let subtractedRefs = subtract(refs: &fromRefs, amount: to.amount)
            balances[from.wallet, default: Balance()][from.asset] = fromRefs
            balances[to.wallet, default: Balance()][to.asset, default: RefsDeque()].append(contentsOf: subtractedRefs)
            print("  Transfered refs:", subtractedRefs.map { "\($0.amount)@\(formatRate($0.rate, spendType: .fiat))" })
        case .trade(let spend, let receive):
            let wallet = spend.wallet
            let rate = (-spend.amount / receive.amount)
            print("\(wallet) trade! spent \(spend.formattedAmount), received \(receive.formattedAmount) @\(formatRate(rate, spendType: spend.asset.type))")
            print("full spend \(spend.amount) rate \(rate) receive \(receive.amount)")

            if spend.asset != BASE_ASSET {
                // "move" refs to receive balance
                var refs = balances[wallet, default: Balance()][spend.asset, default: RefsDeque()]
                let balanceBefore = refs.reduce(0) { $0 + $1.amount }
                print("  \(spend.asset.name) balance \(refs.reduce(0) { $0 + $1.amount })")
                print("    bef: \(refs.map { $0.amount })")
                let removedRefs = subtract(refs: &refs, amount: -spend.amount)
                print("    rem: \(removedRefs.map { $0.amount })")
                print("    aft: \(refs.map { $0.amount })")

                let balanceAfter = (refs + removedRefs).reduce(0) { $0 + $1.amount }
                if balanceBefore != balanceAfter {
                    fatalError("Balance subtract error, should be \(balanceBefore), it's \(balanceAfter)")
                }

                balances[wallet, default: Balance()][spend.asset] = refs

                if receive.asset != BASE_ASSET {
                    let precision = receive.amount.significantFractionalDecimalDigits
                    // Propagate rate to receive side
                    // 🚨🚨 The operations here with the amount are not precise enough and leading to wrong balance
                    // TODO: receivedRefs total MUST match receive.amount
                    var receiveRefs = removedRefs.map {
                        let nextRate = $0.rate.map { $0 * rate }
                        let nextAmount = round($0.amount / rate, precision: precision)
                        print("\(nextAmount) \($0.amount / rate)")
                        // let nextAmount = $0.amount / rate

                        return Ref(wallet: $0.wallet, id: $0.id, amount: nextAmount, rate: nextRate)
                    }
                    let dust = receive.amount - receiveRefs.sum
                    // TODO: alert if dust is significantly bigger than a rounding error
                    if dust != 0 {
                        print("⚠️ Receive ref diff: \(dust), adding to first ref")
                        guard let first = receiveRefs.first else {
                            fatalError("Cannot fix rounding error, no elements")
                        }

                        receiveRefs[0] = Ref(
                            wallet: first.wallet,
                            id: first.id,
                            amount: first.amount + dust,
                            rate: first.rate
                        )
                    }

                    let allReceiveRefs = balances[wallet, default: Balance()][receive.asset, default: RefsDeque()] + receiveRefs
                    balances[wallet, default: Balance()][receive.asset] = allReceiveRefs
                    print("  \(receive.asset.name) balance \(allReceiveRefs.reduce(0) { $0 + $1.amount })")
                    print("    \(allReceiveRefs.map { $0.amount })")
                    print("    \(receiveRefs.map { $0.amount })")

                    // receivedRefs total MUST match receive.amount or balances start to drift
                    if receiveRefs.sum != receive.amount {
                        fatalError("Trade balance update error, should be \(receive.amount), is \(receiveRefs.reduce(0) { $0 + $1.amount })")
                    }
                }

                break
            }

            if receive.asset != BASE_ASSET {
                // Add ref to balance
                let ref = Ref(wallet: receive.wallet, id: receive.groupId, amount: receive.amount, rate: rate)
                balances[receive.wallet, default: Balance()][receive.asset, default: RefsDeque()].append(ref)
            }
        }
    }

    return balances
}
