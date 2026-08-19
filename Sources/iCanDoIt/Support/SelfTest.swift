import Foundation
import SwiftData

/// 开发自检:拖拽手势没法自动化,但落位逻辑必须能验证。
/// 用法:`iCanDoIt --selftest`,失败会以非零码退出。
@MainActor
enum SelfTest {
    static func run() {
        let schema = Schema([DayTask.self, Project.self])
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

        // 1. 跨列拖动:C 从周一拖到周二(末尾)
        BoardMove.apply(moving: c, to: tuesday, at: nil, all: all)
        check("跨列拖动改变所属列", c.bucketKey == tuesday, "得到 \(c.bucketKey)")
        check("跨列拖动同步旧 dayKey 字段",
              c.dayKey == BucketKey.dayValue(of: tuesday), "得到 \(c.dayKey)")
        check("原列只剩 A、B",
              BoardMove.ordered(all, in: monday).map(\.title) == ["A", "B"],
              "得到 \(BoardMove.ordered(all, in: monday).map(\.title))")

        // 2. 列内重排:把 B 插到第 0 位
        BoardMove.apply(moving: b, to: monday, at: 0, all: all)
        check("列内重排后顺序为 B、A",
              BoardMove.ordered(all, in: monday).map(\.title) == ["B", "A"],
              "得到 \(BoardMove.ordered(all, in: monday).map(\.title))")

        // 3. 落回原位应当无操作(避免白白重绘)
        let noop = BoardMove.apply(moving: b, to: monday, at: 0, all: all)
        check("落回原位不产生变化", noop == false)

        // 4. 插到末尾:B 从 0 移到 1
        BoardMove.apply(moving: b, to: monday, at: 1, all: all)
        check("插到末尾后顺序为 A、B",
              BoardMove.ordered(all, in: monday).map(\.title) == ["A", "B"],
              "得到 \(BoardMove.ordered(all, in: monday).map(\.title))")

        // 5. 越界的落点要被夹住,不能崩
        BoardMove.apply(moving: b, to: monday, at: 999, all: all)
        check("越界落点被夹到合法范围",
              BoardMove.ordered(all, in: monday).count == 2)

        // 6. 已完成的卡片沉底(A 完成后应排到 B 后面)
        a.completedAt = .now
        check("完成的卡片排到列尾",
              BoardMove.ordered(all, in: monday).map(\.title) == ["B", "A"],
              "得到 \(BoardMove.ordered(all, in: monday).map(\.title))")

        // 7. 日任务拖进「本周目标」列
        BoardMove.apply(moving: b, to: weekBucket, at: nil, all: all)
        check("能拖进周目标列", b.bucketKey == weekBucket, "得到 \(b.bucketKey)")

        // 周/月目标不是"某一天"的任务,完成它不该凭空多出一个 Perfect Day
        let perfectBefore = Stats.compute(from: all).perfectDays
        b.completedAt = .now
        check("完成周目标不增加 Perfect Day",
              Stats.compute(from: all).perfectDays == perfectBefore,
              "\(perfectBefore) → \(Stats.compute(from: all).perfectDays)")

        // 8. 老数据迁移:只有 dayKey 的行要补出 bucketKey / uid / 板
        let legacy = DayTask(title: "legacy", reward: "", bucketKey: monday, sortOrder: 0)
        legacy.bucketKey = ""
        legacy.uid = ""
        legacy.projectUID = ""
        legacy.dayKey = "2026-01-15"
        ctx.insert(legacy)
        all.append(legacy)

        let home = Migration.backfill(tasks: all, projects: [], context: ctx)
        check("没有板时迁移会创建默认板", home.name == Project.defaultName, "得到 \(home.name)")
        check("迁移补出 bucketKey", legacy.bucketKey == "d:2026-01-15", "得到 \(legacy.bucketKey)")
        check("迁移补出 uid", !legacy.uid.isEmpty)
        check("迁移把老任务归到默认板", legacy.projectUID == home.uid)
        check("所有任务都有归属板", all.allSatisfy { !$0.projectUID.isEmpty })

        // 9. 迁移是幂等的:再跑一次不该新建板、也不该改动已有归属
        let uidBefore = legacy.projectUID
        let home2 = Migration.backfill(tasks: all, projects: [home], context: ctx)
        check("重复迁移复用已有板", home2.uid == home.uid && legacy.projectUID == uidBefore)

        // 10. 板筛选:换板后另一个板看不到这张卡
        let other = Project(name: "Job hunt", emoji: "💼", sortOrder: 1)
        ctx.insert(other)
        legacy.projectUID = other.uid
        check("按板筛选只留下该板的卡",
              all.filter { $0.projectUID == other.uid }.map(\.title) == ["legacy"],
              "得到 \(all.filter { $0.projectUID == other.uid }.map(\.title))")
        check("换板不影响任务所在的列", legacy.bucketKey == "d:2026-01-15")

        // 11. 加急标记:只是标记,不能打乱手动排的顺序
        let u1 = DayTask(title: "U1", reward: "", bucketKey: tuesday, sortOrder: 0)
        let u2 = DayTask(title: "U2", reward: "", bucketKey: tuesday, sortOrder: 1)
        for t in [u1, u2] { ctx.insert(t) }
        all += [u1, u2]
        check("新任务默认不加急", u1.isUrgent == false)
        u2.isUrgent = true
        check("加急不改变列内顺序",
              BoardMove.ordered(all, in: tuesday).map(\.title) == ["C", "U1", "U2"],
              "得到 \(BoardMove.ordered(all, in: tuesday).map(\.title))")
        // 加急的卡照样能拖
        BoardMove.apply(moving: u2, to: tuesday, at: 0, all: all)
        check("加急的卡可以拖到最前",
              BoardMove.ordered(all, in: tuesday).first?.title == "U2",
              "得到 \(BoardMove.ordered(all, in: tuesday).map(\.title))")
        check("拖动不会丢掉加急标记", u2.isUrgent)

        // 12. 编辑任务:改标题/奖励/加急不应影响所在列与顺序
        let bucketBefore = u2.bucketKey
        let orderBefore = u2.sortOrder
        u2.title = "U2 edited"
        u2.reward = "Coffee"
        u2.isUrgent = false
        check("编辑不改变所在列和顺序",
              u2.bucketKey == bucketBefore && u2.sortOrder == orderBefore)
        check("编辑后内容已更新",
              u2.title == "U2 edited" && u2.reward == "Coffee" && !u2.isUrgent)

        // 13. 热力图按「实际完成日」计数(此时 a 和 b 都是今天完成的)
        let stats = Stats.compute(from: all)
        check("完成计数取自 completedAt",
              stats.doneByDay[Date.now.dayKey] == 2,
              "得到 \(stats.doneByDay[Date.now.dayKey] ?? -1)")

        // 14. 拖拽看门狗:鼠标没按下时,应当把指示线收起来
        //     (自检运行时左键本来就是松开的,正好覆盖"拖拽被取消"这一路)
        func spinRunLoop(until done: () -> Bool, timeout: TimeInterval) {
            let deadline = Date().addingTimeInterval(timeout)
            while !done() && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }

        var cleared = false
        let watchdog = DragWatchdog()
        watchdog.begin { cleared = true }
        spinRunLoop(until: { cleared }, timeout: 1.5)
        check("看门狗在拖拽结束后收起指示线", cleared)

        var clearedAfterCancel = false
        let watchdog2 = DragWatchdog()
        watchdog2.begin { clearedAfterCancel = true }
        watchdog2.cancel()
        spinRunLoop(until: { clearedAfterCancel }, timeout: 0.5)
        check("取消看门狗后不再回调", clearedAfterCancel == false)

        // 15. 列生成
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
