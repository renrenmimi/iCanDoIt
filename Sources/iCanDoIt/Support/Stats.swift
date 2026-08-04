import Foundation

struct Stats {
    let totalDone: Int
    let totalTasks: Int
    let currentStreak: Int
    let longestStreak: Int
    let perfectDays: Int
    let doneByDay: [String: Int]

    static func compute(from tasks: [DayTask]) -> Stats {
        // 热力图与连击都以「实际完成那天」为准,
        // 这样周/月粒度的任务完成时也会正确点亮当天
        var doneByDay: [String: Int] = [:]
        var totalDone = 0
        for t in tasks {
            guard let at = t.completedAt else { continue }
            doneByDay[at.dayKey, default: 0] += 1
            totalDone += 1
        }

        // Perfect Day:某天的日任务全部完成(周/月目标不参与判定)
        var dayTotals: [String: Int] = [:]
        var dayDone: [String: Int] = [:]
        for t in tasks {
            guard let key = BucketKey.dayValue(of: t.bucketKey) else { continue }
            dayTotals[key, default: 0] += 1
            if t.isDone { dayDone[key, default: 0] += 1 }
        }
        let perfectDays = dayTotals.filter { key, total in
            total > 0 && dayDone[key] == total
        }.count

        // 有 ≥1 件完成即算「打卡日」;当前连击从今天(或昨天)往回数
        let activeDays = Set(doneByDay.keys)
        let cal = Calendar.current
        var current = 0
        var cursor = Date.now
        if !activeDays.contains(cursor.dayKey) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while activeDays.contains(cursor.dayKey) {
            current += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        let dates = activeDays.compactMap { df.date(from: $0) }.sorted()
        var longest = 0
        var run = 0
        var prev: Date?
        for d in dates {
            if let p = prev,
               let next = cal.date(byAdding: .day, value: 1, to: p),
               cal.isDate(next, inSameDayAs: d) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            prev = d
        }

        return Stats(
            totalDone: totalDone,
            totalTasks: tasks.count,
            currentStreak: current,
            longestStreak: longest,
            perfectDays: perfectDays,
            doneByDay: doneByDay
        )
    }
}
