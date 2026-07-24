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
        ICanDoItApp.main()
    }
}

struct ICanDoItApp: App {
    var body: some Scene {
        Window("iCanDoIt", id: "main") {
            RootView()
                .frame(width: 880, height: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .modelContainer(for: DayTask.self)
    }
}
