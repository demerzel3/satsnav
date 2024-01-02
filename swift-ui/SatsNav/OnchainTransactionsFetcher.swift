import Foundation

final class OnchainTransactionsFetcher {
    private var storage = TransactionStorage()
    private let client = JSONRPCClient(hostName: "electrum1.bluewallet.io", port: 50001)

    private func retrieveAndStoreTransactions(txIds: [String]) async -> [ElectrumTransaction] {
        let txIdsSet = Set<String>(txIds)
        print("requesting transaction information for", txIdsSet.count, "transactions")

        // Do not request transactions that we have already stored
        let unknownTransactionIds = await storage.notIncludedTxIds(txIds: txIdsSet)
        if unknownTransactionIds.count > 0 {
            let txRequests = Set<String>(unknownTransactionIds).map { JSONRPCRequest.getTransaction(txHash: $0, verbose: true) }
            guard let transactions: [Result<ElectrumTransaction, JSONRPCError>] = await client.send(requests: txRequests) else {
                print("🚨 Unable to get transactions")
                exit(1)
            }

            // TODO: do something with the errors maybe? at least log them!
            let validTransactions = transactions.compactMap { if case .success(let t) = $0 { t } else { nil } }
            let storageSize = await storage.store(transactions: validTransactions)
            print("Retrieved \(validTransactions.count) transactions, in store: \(storageSize)")

            // Commit transactions storage to disk
            await storage.write()
        }

        return await storage.getTransactions(byIds: txIdsSet)
    }

    // Manual transactions have usually a number of inputs (in case of consolidation)
    // but only one output, + optional change
    private func isManualTransaction(_ transaction: ElectrumTransaction) -> Bool {
        return transaction.vout.count <= 2
    }

