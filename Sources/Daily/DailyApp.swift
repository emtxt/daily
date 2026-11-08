import SwiftUI

@main
struct DailyApp: App {
    var body: some Scene {
        Window("Daily", id: "planner") {
            PlannerView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1080, height: 740)
    }
}
