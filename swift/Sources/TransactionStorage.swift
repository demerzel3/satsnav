import Foundation

actor TransactionStorage {
    private var transactions = [String: ElectrumTransaction]()

    // Function to retrieve a transaction given its ID
    func getTransaction(byId id: String) async -> ElectrumTransaction? {
        return transactions[id]
    }

    func getTransactions(byIds ids: any Sequence<String>) async -> [ElectrumTransaction] {
        return ids.map { transactions[$0] }.compactMap { $0 }
    }

    // Function to store a new transaction
    func store(transaction: ElectrumTransaction) -> Int {
        transactions[transaction.txid] = transaction
        return transactions.count
    }

    func store(transactions: [ElectrumTransaction]) -> Int {
        for transaction in transactions {
            _ = store(transaction: transaction)
        }
        return transactions.count
    }

    // Function to check if a transaction ID exists in storage
    func includes(txid: String) -> Bool {
        return transactions.keys.contains(txid)
    }

    // Filters out txids that are currently in the storage
    func notIncludedTxIds(txIds: any Sequence<String>) -> [String] {
        return txIds.filter { !includes(txid: $0) }
    }

    func write() {
        let filePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("transactions.plist")
        print(filePath)
        do {
            let data = try PropertyListEncoder().encode(transactions)
            try data.write(to: filePath)
            print("Transactions saved successfully!")
        } catch {
            print("Error saving transactions: \(error)")
        }
    }

    func read() {
        let filePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("transactions.plist")
        print(filePath)
        do {
            let data = try Data(contentsOf: filePath)
            transactions = try PropertyListDecoder().decode([String: ElectrumTransaction].self, from: data)
            print("Retrieved transactions from disk: \(transactions.count)")
        } catch {
            print("Error retrieving transactions: \(error)")
        }
    }
}
