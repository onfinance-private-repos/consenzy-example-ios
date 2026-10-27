import SwiftUI

@main
struct ConsenzyExampleApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let session = state.signedIn {
                    HomeView(session: session)
                } else {
                    SignInView()
                }
            }
            .environmentObject(state)
        }
    }
}
