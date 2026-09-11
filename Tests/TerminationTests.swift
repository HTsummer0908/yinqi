import AppKit

/// 2026-09-11: Exercise real capture-stop completion under AppKit's deferred termination loop, without requesting audio.
final class TerminationTestDelegate: NSObject, NSApplicationDelegate {
    private let capture = AudioCaptureService()
    private var completed = false

    /// Dispatch reproduces the restart prompt path; a timer represents a normal event-driven quit.
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("relaunch") {
            try! ApplicationRelauncher.schedule(bundleURL:Bundle.main.bundleURL,processID:ProcessInfo.processInfo.processIdentifier)
        }
        if CommandLine.arguments.contains("event") {
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in NSApp.terminate(nil) }
        } else {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Match production's asynchronous audio shutdown and AppKit reply ordering.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        capture.stop { [self] in
            precondition(Thread.isMainThread && !completed)
            completed = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Exit is successful only after stop completion was delivered exactly once on the main thread.
    func applicationWillTerminate(_ notification: Notification) {
        precondition(completed)
        // 2026-09-11: A disposable app records both exits to verify the complete restart chain.
        if Bundle.main.bundleURL.pathExtension == "app" {
            let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("termination-pids.txt")
            if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil) }
            let file = try! FileHandle(forWritingTo:url)
            try! file.seekToEnd()
            try! file.write(contentsOf:Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8))
            try! file.close()
        }
        print("PASS: capture stop completion and AppKit termination")
        fflush(stdout)
    }
}

@main struct TerminationTests {
    /// Retain the delegate throughout the application run loop.
    static func main() {
        let app = NSApplication.shared
        let delegate = TerminationTestDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
