// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// 2026-09-11: Route user-visible labels and messages through the process-selected localization resources.
import Foundation
import AppKit
import CoreAudio
import Realtime

/// Stage A metadata only; no raw audio is logged or persisted.
struct CaptureStatus {
    var message: String
    var isError: Bool = false
    var sampleRate: Double = 0
    var channels: UInt32 = 0
    var callbacks: UInt64 = 0
    var dropped: UInt64 = 0
    var rmsDB: Double = -160
    var peak: Float = 0
}

/// Owns all HAL resources on a serial control queue; the C callback only owns PCM production.
final class AudioCaptureService {
    private let control = DispatchQueue(label: "local.yinqi.capture")
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var pcm: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var scratch = [Float](repeating: 0, count: 8192)
    private var format = AudioStreamBasicDescription()
    private var analyzer: SpectrumAnalyzer?
    private var settings = Settings()
    let frames = SpectrumFrameStore()
    private var ticks = 0
    private var lastInputTime = 0.0
    private var wanted = false
    private var recoveryPending = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    /// Serialize immutable analysis settings with PCM consumption.
    func configure(_ value: Settings) { control.async { self.settings = value.validated() } }
    var onStatus: ((CaptureStatus) -> Void)?

    /// Start is serialized and idempotent; failure releases partially acquired resources.
    func start() {
        control.async { [self] in wanted = true; beginOnQueue() }
    }

