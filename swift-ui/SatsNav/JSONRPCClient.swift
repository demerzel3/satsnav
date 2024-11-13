import Foundation
import Network

public enum JSONRPCParam: Sendable {
    case string(String)
    case bool(Bool)
}

public struct JSONRPCRequest: Sendable {
    let method: String
    let params: [String: JSONRPCParam]
}

public struct JSONRPCError: Error, Decodable, Sendable {
    let code: Int
    let message: String
}

struct JSONRPCResponse<ResultT: Decodable & Sendable>: Decodable {
    let id: Int
    let result: ResultT?
    let error: JSONRPCError?
}

@available(iOS 13.0, macOS 10.15, *)
public actor JSONRPCClient: @unchecked Sendable {
    private let connection: NWConnection
    private var lastId: Int = 0
    private let debug: Bool
    private var resultData = Data()
    private var pendingContinuation: CheckedContinuation<Data, Error>?

    public init(hostName: String, port: Int) {
        let host = NWEndpoint.Host(hostName)
        let port = NWEndpoint.Port("\(port)")!
        debug = true
        connection = NWConnection(host: host, port: port, using: .tcp)
    }

    public func start() {
        if debug {
            print("EasyTCP started")
        }
        connection.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleStateChange(state)
            }
        }
        startReceive()
        connection.start(queue: .main)
    }

    public func stop() {
        connection.cancel()
        if debug {
            print("EasyTCP stopped")
        }
    }

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .setup:
            break
        case .waiting(let error):
            if debug {
                print("EasyTCP is waiting: %@", "\(error)")
            }
        case .preparing:
            break
        case .ready:
            break
        case .failed(let error):
            if debug {
                print("EasyTCP did fail, error: %@", "\(error)")
            }
            stop()
        case .cancelled:
            if debug {
                print("EasyTCP was cancelled")
            }
            stop()
        @unknown default:
            break
        }
    }

    private func startReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                Task {
                    await self.processReceivedData(data)
                }
            }
            if let error = error {
                print("did receive, error: %@", "\(error)")
                Task {
                    await self.stop()
                }
                return
            }
            Task {
                await self.startReceive()
            }
        }
    }

    private func processReceivedData(_ data: Data) async {
        resultData.append(data)

        guard let lastByte = resultData.last, lastByte == 10 else {
            return
        }

        let currentData = resultData
        resultData.removeAll(keepingCapacity: true)
        pendingContinuation?.resume(returning: currentData)
    }

    public func send<R: Decodable & Sendable>(requests: [JSONRPCRequest]) async throws -> [Result<R, JSONRPCError>] {
        guard !requests.isEmpty else {
            return []
        }

        var expectedIds = [Int]()
        var encodedRequests = [Any]()

        for request in requests {
            let (expectedId, encodedRequest) = await encodeRequest(request: request)
            expectedIds.append(expectedId)
            encodedRequests.append(encodedRequest)
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let responseData = try await sendRequest(encodedRequests)
                    let decoder = JSONDecoder()
                    var responseArray = try decoder.decode([JSONRPCResponse<R>].self, from: responseData)

                    guard responseArray.count == requests.count else {
                        throw JSONRPCError(code: -32603, message: "Invalid response count")
                    }

                    responseArray.sort { $0.id < $1.id }

                    let results: [Result<R, JSONRPCError>] = responseArray.enumerated().map { index, element in
                        guard
                            element.id == expectedIds[index],
                            let result = element.result
                        else {
                            return .failure(element.error ?? JSONRPCError(code: -32603, message: "Invalid response"))
                        }
                        return .success(result)
                    }

                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error as? JSONRPCError ?? JSONRPCError(code: -32603, message: error.localizedDescription))
                }
            }
        }
    }

    private func sendRequest(_ request: Any) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            guard var data = try? JSONSerialization.data(withJSONObject: request) else {
                continuation.resume(throwing: JSONRPCError(code: -32700, message: "Invalid JSON request"))
                return
            }

            data.append("\n".data(using: .utf8)!)

            self.connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: JSONRPCError(code: -32603, message: error.localizedDescription))
                } else {
                    Task { [weak self] in
                        await self?.setPendingContinuation(continuation)
                    }
                }
            })
        }
    }

    private func setPendingContinuation(_ continuation: CheckedContinuation<Data, Error>) {
        pendingContinuation = continuation
    }

    private func encodeRequest(request: JSONRPCRequest) async -> (id: Int, payload: [String: Any]) {
        lastId += 1

        return (lastId, [
            "jsonrpc": "2.0",
            "id": lastId,
            "method": request.method,
            "params": request.params.mapValues { param -> Any in
                switch param {
                case .bool(let value):
                    return value
                case .string(let value):
                    return value
                }
            }
        ])
    }
}
