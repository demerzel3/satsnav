extension JSONRPCRequest {
    static func getScripthashHistory(scriptHash: String) -> JSONRPCRequest {
        return self.init(
            method: "blockchain.scripthash.get_history",
            params: ["scripthash": .string(scriptHash)]
        )
    }

    static func getTransaction(txHash: String, verbose: Bool) -> JSONRPCRequest {
        return self.init(
            method: "blockchain.transaction.get",
            params: ["tx_hash": .string(txHash), "verbose": .bool(verbose)]
        )
    }
}

struct GetScriptHashHistoryResultItem: Decodable {
    let tx_hash: String
    let height: Int
}

typealias GetScriptHashHistoryResult = [GetScriptHashHistoryResultItem]
