import Foundation
import SwiftData

/// 一个「板」——把任务按人生的不同战线分开:投简历 / 刷题 / 健身 / 备孕…
@Model
final class Project {
    var name: String
    var emoji: String
    var sortOrder: Int
    var createdAt: Date
    var uid: String = ""

    init(name: String, emoji: String, sortOrder: Int) {
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.uid = UUID().uuidString
    }
}

extension Project {
    /// 新建板时可选的图标
    static let emojiPalette = [
        "📥", "💼", "🧠", "💪", "🌱", "📚", "🏠", "❤️", "✈️", "🎯", "💰", "🎨",
    ]

    /// 首次升级时给老数据兜底的默认板
    static let defaultName = "General"
    static let defaultEmoji = "📥"
}
