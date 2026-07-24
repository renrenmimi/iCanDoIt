// 生成 App 图标:深紫渐变圆角方块 + 白色对勾 + 星光
// 用法: swift scripts/make_icon.swift <输出PNG路径>
import AppKit

func star(_ c: NSPoint, _ r: CGFloat, _ alpha: CGFloat) {
    let k: CGFloat = 0.18
    let p = NSBezierPath()
    p.move(to: NSPoint(x: c.x, y: c.y + r))
    p.curve(to: NSPoint(x: c.x + r, y: c.y),
            controlPoint1: NSPoint(x: c.x + r * k, y: c.y + r * k),
            controlPoint2: NSPoint(x: c.x + r * k, y: c.y + r * k))
    p.curve(to: NSPoint(x: c.x, y: c.y - r),
            controlPoint1: NSPoint(x: c.x + r * k, y: c.y - r * k),
            controlPoint2: NSPoint(x: c.x + r * k, y: c.y - r * k))
    p.curve(to: NSPoint(x: c.x - r, y: c.y),
            controlPoint1: NSPoint(x: c.x - r * k, y: c.y - r * k),
            controlPoint2: NSPoint(x: c.x - r * k, y: c.y - r * k))
    p.curve(to: NSPoint(x: c.x, y: c.y + r),
            controlPoint1: NSPoint(x: c.x - r * k, y: c.y + r * k),
            controlPoint2: NSPoint(x: c.x - r * k, y: c.y + r * k))
    p.close()
    NSColor.white.withAlphaComponent(alpha).setFill()
    p.fill()
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon_1024.png"
let S: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    fatalError("无法创建位图")
}

let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gctx

// 圆角方块(macOS 图标标准留白)
let margin: CGFloat = 92
let rect = NSRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
squircle.addClip()

// 深紫渐变底
let base = NSGradient(
    starting: NSColor(calibratedRed: 0.14, green: 0.09, blue: 0.32, alpha: 1),
    ending: NSColor(calibratedRed: 0.44, green: 0.22, blue: 0.78, alpha: 1)
)!
base.draw(in: rect, angle: 60)

// 右上角品红柔光
let glow = NSGradient(
    starting: NSColor(calibratedRed: 0.93, green: 0.28, blue: 0.60, alpha: 0.5),
    ending: NSColor(calibratedRed: 0.93, green: 0.28, blue: 0.60, alpha: 0.0)
)!
glow.draw(
    fromCenter: NSPoint(x: S * 0.72, y: S * 0.72), radius: 0,
    toCenter: NSPoint(x: S * 0.72, y: S * 0.72), radius: 430,
    options: []
)

// 对勾(先画一层柔光,再画主体)
let check = NSBezierPath()
check.move(to: NSPoint(x: 328, y: 512))
check.line(to: NSPoint(x: 462, y: 378))
check.line(to: NSPoint(x: 702, y: 636))
check.lineCapStyle = .round
check.lineJoinStyle = .round

let haloCheck = check.copy() as! NSBezierPath
haloCheck.lineWidth = 112
NSColor.white.withAlphaComponent(0.22).setStroke()
haloCheck.stroke()

check.lineWidth = 76
NSColor.white.setStroke()
check.stroke()

// 星光点缀
star(NSPoint(x: 742, y: 748), 58, 0.95)
star(NSPoint(x: 646, y: 816), 24, 0.7)

gctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 编码失败")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("✓ 图标已生成:\(outPath)")
