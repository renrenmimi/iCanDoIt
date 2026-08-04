import Foundation
import SwiftData

@Model
final class DayTask {
    var title: String
    var reward: String
    /// 旧版字段:只保留以保证老数据平滑迁移,新逻辑一律看 bucketKey
    var dayKey: String
    /// 任务所在的「列」——看板的核心。格式见 BucketKey
    var bucketKey: String = ""
    /// 拖拽时用的稳定标识(PersistentIdentifier 不便直接当拖拽载荷)
    var uid: String = ""
    var createdAt: Date
    var completedAt: Date?
    var sortOrder: Int

    init(title: String, reward: String, bucketKey: String, sortOrder: Int) {
        self.title = title
        self.reward = reward
        self.bucketKey = bucketKey
        self.uid = UUID().uuidString
        // 兼容旧字段:日任务写日期,周/月任务写创建当天
        self.dayKey = BucketKey.dayValue(of: bucketKey) ?? Date.now.dayKey
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

// MARK: - 列标识

/// 任务所在列的标识。三种粒度:
/// - 某一天   `d:2026-08-03`
/// - 某一周   `w:2026-W32`(ISO 周)
/// - 某一月   `m:2026-08`
enum BucketKey {
    static func day(_ date: Date) -> String { "d:\(date.dayKey)" }

    static func week(_ date: Date) -> String {
        let c = Calendar.iso8601.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "w:%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    static func month(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "m:%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// 从 `d:2026-08-03` 取出 `2026-08-03`;非日列返回 nil
    static func dayValue(of bucketKey: String) -> String? {
        bucketKey.hasPrefix("d:") ? String(bucketKey.dropFirst(2)) : nil
    }
}

extension Calendar {
    /// 周一为一周之首(ISO 8601),避免"这周"跨越周日时错位
    static let iso8601: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }()
}

extension Date {
    /// 本地时区的天级标识,如 "2026-07-18",用于按天归组
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 所在 ISO 周的周一
    var startOfWeek: Date {
        let cal = Calendar.iso8601
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)) ?? self
    }

    /// 所在月的 1 号
    var startOfMonth: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: self)) ?? self
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
