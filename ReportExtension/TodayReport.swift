import DeviceActivity
import DoomscrollKit
import ExtensionKit
import SwiftUI

/// Draws the Today ring with exact minutes. iOS renders this in a sandbox inside the app's window: the app
/// itself never sees the number, and nothing here can send it anywhere.
@main
struct DoomscrollReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayReport { TodayRing(minutes: $0.minutes, limit: $0.limit, exact: true) }
    }
}

extension DeviceActivityReport.Context {
    static let today = Self("today")
}

struct TodayConfiguration {
    let minutes: Int
    let limit: Int?
}

nonisolated struct TodayReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .today
    let content: (TodayConfiguration) -> TodayRing

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayConfiguration {
        // The app's filter already limits this to the picked apps and categories.
        var total: TimeInterval = 0
        for await device in data {
            for await segment in device.activitySegments {
                for await category in segment.categories {
                    total += category.totalActivityDuration
                }
            }
        }
        return TodayConfiguration(minutes: Int(total / 60), limit: SharedSettings.shared.dailyLimitMinutes)
    }
}
