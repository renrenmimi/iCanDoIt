import Foundation
import SwiftData

/// 开发自检:拖拽手势没法自动化,但落位逻辑必须能验证。
/// 用法:`iCanDoIt --selftest`,失败会以非零码退出。
@MainActor
enum SelfTest {
    static func run() {
        let schema = Schema([DayTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            fputs("无法创建内存数据库\n", stderr)
            exit(1)
        }
        let ctx = container.mainContext

        var failures: [String] = []
        var total = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            total += 1
            if ok {
                print("  ✓ \(name)")
            } else {
                print("  ✗ \(name) \(detail)")
                failures.append(name)
            }
        }

        let monday = BucketKey.day(Date.now.startOfWeek)
        let tuesday = BucketKey.day(
            Calendar.iso8601.date(byAdding: .day, value: 1, to: Date.now.startOfWeek) ?? .now
        )
        let weekBucket = BucketKey.week(.now)

        // 三张卡在周一列
        let a = DayTask(title: "A", reward: "", bucketKey: monday, sortOrder: 0)
        let b = DayTask(title: "B", reward: "", bucketKey: monday, sortOrder: 1)
        let c = DayTask(title: "C", reward: "", bucketKey: monday, sortOrder: 2)
        for t in [a, b, c] { ctx.insert(t) }
        var all = [a, b, c]

        print("拖拽落位自检:")

        // 1. 跨列拖动:C 从周一拖到周二
        BoardMove.apply(moving: c, to: tuesday, before: nil, all: all)
        check("跨列拖动改变所属列", c.bucketKey == tuesday, "得到 \(c.bucketKey)")
        check("跨列拖动同步旧 dayKey 字段",
              c.dayKey == BucketKey.dayValue(of: tuesday), "得到 \(c.dayKey)")
        check("原列只剩 A、B",
              BoardMove.ordered(all, in: monday).map(\.title) == ["A", "B"],
              "得到 \(BoardMove.ordered(all, in: monday).map(\.title))")

        // 2. 列内重排:把 B 插到 A 前面
        BoardMove.apply(moving: b, to: monday, before: a, all: all)
        check("列内重排后顺序为 B、A",
              BoardMove.ordered(all, in: monday).map(\.title) == ["B", "A"],
              "得到 \(BoardMove.ordered(all, in: monday).map(\.title))")

        // 3. 拖到自己身上应当无操作
        let before = b.sortOrder
        let noop = BoardMove.apply(moving: b, to: monday, before: b, all: all)
        check("拖到自己身上不产生变化", noop == false && b.sortOrder == before)

        // 4. 已完成的卡片沉底
        a.completedAt = .now
        check("完成的卡片排到列尾",
              BoardMove.ordered(all, in: monday).map(\.title) == ["B", "A"],
              "得到 \(BoardMove.ordered(all, in: monday).map(\.title))")

        // 5. 日任务拖进「本周目标」列
        BoardMove.apply(moving: b, to: weekBucket, before: nil, all: all)
        check("能拖进周目标列", b.bucketKey == weekBucket, "得到 \(b.bucketKey)")

        // 周/月目标不是"某一天"的任务,完成它不该凭空多出一个 Perfect Day
        let perfectBefore = Stats.compute(from: all).perfectDays
        b.completedAt = .now
        check("完成周目标不增加 Perfect Day",
              Stats.compute(from: all).perfectDays == perfectBefore,
              "\(perfectBefore) → \(Stats.compute(from: all).perfectDays)")

        // 6. 老数据迁移:只有 dayKey 的行要补出 bucketKey 和 uid
        let legacy = DayTask(title: "legacy", reward: "", bucketKey: monday, sortOrder: 0)
        legacy.bucketKey = ""
        legacy.uid = ""
        legacy.dayKey = "2026-01-15"
        ctx.insert(legacy)
        all.append(legacy)
        Migration.backfill(all, context: ctx)
        check("迁移补出 bucketKey", legacy.bucketKey == "d:2026-01-15", "得到 \(legacy.bucketKey)")
        check("迁移补出 uid", !legacy.uid.isEmpty)

        // 7. 热力图按「实际完成日」计数(此时 a 和 b 都是今天完成的)
        let stats = Stats.compute(from: all)
        check("完成计数取自 completedAt",
              stats.doneByDay[Date.now.dayKey] == 2,
              "得到 \(stats.doneByDay[Date.now.dayKey] ?? -1)")

        // 8. 列生成
        let weekCols = BoardLayout.weekColumns(anchor: .now)
        check("周视图 = 目标列 + 7 天", weekCols.count == 8, "得到 \(weekCols.count)")
        check("周视图有且仅有一列标记今天",
              weekCols.filter(\.isToday).count == 1)
        let monthCols = BoardLayout.monthColumns(anchor: .now)
        check("月视图列数在 5–7 之间", (5...7).contains(monthCols.count), "得到 \(monthCols.count)")
        check("月视图周列带日列汇总",
              monthCols.dropFirst().allSatisfy { $0.dayBuckets.count == 7 })

        if failures.isEmpty {
            print("\n✓ 全部 \(total) 项自检通过")
            exit(0)
        } else {
            print("\n✗ \(failures.count) 项失败:\(failures.joined(separator: ", "))")
            exit(1)
        }
    }
}
