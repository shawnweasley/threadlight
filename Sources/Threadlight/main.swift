import AppKit
import ThreadlightCore

if CommandLine.arguments.contains("--check-assets") {
    guard SignalArtwork.hasPackagedArtwork else { fputs("Packaged artwork is missing or unreadable.\n", stderr); exit(1) }
    print("Packaged artwork is available.")
} else if let index = CommandLine.arguments.firstIndex(of: "--export-screenshots"), CommandLine.arguments.count > index + 1 {
    do { try PreviewExport.write(to: CommandLine.arguments[index + 1]) }
    catch { fputs("Preview export failed.\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--diagnose") {
    let monitor = LocalMonitor(persistentCache: false)
    for label in ["cold", "warm"] {
        let report = monitor.poll()
        let active = report.readings.filter { $0.phase == .working }
        print("\(label): milliseconds=\(report.milliseconds) log_bytes=\(report.logBytes) metadata_bytes=\(report.metadataBytes) cached_logs=\(report.cacheHits) codex_working=\(active.filter { $0.id.client == .codex }.count) claude_working=\(active.filter { $0.id.client == .claude }.count)")
        for message in report.notices { print("notice: \(message)") }
    }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AgentApplication()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}
