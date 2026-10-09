// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// 2026-09-11: Relaunch only after the old process exits, releasing its renderer resources.
enum ApplicationRelauncher {
    /// Pass paths as positional arguments; never interpolate a bundle path into shell source.
    static func schedule(bundleURL: URL, processID: Int32) throws {
        guard bundleURL.pathExtension == "app", FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/MacOS/Yinqi").path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 2026-09-11: Bound waiting to two minutes; never force-kill stalled audio shutdown.
        let script = #"i=0; while kill -0 "$1" 2>/dev/null; do i=$((i+1)); [ "$i" -lt 1200 ] || exit 1; sleep 0.1; done; exec /usr/bin/open -n "$2""#
        helper.arguments = ["-c", script, "yinqi-relaunch", String(processID), bundleURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
}
