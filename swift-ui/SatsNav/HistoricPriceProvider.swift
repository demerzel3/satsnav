import Foundation

struct Price {
    let timestamp: Int
    let price: Decimal
}

class HistoricPriceProvider: ObservableObject {
    @Published var price = [Price]()

    // TODO: fetch historic data from Kraken to build a chart
    // Stacked area chart with fiat on the y axes and dates on the x, with 3 areas:
    // - capital, interests and price appreciation
    // Do a prototype first, might not be that interesting 🤷‍♂️
}
