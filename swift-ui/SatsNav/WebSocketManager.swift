import Foundation
import Starscream
import UIKit

class WebSocketManager: ObservableObject {
    @Published var isConnected = false
    @Published var btcPrice: Decimal = 0
    private var btcPriceLastUpdated: Date?
    private var socket: WebSocket?
    private var notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        addAppLifecycleObservers()
    }

    private func addAppLifecycleObservers() {
        notificationCenter.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        print("--- ENTERING BACKGROUND, disconnecting 📉")
        disconnect()
    }

    @objc private func appWillEnterForeground() {
        print("--- ENTERING FOREGROUND, connecting 🚀")
        connect()
    }

    func connect() {
        guard let url = URL(string: "wss://ws.kraken.com") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        socket = WebSocket(request: request)
        // socket?.delegate = self
        socket?.connect()
        socket?.onEvent = { event in
            switch event {
            case .connected:
                self.isConnected = true
                print("websocket is connected")
                self.socket?.write(string: """
                {"event":"subscribe","pair":["XBT/EUR"],"subscription":{"name":"ticker"}}
                """, completion: {
                    // TODO: need to do something here?
                })
            case .disconnected(let reason, let code):
                self.isConnected = false
                print("websocket is disconnected: \(reason) with code: \(code)")
            case .text(let string):
                // Ignore heartbeat events
                if string == "{\"event\":\"heartbeat\"}" {
                    break
                }

                // Try to parse the incoming message as a ticker
                if let jsonData = string.data(using: .utf8),
                   let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [Any],
                   let tickerData = jsonArray[1] as? [String: Any],
                   let cArray = tickerData["c"] as? [Any],
                   let closePriceStr = cArray.first as? String,
                   let closePrice = Decimal(string: closePriceStr)
                {
                    self.setBtcPriceDebounced(nextPrice: closePrice)
                } else {
                    print("Received text: \(string)")
                }
            case .binary(let data):
                print("Received data: \(data.count)")
            case .ping:
                break
            case .pong:
                break
            case .viabilityChanged:
                break
            case .reconnectSuggested:
                break
            case .cancelled:
                self.isConnected = false
            case .error(let error):
                self.isConnected = false
                print("WEBSOCKET ERROR", error as Any)
            case .peerClosed:
                break
            }
        }
    }

    func disconnect() {
        socket?.disconnect()
    }

    // Debounced to avoid too many updates
    func setBtcPriceDebounced(nextPrice: Decimal) {
        if let lastUpdated = btcPriceLastUpdated, Date.now.timeIntervalSince(lastUpdated) < 2.5 {
            return
        }

        btcPrice = nextPrice
        btcPriceLastUpdated = Date.now
    }
}
