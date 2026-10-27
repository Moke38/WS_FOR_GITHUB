import SwiftUI

@main
struct StockMoverApp: App {
    @State private var viewModel = MoversViewModel(service: YahooFinanceService())

    var body: some Scene {
        WindowGroup {
            MoversListView(viewModel: viewModel)
        }
    }
}