    /// 2026-09-11: Recovery runs inline without changing user intent, preventing hidden capture revival.
    private func beginOnQueue() {
            guard device == 0, tap == 0, io == nil else { return }
            publish(CaptureStatus(message: L("等待系统音频授权 / 建立采集；请处理系统弹窗…")))
            do {
                var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
                var process: AudioObjectID = 0
                var address = property(kAudioHardwarePropertyTranslatePIDToProcessObject)
                var size = UInt32(MemoryLayout<AudioObjectID>.size)
                try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                    UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process), L("解析自身进程"))
                guard process != 0 else { throw CaptureError(message: L("系统未返回自身音频进程 ID")) }
                let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [process])
                description.name = "Yinqi system audio"
                description.isPrivate = true
                description.muteBehavior = .unmuted
                try check(AudioHardwareCreateProcessTap(description, &tap), L("创建系统音频 tap"))
                address = property(kAudioTapPropertyFormat)
                size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), L("读取 tap 格式"))
                guard format.mFormatID == kAudioFormatLinearPCM,
                      format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                      format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                      format.mBitsPerChannel == 32, format.mChannelsPerFrame == 2,
                      format.mSampleRate.isFinite, format.mSampleRate > 0 else {
                    throw CaptureError(message: L("暂不支持 tap 格式：需 Float32 双声道，实际 %@", String(describing: format)))
                }
                let config: [String: Any] = [
                    kAudioAggregateDeviceNameKey: "Yinqi Private Capture",
                    kAudioAggregateDeviceUIDKey: UUID().uuidString,
                    kAudioAggregateDeviceIsPrivateKey: true,
                    // 2026-09-11: SDK documents true as a blocking wait in AudioDeviceStart.
                    // Disable that wait so a quiet system cannot block stop/retry on the control queue.
                    kAudioAggregateDeviceTapAutoStartKey: false,
                    kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                        kAudioSubTapDriftCompensationKey: true]]
                ]
                try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &device), L("创建私有聚合设备"))
                guard let buffer = sb_create(4096) else { throw CaptureError(message: L("PCM 缓冲分配失败")) }
                pcm = buffer
                try check(AudioDeviceCreateIOProcID(device, sb_io, UnsafeMutableRawPointer(buffer), &io), L("创建 IO 回调"))
                try check(AudioDeviceStart(device, io), L("启动音频 IO；请检查系统音频录制授权"))
                analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate)
                ticks = 0
                lastInputTime = ProcessInfo.processInfo.systemUptime
                listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
                listen(tap, kAudioTapPropertyFormat)
                listen(device, kAudioDevicePropertyDeviceIsAlive)
                publish(CaptureStatus(message: L("IO 已启动，等待系统播放音频"), sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame))
                let source = DispatchSource.makeTimerSource(queue: control)
                source.schedule(deadline: .now(), repeating: .milliseconds(20))
                source.setEventHandler { [weak self] in self?.consume() }
                timer = source
                source.resume()
            } catch {
                guard releaseResources() else { return }
                publish(CaptureStatus(message: L("采集失败：%@。可在系统设置中检查屏幕与系统音频录制权限，再手动重试。", String(describing: error.localizedDescription)), isError: true))
            }
    }

    /// 2026-09-11: Stop HAL before releasing callback context; deliver completion in AppKit's nested quit loop too.
    func stop(completion: (() -> Void)? = nil) {
        control.async { [self] in
            wanted = false
            let released = releaseResources()
            frames.publish(SpectrumFrame(bands: [], rmsDB: -160, timestamp: 0, sequence: 0, opacity: 0))
            if released { publish(CaptureStatus(message: L("已停止采集"))) }
            // 2026-09-11: Main dispatch cannot reenter when terminate() was called inside a main-queue task.
            // Run-loop delivery also works while AppKit waits in modal mode for terminateLater's reply.
            if let completion {
                RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking], block: completion)
            }
        }
    }

    /// Consume queued frames on the worker, calculate channel power without phase cancellation.
    private func consume() {
        guard let pcm else { return }
        let count = scratch.withUnsafeMutableBufferPointer { sb_read_latest(pcm, $0.baseAddress!, UInt32(min(4096, max(1024, Int(format.mSampleRate * 0.03))))) }
        ticks += 1
        let time = ProcessInfo.processInfo.systemUptime
        if count == 0 {
            // 2026-09-11: A single empty poll is not silence. After 250 ms without real input,
            // advance the silence gate by wall time without injecting synthetic PCM into FFT history.
            if time-lastInputTime >= 0.25, let frame = analyzer?.idle(settings: settings, timestamp: time) { frames.publish(frame) }
            if ticks % 50 == 0 { publish(CaptureStatus(message: L("等待系统播放音频；如测试声无响应请检查授权并重试"), sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame, callbacks: sb_callbacks(pcm), dropped: sb_dropped(pcm))) }
            return
        }
        lastInputTime = time
        if let frame = analyzer?.ingest(scratch, count: Int(count), settings: settings, timestamp: time) { frames.publish(frame) }
        var power = 0.0
        var peak: Float = 0
        for i in 0..<(Int(count) * 2) {
            let x = scratch[i]
            if x.isFinite { power += Double(x) * Double(x); peak = max(peak, abs(x)) }
        }
        let db = 10 * log10(max(1e-16, power / Double(count * 2)))
        // Diagnostics are sampled at 5 Hz, never logged from the realtime callback.
        if ticks % 10 == 0 {
            publish(CaptureStatus(message: db > -65 ? L("收到非零系统音频样本") : L("IO 运行中，当前无声音（不能据此判断授权）"),
                sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame,
                callbacks: sb_callbacks(pcm), dropped: sb_dropped(pcm), rmsDB: db, peak: peak))
        }
    }

    /// Reverse acquisition order; no default output device is ever modified.
    @discardableResult private func releaseResources() -> Bool {
        timer?.cancel(); timer = nil
        for (object, var address, block) in listeners { AudioObjectRemovePropertyListenerBlock(object, &address, control, block) }
        listeners.removeAll()
        analyzer = nil
        if let io {
            let stopped = AudioDeviceStop(device, io)
            let destroyed = AudioDeviceDestroyIOProcID(device, io)
            // 2026-09-11: Retain context on unregister failure; freeing it could race a live HAL callback.
            guard destroyed == noErr else {
                publish(CaptureStatus(message: L("停止资源失败：stop=%@, unregister=%@；缓冲仍保留，请重试或退出", String(describing: stopped), String(describing: destroyed)), isError: true))
                return false
            }
            self.io = nil
        }
        if let pcm { sb_destroy(pcm); self.pcm = nil }
        if device != 0 {
            let status = AudioHardwareDestroyAggregateDevice(device)
            guard status == noErr else { publish(CaptureStatus(message: L("释放聚合设备失败 OSStatus=%@，请重试", String(describing: status)), isError: true)); return false }
            device = 0
        }
        if tap != 0 {
            let status = AudioHardwareDestroyProcessTap(tap)
            guard status == noErr else { publish(CaptureStatus(message: L("释放 tap 失败 OSStatus=%@，请重试", String(describing: status)), isError: true)); return false }
            tap = 0
        }
        return true
    }

    /// Property callbacks run on the same serial path and coalesce a device/format rebuild.
    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
        var address = property(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.wanted, !self.recoveryPending else { return }
            self.recoveryPending = true
            self.publish(CaptureStatus(message: L("设备恢复中…")))
            self.control.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.recoveryPending = false
                guard self.wanted else { return }
                guard self.releaseResources() else { return }
                // A single automatic attempt is bounded; failure exposes a manual retry instead of a loop.
                self.beginOnQueue()
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, control, block) == noErr { listeners.append((object,address,block)) }
        else { publish(CaptureStatus(message: L("设备监听注册失败；设备变化后请手动重试"), isError: true)) }
    }

    /// Marshal immutable diagnostics to the UI thread.
    private func publish(_ status: CaptureStatus) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }

    /// All properties used here address the global main element.
    private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Preserve OSStatus for actionable diagnostics instead of guessing a permission outcome.
    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw CaptureError(message: "\(operation) OSStatus=\(status)") }
    }
}

/// Carries the original failing HAL operation to the menu and diagnostics window.
private struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
