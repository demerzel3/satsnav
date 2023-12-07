import Combine
import Foundation
import KrakenAPI
import SwiftCSV

class HistoricPriceProvider: ObservableObject {
    @Published var prices = [Date: Decimal]()

    private let client: Kraken

    init() {
        let credentials = Kraken.Credentials(apiKey: "", privateKey: "")
        client = Kraken(credentials: credentials)
    }

    private func loadFromFile() -> [Date: Decimal] {
        guard let csv = try? CSV<Named>(name: "XBTEUR_1440.csv") else {
            return [Date: Decimal]()
        }

        var prices = [Date: Decimal]()
        // time,o,h,l,c,v,t
        try? csv.enumerateAsDict { dict in
            guard let timestamp = dict["time"].flatMap({ Int($0) }),
                  let price = dict["o"].map({ Decimal(string: $0) })
            else {
                return
            }

            prices[Date(timeIntervalSince1970: TimeInterval(timestamp))] = price
        }

        return prices
    }

    func load() {
        client.ohlcData(pair: "XXBTZEUR", interval: .i1440min) { response in
            guard case .success(let result) = response else {
                print("Invalid prices response")
                return
            }

            guard var candles = result["XXBTZEUR"] as? [[Any]] else {
                print("Invalid prices response")
                return
            }

            // Last element is the current day, we rely on the WS to keep that up to date
            candles.removeLast()

            // TODO: not necessarily the best place to call loadFromFile.. but hey!
            let prices = candles.reduce(into: self.loadFromFile()) { prices, item in
                guard let timestamp = item[0] as? Int,
                      let priceStr = item[1] as? String,
                      let price = Decimal(string: priceStr)
                else {
                    return
                }

                prices[Date(timeIntervalSince1970: TimeInterval(timestamp))] = price
            }

            DispatchQueue.main.async {
                self.prices = prices
            }
        }
    }
}
