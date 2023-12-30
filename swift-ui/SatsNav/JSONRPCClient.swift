import Foundation
import Network

public enum JSONRPCParam {
    case string(String)
    case bool(Bool)
}

public struct JSONRPCRequest {
    let method: String
    let params: [String: JSONRPCParam]
}

public struct JSONRPCError: Error, Decodable {
    let code: Int
    let message: String
}

struct JSONRPCResponse<ResultT: Decodable>: Decodable {
    let id: Int
    let result: ResultT?
    let error: JSONRPCError?
}

@available(iOS 13.0, macOS 10.15, *)
public class JSONRPCClient: ObservableObject {
    public init(hostName: String, port: Int) {
        let host = NWEndpoint.Host(hostName)
        let port = NWEndpoint.Port("\(port)")!
        self.debug = true
        self.connection = NWConnection(host: host, port: port, using: .tcp)
    }

    public typealias Completion = (Data) -> ()
    public let connection: NWConnection
    private var lastId: Int = 0
    private let debug: Bool
    private var resultData = Data()
    private var completion: Completion? = nil

    public func start() {
        if self.debug {
            print("EasyTCP started")
        }
        self.connection.stateUpdateHandler = self.didChange(state:)
        self.startReceive()
        self.connection.start(queue: .main)
    }

    public func stop() {
        self.connection.cancel()
        if self.debug {
            print("EasyTCP stopped")
        }
    }

    private func didChange(state: NWConnection.State) {
        switch state {
        case .setup:
            break
        case .waiting(let error):
            if self.debug {
                print("EasyTCP is waiting: %@", "\(error)")
            }
        case .preparing:
            break
        case .ready:
            break
        case .failed(let error):
            if self.debug {
                print("EasyTCP did fail, error: %@", "\(error)")
            }
            self.stop()
        case .cancelled:
            if self.debug {
                print("EasyTCP was cancelled")
            }
            self.stop()
        @unknown default:
            break
        }
    }

    private func checkData(data: Data) {
        self.resultData.append(data)
        // print("received data length", data.count)

        guard let lastByte = self.resultData.last else {
            return
        }

        guard lastByte == 10 else {
            // print("Probably not end of stream", lastByte)
            return
        }

        if let completion = self.completion {
            completion(self.resultData)
            self.completion = nil
            self.resultData.removeAll(keepingCapacity: true)
        } else {
            fatalError("ERROR: completion is not defined")
        }
    }

    private func startReceive() {
        self.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
            if let data = data, !data.isEmpty {
                self.checkData(data: data)
            }
            if let error = error {
                print("did receive, error: %@", "\(error)")
                self.stop()
                return
            }
            self.startReceive()
        }
    }

    public func send<R>(requests: [JSONRPCRequest]) async -> [Result<R, JSONRPCError>]? where R: Decodable {
        guard requests.count > 0 else {
            return [Result<R, JSONRPCError>]()
        }

        // TODO: might be possible to remove the type in `continuation`
        return await withCheckedContinuation { (continuation: CheckedContinuation<[Result<R, JSONRPCError>]?, Never>) in
            var expectedIds = [Int]()
            var encodedRequests = [Any]()

            for request in requests {
                let (expectedId, encodedRequest) = self.encodeRequest(request: request)
                expectedIds.append(expectedId)
                encodedRequests.append(encodedRequest)
            }

            // let encodedRequest = JSON.array(JSON.Array(encodedRequests))
            self.send(request: encodedRequests) { response in
                let decoder = JSONDecoder()
                var responseArray = try! decoder.decode([JSONRPCResponse<R>].self, from: response)
//                guard var responseArray = try? decoder.decode([JSONRPCResponse<R>].self, from: response) else {
//                    print("Invalid JSON response")
//                    continuation.resume(returning: nil)
//                    return
//                }

                guard responseArray.count == requests.count else {
                    print("Invalid number of responses, expected \(requests.count), received \(responseArray.count)")
                    continuation.resume(returning: nil)
                    return
                }

                // Sort responses by ID
                responseArray.sort { a, b in a.id < b.id }

                var results = [Result<R, JSONRPCError>]()
                for (index, element) in responseArray.enumerated() {
                    guard
                        element.id == expectedIds[index],
                        let result = element.result
                    else {
                        results.append(.failure(element.error!))
                        continue
                    }

                    results.append(.success(result))
                }
                continuation.resume(returning: results)
            }
        }
    }

    private func send(request: Any, completion: @escaping Completion) {
        guard self.completion == nil else {
            print("completion must be nil")
            fatalError()
        }
        guard var data = try? JSONSerialization.data(withJSONObject: request) else {
            fatalError("Cannot JSON encode \(request)")
        }
        data.append("\n".data(using: .utf8)!)
        self.connection.send(content: data, completion: NWConnection.SendCompletion.contentProcessed { error in
            if let error = error {
                print("did send, error: %@", "\(error)")
                self.stop()
            } else {
                self.completion = completion
            }
        })
    }

    private func encodeRequest(request: JSONRPCRequest) -> (id: Int, payload: [String: Any]) {
        self.lastId += 1

        return (self.lastId, [
            "jsonrpc": "2.0",
            "id": self.lastId,
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
