import AppKit
import SwiftUI
import ApplicationServices

/// Scroll Reverser v1: arah scroll terpisah untuk trackpad (scroll kontinu) dan mouse beroda,
/// plus step size tetap untuk mouse. Bekerja lewat event tap (butuh izin Accessibility).
final class ScrollReverser: ObservableObject {
    static let shared = ScrollReverser()

    @Published private(set) var running = false
    @Published private(set) var lastTrackpad: Date?
    @Published private(set) var lastMouse: Date?
    @Published private(set) var systemNatural = true
    @Published var message: String?

    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var settings: Settings { AetherCore.shared.settings }

    var trusted: Bool { AXIsProcessTrusted() }

    /// Arah bawaan macOS (System Settings → Mouse/Trackpad → Natural scrolling), berlaku untuk semua perangkat.
    func refreshSystem() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let v = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)
        systemNatural = (v as? NSNumber)?.boolValue ?? true
    }

    func apply(prompt: Bool) {
        refreshSystem()
        if settings.scrollEnabled { start(prompt: prompt) } else { stop() }
    }

    private func start(prompt: Bool) {
        guard tap == nil else { running = true; return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            running = false
            HotkeyCenter.shared.ensure(prompt: false)   // memasang pengecek izin otomatis
            message = tr("Izinkan PY-Sys di System Settings → Privacy & Security → Accessibility, lalu nyalakan lagi.",
                         "Allow PY-Sys in System Settings → Privacy & Security → Accessibility, then turn it on again.")
            return
        }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in
                                            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                                                if let t = ScrollReverser.shared.tap { CGEvent.tapEnable(tap: t, enable: true) }
                                                return Unmanaged.passUnretained(event)
                                            }
                                            guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
                                            ScrollReverser.shared.handle(event)
                                            return Unmanaged.passUnretained(event)
                                        }, userInfo: nil) else {
            message = tr("Scroll Reverser tidak bisa dijalankan.", "Scroll Reverser could not start.")
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        source = src
        running = true
        message = nil
    }

    func stop() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        running = false
    }

    // MARK: Pengolahan event

    fileprivate func handle(_ e: CGEvent) {
        let s = settings
        let continuous = e.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let now = Date()
        if continuous {
            if lastTrackpad.map({ now.timeIntervalSince($0) > 1 }) ?? true { lastTrackpad = now }
        } else {
            if lastMouse.map({ now.timeIntervalSince($0) > 1 }) ?? true { lastMouse = now }
        }

        // Step size tetap untuk roda mouse (tanpa akselerasi macOS)
        if !continuous && s.scrollStepEnabled {
            for axis in [(CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventFixedPtDeltaAxis1, CGEventField.scrollWheelEventPointDeltaAxis1),
                         (CGEventField.scrollWheelEventDeltaAxis2, CGEventField.scrollWheelEventFixedPtDeltaAxis2, CGEventField.scrollWheelEventPointDeltaAxis2)] {
                let d = e.getIntegerValueField(axis.0)
                guard d != 0 else { continue }
                let lines = Int64(s.scrollStep) * (d > 0 ? 1 : -1)
                e.setIntegerValueField(axis.0, value: lines)
                e.setDoubleValueField(axis.1, value: Double(lines))
                e.setIntegerValueField(axis.2, value: lines * 10)
            }
        }

        // Balik arah bila yang diinginkan berbeda dari pengaturan macOS
        let wantNatural = continuous ? s.scrollTrackpadNatural : s.scrollMouseNatural
        guard wantNatural != systemNatural else { return }
        var axes: [(CGEventField, CGEventField, CGEventField)] =
            [(.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)]
        if s.scrollHorizontal {
            axes.append((.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2))
        }
        for a in axes {
            e.setIntegerValueField(a.0, value: -e.getIntegerValueField(a.0))
            e.setDoubleValueField(a.1, value: -e.getDoubleValueField(a.1))
            e.setIntegerValueField(a.2, value: -e.getIntegerValueField(a.2))
        }
    }
}

// MARK: - Utility › Scroll

struct ScrollTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var sr = ScrollReverser.shared

    private func ago(_ d: Date?) -> String {
        guard let d else { return tr("Belum dipakai", "Not used yet") }
        if Date().timeIntervalSince(d) < 10 { return tr("Baru saja", "Just now") }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: AppLanguage.isEnglish ? "en" : "id")
        return f.localizedString(for: d, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(tr("Aktifkan Scroll Reverser", "Enable Scroll Reverser"), isOn: Binding(
                get: { settings.scrollEnabled },
                set: { v in
                    settings.scrollEnabled = v
                    sr.apply(prompt: v)
                }))
                .toggleStyle(.switch)
            HStack(spacing: 6) {
                Circle().fill(sr.running ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(sr.running ? tr("Berjalan", "Running") : tr("Tidak aktif", "Off"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            GroupBox(tr("Perangkat", "Devices")) {
                VStack(spacing: 12) {
                    ScrollDeviceRow(icon: "hand.point.up.left", title: "Trackpad",
                                    subtitle: tr("Juga Magic Mouse · scroll kontinu", "Also Magic Mouse · continuous"),
                                    natural: $settings.scrollTrackpadNatural, last: ago(sr.lastTrackpad)) {
                        Text(tr("Kontinu", "Continuous")).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    ScrollDeviceRow(icon: "computermouse", title: tr("Mouse beroda", "Wheel mouse"),
                                    subtitle: tr("Logitech dan mouse USB/Bluetooth lain", "Logitech and other USB/Bluetooth mice"),
                                    natural: $settings.scrollMouseNatural, last: ago(sr.lastMouse)) {
                        HStack(spacing: 4) {
                            Toggle("", isOn: $settings.scrollStepEnabled).labelsHidden()
                            Stepper(value: $settings.scrollStep, in: 1...10) {
                                Text(tr("\(settings.scrollStep) baris", "\(settings.scrollStep) lines")).monospacedDigit()
                            }
                            .disabled(!settings.scrollStepEnabled)
                        }
                        .font(.caption)
                    }
                }
            }

            Toggle(tr("Balik juga arah horizontal", "Also reverse horizontal scrolling"), isOn: $settings.scrollHorizontal)

            Text(tr("Pengaturan macOS saat ini: \(sr.systemNatural ? "Natural" : "Classic") untuk semua perangkat. PY-Sys hanya membalik perangkat yang pilihannya berbeda dari itu. Jika Logi Options+ juga mengatur arah scroll, set netral di sana agar tidak saling membalik.",
                    "Current macOS setting: \(sr.systemNatural ? "Natural" : "Classic") for every device. PY-Sys only flips devices set differently. If Logi Options+ also changes scroll direction, set it to neutral there so they don't cancel out."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let m = sr.message {
                Text(m).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button(tr("Buka pengaturan Accessibility", "Open Accessibility settings")) {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(u)
                    }
                }
                .controlSize(.small)
            }
        }
        .onAppear { sr.refreshSystem() }
    }
}

struct ScrollDeviceRow<Step: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var natural: Bool
    let last: String
    let step: Step

    init(icon: String, title: String, subtitle: String, natural: Binding<Bool>, last: String,
         @ViewBuilder step: () -> Step) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._natural = natural
        self.last = last
        self.step = step()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $natural) {
                    Text("Natural").tag(true)
                    Text("Classic").tag(false)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)
            }
            HStack {
                Text(tr("Step size", "Step size")).font(.caption).foregroundStyle(.secondary)
                step
                Spacer()
                Text(last).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.leading, 28)
        }
        .font(.callout)
    }
}
