import AppKit
import SwiftData
import SwiftUI

/// 开发自检:把各界面离屏渲染成 PNG,便于不弹窗检查视觉效果
@MainActor
enum Snapshot {
    /// ImageRenderer 画不了 NSVisualEffectView(会显示 🚫 占位符),
    /// 离屏渲染时背景改用纯色渐变替身
    static var offscreen = false

    static func renderAll(to dir: String) {
        offscreen = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let schema = Schema([DayTask.self, Project.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            fputs("无法创建内存数据库\n", stderr)
            exit(1)
        }

        // 三个板,给板切换条当样本
        let demoProject = Project(name: "General", emoji: "📥", sortOrder: 0)
        let jobProject = Project(name: "Job hunt", emoji: "💼", sortOrder: 1)
        let gymProject = Project(name: "Fitness", emoji: "💪", sortOrder: 2)
        for p in [demoProject, jobProject, gymProject] { container.mainContext.insert(p) }

        let todayBucket = BucketKey.day(.now)
        let sampleTasks: [DayTask] = [
            DayTask(title: "Run 3 km", reward: "An iced americano", bucketKey: todayBucket, sortOrder: 0),
            DayTask(title: "Read chapter 4 of Sapiens", reward: "", bucketKey: todayBucket, sortOrder: 1),
            DayTask(title: "Call mom", reward: "One episode of my show", bucketKey: todayBucket, sortOrder: 2),
            DayTask(title: "Plan next week's study", reward: "Bubble tea", bucketKey: todayBucket, sortOrder: 3),
        ]
        for t in sampleTasks { container.mainContext.insert(t) }
        sampleTasks[0].completedAt = .now
        sampleTasks[2].completedAt = .now

        // 看板样本:本周目标 + 散落在几天里的卡片
        let isoCal = Calendar.iso8601
        let monday = Date.now.startOfWeek
        var boardTasks: [DayTask] = [
            DayTask(title: "Ship the week's report", reward: "Ramen night",
                    bucketKey: BucketKey.week(.now), sortOrder: 0),
            DayTask(title: "Finish Swift chapter 5", reward: "",
                    bucketKey: BucketKey.week(.now), sortOrder: 1),
            DayTask(title: "Read 3 books", reward: "New headphones",
                    bucketKey: BucketKey.month(.now), sortOrder: 0),
        ]
        for offset in 0..<5 {
            guard let d = isoCal.date(byAdding: .day, value: offset, to: monday) else { continue }
            boardTasks.append(DayTask(
                title: ["Gym", "Design review", "Grocery run", "Call grandma", "Deep work block"][offset],
                reward: offset == 1 ? "Bubble tea" : "",
                bucketKey: BucketKey.day(d), sortOrder: 0
            ))
        }
        for t in boardTasks { container.mainContext.insert(t) }
        boardTasks[3].completedAt = .now
        // 标几个加急,好检查视觉
        boardTasks[0].isUrgent = true
        boardTasks[4].isUrgent = true
        sampleTasks[1].isUrgent = true
        let allBoardTasks = sampleTasks + boardTasks
        // 分散到三个板上,好看出板切换条的计数
        for (i, t) in allBoardTasks.enumerated() {
            t.projectUID = [demoProject, jobProject, gymProject][i % 3].uid
        }

        // 造一份半年的热力图数据
        var doneByDay: [String: Int] = [:]
        let cal = Calendar.current
        for offset in 0..<180 where offset % 7 != 3 && offset % 11 != 5 {
            if let d = cal.date(byAdding: .day, value: -offset, to: .now) {
                doneByDay[d.dayKey] = (offset * 13 + 5) % 5 + (offset % 3 == 0 ? 1 : 0)
            }
        }
        let stats = Stats(
            totalDone: 236, totalTasks: 280,
            currentStreak: 12, longestStreak: 34, perfectDays: 41,
            doneByDay: doneByDay
        )

        save(view: MorningRitualView(onStart: { _ in }), container: container, name: "1_ritual", dir: dir)
        save(
            view: TodayView(tasks: sampleTasks, stats: stats, draggingUID: .constant(nil)),
            container: container, name: "2_today", dir: dir
        )
        // 新增:周看板 / 月看板
        save(
            view: BoardView(
                scope: .week,
                columns: BoardLayout.weekColumns(anchor: .now),
                tasks: allBoardTasks,
                activeProjectUID: demoProject.uid,
                projectBadges: [:],
                draggingUID: .constant(nil),
                resolve: { uid in allBoardTasks.first { $0.uid == uid } },
                debugSlot: DropSlot(column: BucketKey.day(.now), index: 1)
            ),
            container: container, name: "7_board_week", dir: dir, width: 1420, height: 780
        )
        save(
            view: BoardView(
                scope: .month,
                columns: BoardLayout.monthColumns(anchor: .now),
                tasks: allBoardTasks,
                activeProjectUID: demoProject.uid,
                projectBadges: [:],
                draggingUID: .constant(nil),
                resolve: { uid in allBoardTasks.first { $0.uid == uid } }
            ),
            container: container, name: "8_board_month", dir: dir, width: 1420, height: 780
        )
        save(view: ReviewView(stats: stats, onBack: {}), container: container, name: "3_review", dir: dir)
        save(
            view: HeatmapGrid(doneByDay: stats.doneByDay, debugHover: (col: 12, row: 3)).padding(60),
            container: container, name: "6_heatmap_hover", dir: dir
        )
        save(
            view: CelebrationOverlay(
                rewards: ["An iced americano", "One episode of my show"],
                startVisible: true, onClose: {}
            ),
            container: container, name: "4_celebration", dir: dir
        )
        // 按真实列表的分组规则排:未完成置顶,已完成沉底带小标题
        let pendingSample = sampleTasks.filter { !$0.isDone }
        let finishedSample = sampleTasks.filter(\.isDone)
        let rowsPreview = VStack(alignment: .leading, spacing: 10) {
            ForEach(pendingSample, id: \.persistentModelID) { t in
                TaskRow(task: t, onToggle: {}, onDelete: {}, onEdit: {})
            }
            FinishedHeader(count: finishedSample.count)
            ForEach(finishedSample, id: \.persistentModelID) { t in
                TaskRow(task: t, onToggle: {}, onDelete: {}, onEdit: {})
            }
        }
        .padding(.horizontal, 36)
        save(view: rowsPreview, container: container, name: "5_rows", dir: dir)

        // 板切换条:选中态 / 未选中态 / 计数 / All
        let bar = VStack(alignment: .leading, spacing: 18) {
            ProjectBar(
                projects: [demoProject, jobProject, gymProject],
                tasks: allBoardTasks,
                selected: .constant(nil),
                draggingUID: .constant(nil),
                resolve: { _ in nil }
            )
            ProjectBar(
                projects: [demoProject, jobProject, gymProject],
                tasks: allBoardTasks,
                selected: .constant(jobProject.uid),
                draggingUID: .constant(nil),
                resolve: { _ in nil }
            )
        }
        .padding(.horizontal, 36)
        save(view: bar, container: container, name: "9_project_bar", dir: dir, width: 900, height: 200)

        // 编辑面板(含加急开关的开/关两态)
        save(
            view: TaskEditorSheet(task: sampleTasks[1], onSave: { _, _, _ in }, onDelete: {}),
            container: container, name: "10_editor_urgent", dir: dir, width: 470, height: 400
        )
        save(
            view: TaskEditorSheet(task: sampleTasks[0], onSave: { _, _, _ in }, onDelete: {}),
            container: container, name: "11_editor_normal", dir: dir, width: 470, height: 400
        )

        print("✓ 已输出 11 张界面快照到 \(dir)")
        exit(0)
    }

    private static func save(
        view: some View, container: ModelContainer, name: String, dir: String,
        width: CGFloat = 880, height: CGFloat = 640
    ) {
        let content = ZStack {
            AppBackground()
            view
        }
        .frame(width: width, height: height)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .modelContainer(container)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("渲染失败:\(name)\n", stderr)
            return
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
    }
}
