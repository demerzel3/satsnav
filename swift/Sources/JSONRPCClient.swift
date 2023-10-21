import Foundation
import Grammar
import JSON
import Network

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
        print("parsed up to @\(parsingInput.index)")
        self.resultData.removeFirst(parsingInput.index)
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
        
    public func send(request: JSON) async throws -> JSON {
        return await withCheckedContinuation { continuation in
            self.send(request: request) { response in
                continuation.resume(returning: response)
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
}
