import Foundation
import SwiftData

/// 看板的三种视角
enum BoardScope: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// 看板上的一列(Trello 里的 List)
struct BoardColumn: Identifiable, Equatable {
    let id: String          // 就是 bucketKey
    let title: String       // "Mon" / "Week 32" / "This Week"
    let subtitle: String    // "Aug 3" / "Aug 3 – 9"
    let isToday: Bool
    let isGoalColumn: Bool  // 左侧那列「本周/本月目标」
    /// 这一列覆盖的日列(仅月视图的周列用):拿来汇总"这周有几件日任务"
    var dayBuckets: [String] = []

    static func == (a: BoardColumn, b: BoardColumn) -> Bool { a.id == b.id }
}

enum BoardLayout {
    /// 周视图:本周目标 + 周一…周日
    static func weekColumns(anchor: Date) -> [BoardColumn] {
        let cal = Calendar.iso8601
        let monday = anchor.startOfWeek
        let todayKey = BucketKey.day(.now)

        let goal = BoardColumn(
            id: BucketKey.week(anchor),
            title: "This Week",
            subtitle: rangeText(from: monday, days: 7),
            isToday: false,
            isGoalColumn: true
        )

        let days = (0..<7).compactMap { offset -> BoardColumn? in
            guard let date = cal.date(byAdding: .day, value: offset, to: monday) else { return nil }
            let key = BucketKey.day(date)
            return BoardColumn(
                id: key,
                title: date.formatted(.dateTime.weekday(.abbreviated).locale(.en)),
                subtitle: date.formatted(.dateTime.month(.abbreviated).day().locale(.en)),
                isToday: key == todayKey,
                isGoalColumn: false
            )
        }
        return [goal] + days
    }

    /// 月视图:本月目标 + 该月覆盖的每个 ISO 周
    static func monthColumns(anchor: Date) -> [BoardColumn] {
        let cal = Calendar.iso8601
        let first = anchor.startOfMonth
        let dayCount = Calendar.current.range(of: .day, in: .month, for: first)?.count ?? 30
        let thisWeekKey = BucketKey.week(.now)

        let goal = BoardColumn(
            id: BucketKey.month(anchor),
            title: "This Month",
            subtitle: first.formatted(.dateTime.month(.wide).year().locale(.en)),
            isToday: false,
            isGoalColumn: true
        )

        // 逐周推进,收集这个月里出现过的所有周
        var weeks: [BoardColumn] = []
        var cursor = first.startOfWeek
        let monthEnd = cal.date(byAdding: .day, value: dayCount - 1, to: first) ?? first
        while cursor <= monthEnd {
            let key = BucketKey.week(cursor)
            let weekNo = cal.component(.weekOfYear, from: cursor)
            let days = (0..<7).compactMap { off in
                cal.date(byAdding: .day, value: off, to: cursor).map(BucketKey.day)
            }
            weeks.append(BoardColumn(
                id: key,
                title: "Week \(weekNo)",
                subtitle: rangeText(from: cursor, days: 7),
                isToday: key == thisWeekKey,
                isGoalColumn: false,
                dayBuckets: days
            ))
            guard let next = cal.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return [goal] + weeks
    }

    /// "Aug 3 – 9"
    private static func rangeText(from start: Date, days: Int) -> String {
        let cal = Calendar.iso8601
        let end = cal.date(byAdding: .day, value: days - 1, to: start) ?? start
        let s = start.formatted(.dateTime.month(.abbreviated).day().locale(.en))
        let sameMonth = cal.component(.month, from: start) == cal.component(.month, from: end)
        let e = sameMonth
            ? end.formatted(.dateTime.day().locale(.en))
            : end.formatted(.dateTime.month(.abbreviated).day().locale(.en))
        return "\(s) – \(e)"
    }
}

extension Locale {
    static let en = Locale(identifier: "en_US")
}

// MARK: - 拖拽落位

enum BoardMove {
    /// 一列里的显示顺序:未完成置顶(手动序),已完成沉底(按完成时间)
    static func ordered(_ tasks: [DayTask], in bucket: String) -> [DayTask] {
        let inBucket = tasks.filter { $0.bucketKey == bucket }
        let pending = inBucket.filter { !$0.isDone }.sorted { $0.sortOrder < $1.sortOrder }
        let done = inBucket.filter(\.isDone)
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        return pending + done
    }

    /// 把 task 移到 bucket 列的第 index 个位置(index 为 nil 表示追加到末尾)。
    /// 抽成纯函数是为了能在 --selftest 里直接验证(拖拽手势本身没法自动化)。
    @discardableResult
    static func apply(
        moving task: DayTask, to bucket: String, at index: Int?, all tasks: [DayTask]
    ) -> Bool {
        let current = ordered(tasks, in: bucket)
        let siblings = current.filter { $0.uid != task.uid }
        let insertAt = min(max(index ?? siblings.count, 0), siblings.count)

        // 原地没动就别改数据,免得白白触发一次动画和重绘
        if task.bucketKey == bucket,
           let now = current.firstIndex(where: { $0.uid == task.uid }),
           now == insertAt {
            return false
        }

        var reordered = siblings
        reordered.insert(task, at: insertAt)

        task.bucketKey = bucket
        if let day = BucketKey.dayValue(of: bucket) { task.dayKey = day }
        for (i, t) in reordered.enumerated() { t.sortOrder = i }
        return true
    }
}

// MARK: - 老数据迁移

enum Migration {
    /// 老数据补齐:1.0 只有 dayKey;2.0 之前没有板。幂等,可反复调用。
    /// 返回兜底的默认板(没有任何板时会创建一个)。
    @discardableResult
    static func backfill(
        tasks: [DayTask], projects: [Project], context: ModelContext
    ) -> Project {
        var touched = false

        // 至少要有一个板,老任务才有地方归属
        let sorted = projects.sorted { $0.sortOrder < $1.sortOrder }
        let home: Project
        if let first = sorted.first {
            home = first
        } else {
            home = Project(name: Project.defaultName, emoji: Project.defaultEmoji, sortOrder: 0)
            context.insert(home)
            touched = true
        }
        if home.uid.isEmpty {
            home.uid = UUID().uuidString
            touched = true
        }

        for t in tasks {
            if t.bucketKey.isEmpty {
                t.bucketKey = "d:\(t.dayKey)"
                touched = true
            }
            if t.uid.isEmpty {
                t.uid = UUID().uuidString
                touched = true
            }
            if t.projectUID.isEmpty {
                t.projectUID = home.uid
                touched = true
            }
        }
        if touched { try? context.save() }
        return home
    }
}
