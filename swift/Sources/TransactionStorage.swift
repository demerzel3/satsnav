import Foundation

actor TransactionStorage {
    private var transactions = [String: ElectrumTransaction]()

    // Function to retrieve a transaction given its ID
    func getTransaction(by id: String) async -> ElectrumTransaction? {
        return transactions[id]
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
    func notIncludedTxIds(txIds: [String]) -> [String] {
        return txIds.filter { !includes(txid: $0) }
    }
}
