import SwiftUI

@main
struct DailyTaskApp: App {
    @State private var store = TaskStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
                .task {
                    // Check for updates in the background after launch
                    try? await Task.sleep(for: .seconds(2))
                    await UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
                }
        } label: {
            let incompleteCount = store.incompleteTaskCount
            HStack(spacing: 4) {
                Image(systemName: incompleteCount > 0 ? "checklist.checked" : "checklist")
                if incompleteCount > 0 {
                    Text("\(incompleteCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
