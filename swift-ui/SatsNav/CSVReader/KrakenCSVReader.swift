import Foundation
import SwiftCSV

private func createDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    // Set the locale to ensure that the date formatter doesn't get affected by the user's locale.
    formatter.locale = Locale(identifier: "en_US_POSIX")

    return formatter
}

class KrakenCSVReader: CSVReader {
    private let dateFormatter = createDateFormatter()

    func read(fileUrl: URL) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: fileUrl)
        var krakenLedger = [KrakenLedgerEntry]()

        // "txid","refid","time","type","subtype","aclass","asset","amount","fee","balance"
        try csv.enumerateAsDict { dict in
            krakenLedger.append(KrakenLedgerEntry(
                id: dict["txid"] ?? "",
                refId: dict["refid"] ?? "",
                time: self.dateFormatter.date(from: dict["time"] ?? "") ?? Date.now,
                type: dict["type"] ?? "",
                subtype: dict["subtype"] ?? "",
                asset: dict["asset"] ?? "",
                amount: Decimal(string: dict["amount"] ?? "0") ?? 0,
                fee: Decimal(string: dict["fee"] ?? "0") ?? 0,
                balance: Decimal(string: dict["balance"] ?? "0") ?? 0
            ))
        }

        return convertKrakenLedgerToCommonLedger(entries: krakenLedger)
    }
}
