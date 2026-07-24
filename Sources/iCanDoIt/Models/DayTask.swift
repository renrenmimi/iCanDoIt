import Foundation
import SwiftData

@Model
final class DayTask {
    var title: String
    var reward: String
    var dayKey: String
    var createdAt: Date
    var completedAt: Date?
    var sortOrder: Int

    init(title: String, reward: String, dayKey: String, sortOrder: Int) {
        self.title = title
        self.reward = reward
        self.dayKey = dayKey
        self.createdAt = .now
        self.completedAt = nil
        self.sortOrder = sortOrder
    }

    var isDone: Bool { completedAt != nil }
}

/// 晨间仪式页里还未落库的任务草稿
struct TaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var reward: String
}

extension Date {
    /// 本地时区的天级标识,如 "2026-07-18",用于按天归组
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum DateInfo {
    static var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    static var todayString: String {
        Date.now.formatted(
            .dateTime.weekday(.wide).month().day()
                .locale(Locale(identifier: "en_US"))
        )
    }
}
