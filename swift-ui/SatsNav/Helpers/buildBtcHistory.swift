import Foundation

struct PortfolioHistoryItem: Codable {
    let date: Date
    let total: Decimal // Incl. bonus
    let bonus: Decimal
    let spent: Decimal
}

func utcCalendar() -> Calendar {
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

    return calendar
}

func buildBtcHistory(balances: [String: Balance], getLedgerById: (String) -> LedgerEntry?) -> [PortfolioHistoryItem] {
    var allBtcRefs = balances.values.compactMap { $0[BTC] }.flatMap { $0 }.sorted { a, b in
        a.date < b.date
    }
    var total = allBtcRefs.sum
    var spent = allBtcRefs.compactMap { ref in ref.rate.map { $0 * ref.amount } }.reduce(0) { $0 + $1 }
    var bonus = allBtcRefs.filter {
        let entry = getLedgerById($0.refId)
        return entry?.type == .bonus || entry?.type == .interest
    }.sum
    var entries = [PortfolioHistoryItem(date: Date.now, total: total, bonus: bonus, spent: spent)]

    let calendar = utcCalendar()
    var date = allBtcRefs.last.map { $0.date }.map { calendar.startOfDay(for: $0) }
    while let d = date {
        while let last = allBtcRefs.popLast(), last.date >= d {
            total -= last.amount
            spent -= last.rate.map { $0 * last.amount } ?? 0
            if let entry = getLedgerById(last.refId), entry.type == .bonus || entry.type == .interest {
                bonus -= last.amount
            }
        }
        entries.append(PortfolioHistoryItem(date: d, total: total, bonus: bonus, spent: spent))
        date = allBtcRefs.last.map { $0.date }.map { calendar.startOfDay(for: $0) }
    }

    return entries.reversed()
}
