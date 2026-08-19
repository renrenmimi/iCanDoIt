import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 拖拽被取消、或在任何放置目标之外松手时,系统不会回调 dropExited/performDrop,
/// 指示线就会一直留在屏幕上。这里靠"左键是否还按着"来判断拖拽有没有结束。
@MainActor
final class DragWatchdog {
    private var task: Task<Void, Never>?

    func begin(onEnd: @escaping () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                if Task.isCancelled { return }
                // 最低位代表左键
                if NSEvent.pressedMouseButtons & 0x1 == 0 {
                    onEnd()
                    return
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// 拖拽落点:哪一列、插到第几个
struct DropSlot: Equatable {
    let column: String
    let index: Int
}

/// 用 DropDelegate 而不是 .dropDestination,因为只有它能在拖拽过程中
/// 持续给出鼠标位置(dropUpdated),没有位置就画不出插入指示线。
struct SlotDropDelegate: DropDelegate {
    let column: String
    /// 把本地坐标换算成"插到第几个"
    let slotAt: (CGPoint) -> Int
    let onHover: (DropSlot?) -> Void
    /// 离开这一列。传列名是因为跨列时 entered(新列) 可能先于 exited(旧列),
    /// 不校验的话旧列的 exited 会把新列刚设好的落点清掉。
    let onExit: (String) -> Void
    let onPerform: (Int) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText, .utf8PlainText])
    }

    func dropEntered(info: DropInfo) {
        onHover(DropSlot(column: column, index: slotAt(info.location)))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHover(DropSlot(column: column, index: slotAt(info.location)))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onExit(column)
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = slotAt(info.location)
        onHover(nil)
        return onPerform(slot)
    }
}

/// 卡片之间的插入指示线
struct InsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Theme.mint)
            .frame(height: 3)
            .shadow(color: Theme.mint.opacity(0.8), radius: 5)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.mint.opacity(0.8), radius: 4)
            }
            .padding(.vertical, 1)
            .transition(.opacity)
    }
}
