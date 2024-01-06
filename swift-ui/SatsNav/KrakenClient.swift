import Foundation
import KrakenAPI

enum KrakenClientError: Error {
    case unknownError
    case invalidData
}

final class KrakenClient {
    private let internalClient: Kraken

    init(apiKey: String, apiSecret: String) {
        self.internalClient = Kraken(credentials: Kraken.Credentials(apiKey: apiKey, privateKey: apiSecret))
    }

    private func fetchLedgersPage(page: Int = 0) async throws -> [KrakenLedgerEntry] {
        let result = await internalClient.ledgersInfo(ofs: 50 * page)
        guard case .success(let payload) = result else {
            if case .failure(let err) = result {
                print("KrakenAPI error on page \(page)", err)
                throw err
            }
            throw KrakenClientError.unknownError
        }

        guard let entries = payload["ledger"] as? [String: [String: Any]] else {
            print("Error: `ledger` has invalid type \(String(describing: payload["ledger"]))")
            throw KrakenClientError.invalidData
        }

        let ledger: [KrakenLedgerEntry] = try entries.compactMap { id, entry in
            guard
                let refId = entry["refid"] as? String,
                let timeInSeconds = entry["time"] as? Double,
                let type = entry["type"] as? String,
                let subtype = entry["subtype"] as? String,
                let asset = entry["asset"] as? String,
                let amountStr = entry["amount"] as? String,
                let amount = Decimal(string: amountStr),
                let feeStr = entry["fee"] as? String,
                let fee = Decimal(string: feeStr),
                let balanceStr = entry["balance"] as? String,
                let balance = Decimal(string: balanceStr)
            else {
                print("Cannot parse entry: \(String(describing: entry))")
                throw KrakenClientError.invalidData
            }

            return KrakenLedgerEntry(
                id: id,
                refId: refId,
                time: Date(timeIntervalSince1970: timeInSeconds),
                type: type,
                subtype: subtype,
                asset: asset,
                amount: amount,
                fee: fee,
                balance: balance
            )
        }

        return ledger
    }

    func getLedgers(afterLedgerId lastKnownId: String) async -> [LedgerEntry] {
        var page = 0
        var krakenLedgerUnsorted = [KrakenLedgerEntry]()

        print("last known id is: \(lastKnownId)")
        while !krakenLedgerUnsorted.contains(where: { $0.id == lastKnownId }) {
            try! await krakenLedgerUnsorted.append(contentsOf: fetchLedgersPage(page: page))
            print("fetched page \(page), total entries \(krakenLedgerUnsorted.count)")
            page += 1
        }

        var krakenLedgerNewestFirst = krakenLedgerUnsorted.sorted { a, b in a.time > b.time }
        while krakenLedgerNewestFirst.last?.id != lastKnownId {
            _ = krakenLedgerNewestFirst.popLast()
        }
        assert(krakenLedgerNewestFirst.popLast()?.id == lastKnownId)

        return convertKrakenLedgerToCommonLedger(entries: krakenLedgerNewestFirst.reversed())
    }
}
