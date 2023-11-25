
import Foundation
import SwiftCSV

class EtherscanCSVReader: CSVReader {
    func read(filePath: String) async throws -> [LedgerEntry] {
        let csv: CSV = try CSV<Named>(url: URL(fileURLWithPath: filePath))

        var ledgers = [LedgerEntry]()
        var ids = [String: Int]()
        // "Txhash","Blockno","UnixTimestamp","DateTime (UTC)","From","To","ContractAddress","Value_IN(ETH)","Value_OUT(ETH)","CurrentValue @ $2038.09311913385/Eth","TxnFee(ETH)","TxnFee(USD)","Historical $Price/Eth","Status","ErrCode","Method"
        try csv.enumerateAsDict { (dict: [String: String]) in
            let txHash = dict["Txhash"] ?? ""
            let valueIn = Decimal(string: dict["Value_IN(ETH)"] ?? "0") ?? 0
            let valueOut = Decimal(string: dict["Value_OUT(ETH)"] ?? "0") ?? 0
            let type: LedgerEntry.LedgerEntryType = valueIn > 0 ? .deposit : .withdrawal
            let amount = type == .withdrawal ? -valueOut : valueIn
            let date = Date(timeIntervalSince1970: TimeInterval(dict["UnixTimestamp"] ?? "0") ?? 0)
            let entry = LedgerEntry(
                wallet: "Etherscan",
                id: "\(txHash)-\(ids[txHash, default: 0])",
                groupId: txHash,
                date: date,
                type: type,
                amount: amount,
                asset: LedgerEntry.Asset(name: "ETH", type: .crypto)
            )
            ledgers.append(entry)
            ids[txHash, default: 0] += 1
        }

        return ledgers
    }
}
