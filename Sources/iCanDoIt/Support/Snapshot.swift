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

        let schema = Schema([DayTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            fputs("无法创建内存数据库\n", stderr)
            exit(1)
        }

        let todayKey = Date.now.dayKey
        let sampleTasks: [DayTask] = [
            DayTask(title: "Run 3 km", reward: "An iced americano", dayKey: todayKey, sortOrder: 0),
            DayTask(title: "Read chapter 4 of Sapiens", reward: "", dayKey: todayKey, sortOrder: 1),
            DayTask(title: "Call mom", reward: "One episode of my show", dayKey: todayKey, sortOrder: 2),
            DayTask(title: "Plan next week's study", reward: "Bubble tea", dayKey: todayKey, sortOrder: 3),
        ]
        for t in sampleTasks { container.mainContext.insert(t) }
        sampleTasks[0].completedAt = .now
        sampleTasks[2].completedAt = .now

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
            view: TodayView(tasks: sampleTasks, stats: stats, onShowReview: {}),
            container: container, name: "2_today", dir: dir
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
                TaskRow(task: t, onToggle: {}, onDelete: {})
            }
            FinishedHeader(count: finishedSample.count)
            ForEach(finishedSample, id: \.persistentModelID) { t in
                TaskRow(task: t, onToggle: {}, onDelete: {})
            }
        }
        .padding(.horizontal, 36)
        save(view: rowsPreview, container: container, name: "5_rows", dir: dir)

        print("✓ 已输出 6 张界面快照到 \(dir)")
        exit(0)
    }

    private static func save(view: some View, container: ModelContainer, name: String, dir: String) {
        let content = ZStack {
            AppBackground()
            view
        }
        .frame(width: 880, height: 640)
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
