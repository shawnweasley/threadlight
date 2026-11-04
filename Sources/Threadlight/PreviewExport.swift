import AppKit
import ThreadlightCore

/// Capture native controls with synthetic data, without reading monitored files
/// or requesting permission to capture other apps' screens.
enum PreviewExport {
    static func write(to destination: String) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let folder = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        let first = ChatID(.codex, "demo-a"), second = ChatID(.codex, "demo-b"), third = ChatID(.claude, "demo-c")
        var ledger = ActivityLedger()
        ledger.apply([Reading(id: first, title: "整理产品需求文档", phase: .working),
                      Reading(id: second, title: "检查项目构建", phase: .working),
                      Reading(id: third, title: "审查代码变更", phase: .working)], at: now)
        ledger.apply([Reading(id: second, title: "检查项目构建", phase: .finished, eventTime: now, unread: true)], at: now)
        let rows = ledger.visible.map(DisplayRow.init)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(status) }
        let bar = SignalArtwork.bar(rows, frame: 0, dark: false)
        status.length = bar.size.width + 2
        status.button?.image = bar
        status.button?.imageScaling = .scaleNone
        status.button?.appearance = NSAppearance(named: .aqua)
        let list = FloatingList(autosave: "Threadlight.Documentation")
        list.panel.appearance = NSAppearance(named: .aqua)
        list.update(rows, target: nil, action: nil)
        for row in rows { list.canvas.buttons[row.id]?.image = SignalArtwork.mark(row.phase, frame: 0, dark: false) }
        list.panel.orderFrontRegardless()
        defer { list.panel.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let button = status.button, let frame = list.panel.contentView?.superview else { throw CocoaError(.fileWriteUnknown) }
        try capture(button, to: folder.appendingPathComponent("menu-bar.png"), opaque: true)
        try capture(frame, to: folder.appendingPathComponent("task-list.png"))
    }

    private static func capture(_ view: NSView, to file: URL, opaque: Bool = false) throws {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: image)
        let bitmap: NSBitmapImageRep
        if opaque {
            guard let flattened = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.pixelsWide, pixelsHigh: image.pixelsHigh,
                                                  bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: image.pixelsWide * 3, bitsPerPixel: 24) else { throw CocoaError(.fileWriteUnknown) }
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? NSColor(deviceWhite: 0, alpha: 0)
                    let a = pixel.alphaComponent
                    let color = NSColor(deviceRed: pixel.redComponent * a + 0.96 * (1 - a),
                                        green: pixel.greenComponent * a + 0.96 * (1 - a),
                                        blue: pixel.blueComponent * a + 0.96 * (1 - a), alpha: 1)
                    flattened.setColor(color, atX: x, y: y)
                }
            }
            bitmap = flattened
        } else { bitmap = image }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: file, options: .atomic)
    }
}