    func fetchOnchainTransactions(addresses: [Address], cacheOnly: Bool = false) async -> [LedgerEntry] {
        await storage.read()
        client.start()
        let internalAddresses = Set<Address>(addresses)

        func writeCache(txIds: [String]) {
            let filePath = FileManager.default.temporaryDirectory.appendingPathComponent("rootTransactionIds.plist")
            print(filePath)
            do {
                let data = try PropertyListEncoder().encode(txIds)
                try data.write(to: filePath)
                print("Root tx ids saved successfully!")
            } catch {
                fatalError("Error saving root tx ids: \(error)")
            }
        }

        func readCache() -> [String] {
            let filePath = FileManager.default.temporaryDirectory.appendingPathComponent("rootTransactionIds.plist")
            print(filePath)
            do {
                let data = try Data(contentsOf: filePath)
                let txIds = try PropertyListDecoder().decode([String].self, from: data)
                print("Retrieved root tx ids from disk: \(txIds.count)")

                return txIds
            } catch {
                fatalError("Error retrieving root tx ids: \(error)")
            }
        }

        func electrumTransactionToLedgerEntries(_ transaction: ElectrumTransaction) async -> [LedgerEntry] {
            var totalIn: Decimal = 0
            var transactionVin = [OnchainTransaction.Vin]()
            for vin in transaction.vin {
                guard let vinTxId = vin.txid else {
                    continue
                }
                guard let vinTx = await storage.getTransaction(byId: vinTxId) else {
                    continue
                }
                guard let voutIndex = vin.vout else {
                    continue
                }

                let vout = vinTx.vout[voutIndex]
                let amount = readBtcAmount(vout.value)

                guard let vinAddress = vout.scriptPubKey.address else {
                    print("\(vinTxId):\(voutIndex) has no address")
                    continue
                }
                guard let vinScriptHash = getScriptHashForElectrum(vout.scriptPubKey) else {
                    print("Could not compute script hash for address \(vinAddress)")
                    continue
                }

                totalIn += amount
                transactionVin.append(OnchainTransaction.Vin(
                    txid: vinTxId,
                    voutIndex: voutIndex,
                    amount: amount,
                    address: Address(id: vinAddress, scriptHash: vinScriptHash)
                ))
            }

            var totalOut: Decimal = 0
            var transactionVout = [OnchainTransaction.Vout]()
            for vout in transaction.vout {
                guard let voutAddress = vout.scriptPubKey.address else {
                    continue
                }
                guard let voutScriptHash = getScriptHashForElectrum(vout.scriptPubKey) else {
                    print("Could not compute script hash for address \(voutAddress)")
                    continue
                }

                let amount = readBtcAmount(vout.value)
                totalOut += amount
                transactionVout.append(OnchainTransaction.Vout(
                    amount: amount,
                    address: Address(id: voutAddress, scriptHash: voutScriptHash)
                ))
            }

            let (knownVin, _) = transactionVin.partition { internalAddresses.contains($0.address) }
            let (knownVout, unknownVout) = transactionVout.partition { internalAddresses.contains($0.address) }

            let fees = totalIn - totalOut
            let types: [(LedgerEntry.LedgerEntryType, Decimal)] = if
                knownVin.count == transaction.vin.count,
                knownVout.count == transaction.vout.count
            {
                // vin and vout are all known, it's consolidation or internal transaction, we track each output separately
                transactionVout.flatMap { [(.withdrawal, $0.amount), (.deposit, $0.amount)] } + [(.fee, -fees)]
            } else if knownVin.count == transaction.vin.count {
                // All vin known, it must be a transfer out of some kind
                [
                    (.withdrawal, -unknownVout.reduce(0) { sum, vout in sum + vout.amount }),
                    (.fee, -fees),
                ]
            } else if knownVin.count == 0 {
                // No vin is known, must be a deposit.
                // Split by vout in case we are receiving multiple from different sources, easier to match.
                knownVout.map { (.deposit, $0.amount) }
            } else {
                [(.transfer, 0)]
            }

            let date = Date(timeIntervalSince1970: TimeInterval(transaction.time ?? 0))

            return types.enumerated().map { index, item in LedgerEntry(
                wallet: "❄️",
                id: types.count > 1 ? "\(transaction.txid)-\(index)" : transaction.txid,
                groupId: transaction.txid,
                date: date,
                type: item.0,
                amount: item.1,
                asset: .init(name: "BTC", type: .crypto)
            ) }
        }

        func fetchRootTransactionIds() async -> [String] {
            let internalAddressesList = internalAddresses.map { $0 }
            let historyRequests = internalAddressesList
                .map { address in
                    JSONRPCRequest.getScripthashHistory(scriptHash: address.scriptHash)
                }
            print("Requesting transactions for \(historyRequests.count) addresses")
            guard let history: [Result<GetScriptHashHistoryResult, JSONRPCError>] = await client.send(requests: historyRequests) else {
                fatalError("🚨 Unable to get history")
            }

            // Collect transaction ids and log failures.
            var txIds = [String]()
            for (address, res) in zip(internalAddressesList, history) {
                switch res {
                case .success(let history):
                    txIds.append(contentsOf: history.map { $0.tx_hash })
                case .failure(let error):
                    print("🚨 history request failed for address \(address.id)", error)
                }
            }
            // Save collected txids to cache
            writeCache(txIds: txIds)

            return txIds
        }

        let txIds = cacheOnly ? readCache() : await fetchRootTransactionIds()
        let rootTransactions = await retrieveAndStoreTransactions(txIds: txIds)
        let refTransactionIds = rootTransactions
            .filter { isManualTransaction($0) }
            .flatMap { transaction in transaction.vin.map { $0.txid } }
            .compactMap { $0 }
        _ = await retrieveAndStoreTransactions(txIds: refTransactionIds)

        var entries = [LedgerEntry]()
        for rawTransaction in rootTransactions {
            entries.append(contentsOf: await electrumTransactionToLedgerEntries(rawTransaction))
        }

        return entries
    }
}
