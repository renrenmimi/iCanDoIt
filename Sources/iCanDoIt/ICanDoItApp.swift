import SwiftUI
import SwiftData

@main
enum Bootstrap {
    static func main() {
        // 隐藏的开发自检模式:--snapshot <目录> 把各界面渲染成 PNG 后退出
        if let idx = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.count > idx + 1 {
            let dir = CommandLine.arguments[idx + 1]
            MainActor.assumeIsolated { Snapshot.renderAll(to: dir) }
            return
        }
        // --selftest 跑拖拽落位/迁移/统计的逻辑断言
        if CommandLine.arguments.contains("--selftest") {
            MainActor.assumeIsolated { SelfTest.run() }
            return
        }
        ICanDoItApp.main()
    }
}

struct ICanDoItApp: App {
    /// --uitest:用内存数据库 + 样本数据跑,好在不碰真实数据的前提下测交互
    static let uiTest = CommandLine.arguments.contains("--uitest")

    var body: some Scene {
        Window("iCanDoIt", id: "main") {
            RootView()
                // 看板要同屏放 8 列,窗口给足宽度并允许自由缩放
                // 最小宽度按「8 列每列至少 ~140px」定,再窄看板就挤了
                .frame(minWidth: 1240, idealWidth: 1420, minHeight: 640, idealHeight: 800)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1420, height: 800)
        .modelContainer(for: [DayTask.self, Project.self], inMemory: Self.uiTest)
    }
}
