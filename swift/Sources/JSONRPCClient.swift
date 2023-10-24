import Foundation
import Grammar
import JSON
import Network

public enum JSONRPCParam {
    case string(String)
    case bool(Bool)
}

public struct JSONRPCRequest {
    let method: String
    let params: [String: JSONRPCParam]
}

@available(iOS 13.0, macOS 10.15, *)
public class JSONRPCClient: ObservableObject {
    public init(hostName: String, port: Int) {
        let host = NWEndpoint.Host(hostName)
        let port = NWEndpoint.Port("\(port)")!
        self.debug = true
        self.connection = NWConnection(host: host, port: port, using: .tcp)
    }

    public typealias Completion = (JSON) -> ()
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
        print("received data length", data.count)

        var parsingInput: ParsingInput<NoDiagnostics<Data>> = .init(resultData)
        while let result: JSON = parsingInput.parse(as: JSON.Rule<Int>.Root?.self) {
            if let completion = self.completion {
                completion(result)
                self.completion = nil
            } else {
                print("ERROR: completion is not defined for result", result)
                fatalError()
            }
        }
        print("parsed up to @\(parsingInput.index - self.resultData.startIndex)")
        self.resultData.removeFirst(parsingInput.index - self.resultData.startIndex)
        print("remaining buffer size:", self.resultData.count)
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

    public func send<Result>(request: JSONRPCRequest) async -> Result? where Result: Decodable {
        return await withCheckedContinuation { continuation in
            let (id, encodedRequest) = self.encodeRequest(request: request)
            self.send(request: encodedRequest) { response in
                if let result = extractResult(response: response, expectedId: id) {
                    do {
                        try continuation.resume(returning: Result(from: result))
                    } catch {
                        print("Unable to decode JSON")
                        continuation.resume(returning: nil)
                        return
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func send<Result>(requests: [JSONRPCRequest]) async -> [Result]? where Result: Decodable {
        return await withCheckedContinuation { continuation in
            var expectedIds = [Int]()
            var encodedRequests = [JSON]()

            for request in requests {
                let (expectedId, encodedRequest) = self.encodeRequest(request: request)
                expectedIds.append(expectedId)
                encodedRequests.append(encodedRequest)
            }

            let encodedRequest = JSON.array(JSON.Array(encodedRequests))
            self.send(request: encodedRequest) { response in
                guard var responseArray = response.array else {
                    continuation.resume(returning: nil)
                    return
                }

                guard responseArray.elements.count == requests.count else {
                    print("Invalid number of responses, expected \(requests.count), received \(responseArray.elements.count)")
                    continuation.resume(returning: nil)
                    return
                }

                // Sort responses by ID
                responseArray.elements.sort {
                    guard let a = $0.object?.byKey(key: "id")?.number?.units else {
                        return false
                    }

                    guard let b = $1.object?.byKey(key: "id")?.number?.units else {
                        return true
                    }

                    return a < b
                }

                var results = [Result]()
                for (index, element) in responseArray.elements.enumerated() {
                    // TODO: handle case where we have no "result" but we have "error"
                    let maybeResult = extractResult(response: element, expectedId: expectedIds[index])
                    guard let result = maybeResult else {
                        // TODO: Could return error for the specific request
                        continuation.resume(returning: nil)
                        return
                    }

                    do {
                        try results.append(Result(from: result))
                    } catch {
                        print("Unable to decode JSON")
                        continuation.resume(returning: nil)
                        return
                    }
                }
                continuation.resume(returning: results)
            }
        }
    }

    private func send(request: JSON, completion: @escaping Completion) {
        guard self.completion == nil else {
            print("completion must be nil")
            fatalError()
        }
        guard var data = request.description.data(using: .utf8) else {
            print("cannot encode request as UTF-8")
            fatalError()
        }
        data.append("\n".data(using: .utf8)!)
        self.connection.send(content: data, completion: NWConnection.SendCompletion.contentProcessed { error in
            if let error = error {
                print("did send, error: %@", "\(error)")
                self.stop()
            } else {
                print("did send, no error")
                self.completion = completion
            }
        })
    }

    private func encodeRequest(request: JSONRPCRequest) -> (id: Int, payload: JSON) {
        self.lastId += 1

        return (self.lastId, JSON.object([
            "jsonrpc": JSON.string("2.0"),
            "id": JSON.number(JSON.Number(self.lastId)),
            "method": JSON.string(request.method),
            "params": JSON.object(JSON.Object(request.params.map {
                let key = JSON.Key(stringLiteral: $0.key)
                switch $0.value {
                case .bool(let value):
                    return (key, JSON.bool(value))
                case .string(let value):
                    return (key, JSON.string(value))
                }
            }))
        ]))
    }
}

private func extractResult(response: JSON, expectedId: Int) -> JSON? {
    guard let obj = response.object else {
        return nil
    }

    guard let idJson = obj.byKey(key: "id") else {
        return nil
    }

    guard let id = idJson.number else {
        return nil
    }

    guard id.units == expectedId else {
        print("Invalid response id, expected \(expectedId), received \(id.units)")
        return nil
    }

    return obj.byKey(key: "result")
}

public extension JSON {
    @inlinable
    var number: Number? {
        switch self {
        case .number(let number):
            return number
        default:
            return nil
        }
    }
}

private extension JSON.Object {
    func byKey(key: String) -> JSON? {
        self.fields.first(where: { $0.key.rawValue == key })?.value
    }
}
