import AppKit
import SwiftUI
import ApplicationServices
import UniformTypeIdentifiers

// MARK: - Klik Kanan+ (Utility)
//
// Menu tambahan untuk Finder, dipanggil dengan:
//   • tombol modifier + klik kanan (default Option),
//   • klik tombol tengah mouse,
//   • Finder › klik kanan › Quick Actions › "PY-Sys: Klik Kanan+" (NSServices).
// PY-Sys tidak memasang plugin ke Finder: menunya buatan PY-Sys sendiri, muncul di posisi kursor.

enum ClickItem: String, CaseIterable, Identifiable {
    case newFile, newFolder, copyPath, copyName, copyTerminalPath, openTerminal
    case moveTo, copyTo, commonFolders, addCommon, shortcutDesktop, airdrop
    case folderFromName, folderColor, toggleHidden, permanentDelete
    var id: String { rawValue }

    var title: String {
        switch self {
        case .newFile: return tr("File baru", "New File")
        case .newFolder: return tr("Folder baru", "New Folder")
        case .copyPath: return tr("Salin path", "Copy Path")
        case .copyName: return tr("Salin nama file (folder)", "Copy File (Folder) Name")
        case .copyTerminalPath: return tr("Salin path untuk Terminal", "Copy Path for Terminal")
        case .openTerminal: return tr("Buka di Terminal", "Open in Terminal")
        case .moveTo: return tr("Pindahkan ke…", "Move to…")
        case .copyTo: return tr("Salin ke…", "Copy to…")
        case .commonFolders: return tr("Folder favorit", "Common Folders")
        case .addCommon: return tr("Tambah ke folder favorit", "Add to Common Folders")
        case .shortcutDesktop: return tr("Kirim shortcut ke Desktop", "Send Shortcut to Desktop")
        case .airdrop: return "AirDrop"
        case .folderFromName: return tr("Buat folder dari nama file", "Create Folder Using Filename")
        case .folderColor: return tr("Warna ikon folder", "Folder Icon Color")
        case .toggleHidden: return tr("Tampilkan/sembunyikan file tersembunyi", "Show/Hide Hidden Files")
        case .permanentDelete: return tr("Hapus permanen", "Permanent Delete")
        }
    }

    var symbol: String {
        switch self {
        case .newFile: return "doc.badge.plus"
        case .newFolder: return "folder.badge.plus"
        case .copyPath: return "link"
        case .copyName: return "textformat"
        case .copyTerminalPath: return "chevron.left.forwardslash.chevron.right"
        case .openTerminal: return "terminal"
        case .moveTo: return "arrow.right.doc.on.clipboard"
        case .copyTo: return "doc.on.doc"
        case .commonFolders: return "heart"
        case .addCommon: return "heart.circle"
        case .shortcutDesktop: return "arrow.up.forward.app"
        case .airdrop: return "dot.radiowaves.left.and.right"
        case .folderFromName: return "folder"
        case .folderColor: return "paintpalette"
        case .toggleHidden: return "eye.slash"
        case .permanentDelete: return "trash.slash"
        }
    }
}

enum NewFileKind: String, CaseIterable, Identifiable {
    case txt, md, rtf, html, docx, xlsx, pptx
    var id: String { rawValue }
    var title: String {
        switch self {
        case .txt: return "TXT"
        case .md: return "Markdown"
        case .rtf: return "RTF"
        case .html: return "HTML"
        case .docx: return "Word"
        case .xlsx: return "Excel"
        case .pptx: return "PowerPoint"
        }
    }
    var baseName: String { tr("Dokumen baru", "New Document") }
    var symbol: String {
        switch self {
        case .txt, .md, .rtf: return "doc.text"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .docx: return "doc.richtext"
        case .xlsx: return "tablecells"
        case .pptx: return "rectangle.on.rectangle"
        }
    }
    /// Isi file teks; nil berarti disalin dari template Office di Resources/Templates.
    var textContent: String? {
        switch self {
        case .txt: return ""
        case .md: return "# \n"
        case .rtf: return "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2\n{\\fonttbl\\f0\\fswiss Helvetica;}\n\\f0\\fs24 \n}\n"
        case .html: return "<!doctype html>\n<html lang=\"id\">\n<head><meta charset=\"utf-8\"><title></title></head>\n<body>\n\n</body>\n</html>\n"
        case .docx, .xlsx, .pptx: return nil
        }
    }
}

enum Trigger: String, CaseIterable, Identifiable {
    case option, shift, command
    var id: String { rawValue }
    var title: String {
        switch self {
        case .option: return "⌥ Option"
        case .shift: return "⇧ Shift"
        case .command: return "⌘ Command"
        }
    }
    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .shift: return .maskShift
        case .command: return .maskCommand
        }
    }
}

// MARK: - Pengaturan Klik Kanan+

final class ClickSettings: ObservableObject {
    static let shared = ClickSettings()
    private enum K {
        static let en = "ck.enabled", mod = "ck.modifierOn", trig = "ck.trigger", mid = "ck.middle"
        static let hot = "ck.hotkey", items = "ck.items", kinds = "ck.kinds", open = "ck.openNew", folders = "ck.folders"
    }
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: K.en) } }
    @Published var modifierOn: Bool { didSet { d.set(modifierOn, forKey: K.mod) } }
    @Published var trigger: String { didSet { d.set(trigger, forKey: K.trig) } }
    @Published var middleClick: Bool { didSet { d.set(middleClick, forKey: K.mid) } }
    @Published var hotkeyOn: Bool { didSet { d.set(hotkeyOn, forKey: K.hot) } }
    @Published var items: [String] { didSet { d.set(items, forKey: K.items) } }
    @Published var kinds: [String] { didSet { d.set(kinds, forKey: K.kinds) } }
    @Published var openNew: Bool { didSet { d.set(openNew, forKey: K.open) } }
    @Published var folders: [String] { didSet { d.set(folders, forKey: K.folders) } }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        d.register(defaults: [K.en: false, K.mod: true, K.trig: Trigger.option.rawValue, K.mid: true, K.hot: true,
                              K.items: ClickItem.allCases.map(\.rawValue),
                              K.kinds: NewFileKind.allCases.map(\.rawValue),
                              K.open: true,
                              K.folders: ["\(home)/Desktop", "\(home)/Documents", "\(home)/Downloads"]])
        enabled = d.bool(forKey: K.en)
        modifierOn = d.bool(forKey: K.mod)
        trigger = d.string(forKey: K.trig) ?? Trigger.option.rawValue
        middleClick = d.bool(forKey: K.mid)
        hotkeyOn = d.bool(forKey: K.hot)
        items = d.stringArray(forKey: K.items) ?? []
        kinds = d.stringArray(forKey: K.kinds) ?? []
        openNew = d.bool(forKey: K.open)
        folders = d.stringArray(forKey: K.folders) ?? []
    }

    var triggerValue: Trigger { Trigger(rawValue: trigger) ?? .option }
    func has(_ i: ClickItem) -> Bool { items.contains(i.rawValue) }
    func has(_ k: NewFileKind) -> Bool { kinds.contains(k.rawValue) }

    func binding(_ i: ClickItem) -> Binding<Bool> {
        Binding(get: { self.items.contains(i.rawValue) },
                set: { on in
                    if on { if !self.items.contains(i.rawValue) { self.items.append(i.rawValue) } }
                    else { self.items.removeAll { $0 == i.rawValue } }
                })
    }
    func binding(_ k: NewFileKind) -> Binding<Bool> {
        Binding(get: { self.kinds.contains(k.rawValue) },
                set: { on in
                    if on { if !self.kinds.contains(k.rawValue) { self.kinds.append(k.rawValue) } }
                    else { self.kinds.removeAll { $0 == k.rawValue } }
                })
    }
}

// MARK: - Penangkap klik (event tap)

final class ClickMenu: NSObject, ObservableObject {
    static let shared = ClickMenu()

    @Published private(set) var running = false
    @Published var message: String?
    @Published var lastResult: String?
    @Published var lastEvent: String?

    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var swallowRightUp = false
    fileprivate var swallowOtherUp = false
    private let cs = ClickSettings.shared

    // Target menu yang sedang terbuka
    private var targets: [URL] = []
    private var directory: URL?

    func apply(prompt: Bool) {
        if cs.enabled { start(prompt: prompt) } else { stop() }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
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
        let types: [CGEventType] = [.rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in
                                            ClickMenu.shared.filter(type, event)
                                        }, userInfo: nil) else {
            message = tr("Klik Kanan+ tidak bisa dijalankan.", "Right-Click+ could not start.")
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

    /// Dipanggil untuk setiap klik kanan/tengah. Kembalikan nil = klik ditelan (tidak diteruskan ke Finder).
    fileprivate func filter(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(e)
        case .rightMouseUp where swallowRightUp:
            swallowRightUp = false
            return nil
        case .otherMouseUp where swallowOtherUp:
            swallowOtherUp = false
            return nil
        case .rightMouseDown:
            let flags = e.flags
            let want = cs.triggerValue
            let held = flags.contains(want.flag)
            guard cs.modifierOn, !flags.contains(.maskControl) else { break }
            let who = Self.ownerUnder(e.location)
            note(tr("Klik kanan · \(want.title) \(held ? "ditahan" : "tidak ditahan") · di bawah kursor: \(who.name)",
                    "Right-click · \(want.title) \(held ? "held" : "not held") · under pointer: \(who.name)"))
            guard held, who.finder else { break }
            swallowRightUp = true
            trigger(at: e.location)
            return nil
        case .otherMouseDown:
            let btn = e.getIntegerValueField(.mouseEventButtonNumber)
            guard cs.middleClick, btn == 2 else { break }
            let who = Self.ownerUnder(e.location)
            note(tr("Klik tengah · di bawah kursor: \(who.name)", "Middle click · under pointer: \(who.name)"))
            guard who.finder else { break }
            swallowOtherUp = true
            trigger(at: e.location)
            return nil
        case .keyDown:
            // ⌃⌥Space: menu untuk file yang sedang dipilih di Finder, di posisi kursor (cocok untuk trackpad)
            let f = e.flags
            guard cs.hotkeyOn, e.getIntegerValueField(.keyboardEventKeycode) == 49,
                  f.contains(.maskControl), f.contains(.maskAlternate), !f.contains(.maskCommand), !f.contains(.maskShift)
            else { break }
            note(tr("Shortcut ⌃⌥Space", "Shortcut ⌃⌥Space"))
            DispatchQueue.main.async {
                let (sel, dir) = Self.finderSelection()
                self.show(targets: sel, directory: dir)
            }
            return nil
        default: break
        }
        return Unmanaged.passUnretained(e)
    }

    /// Pemilik jendela di bawah kursor. Lapisan overlay (menu bar, Dock, DisplayLink, widget) dilewati;
    /// yang dihitung hanya jendela aplikasi biasa (layer 0) dan ikon Desktop (layer negatif).
    private static func ownerUnder(_ p: CGPoint) -> (finder: Bool, name: String) {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return (false, "?")
        }
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard let bd = w[kCGWindowBounds as String], let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let r = CGRect(dictionaryRepresentation: bd as! CFDictionary), r.contains(p) else { continue }
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            if layer > 0 { continue }
            if let a = w[kCGWindowAlpha as String] as? Double, a < 0.05 { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? (w[kCGWindowOwnerName as String] as? String ?? "?")
            if app?.bundleIdentifier == "com.apple.finder" { return (true, "Finder") }
            if layer == 0 { return (false, name) }
            // layer negatif milik app lain (mis. widget desktop): lanjut cari ikon Desktop di bawahnya
        }
        // Tidak ada jendela biasa di bawah kursor: anggap Desktop bila Finder aktif
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        return (front, front ? "Finder" : "Desktop")
    }

    private func note(_ s: String) {
        DispatchQueue.main.async { self.lastEvent = s }
    }

    /// Item di bawah kursor sudah terpilih? (lewat Accessibility) Bila ya, pilihan banyak file dipertahankan.
    private static func itemUnderIsSelected(_ p: CGPoint) -> Bool {
        let sys = AXUIElementCreateSystemWide()
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(p.y), &el) == .success, var cur = el else { return false }
        for _ in 0..<5 {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(cur, kAXSelectedAttribute as CFString, &v) == .success,
               let b = v as? Bool, b { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &parent) == .success,
                  let pr = parent, CFGetTypeID(pr) == AXUIElementGetTypeID() else { break }
            cur = pr as! AXUIElement
        }
        return false
    }

    private func trigger(at p: CGPoint) {
        let keep = Self.itemUnderIsSelected(p)
        if !keep {
            // Klik kiri tunggal tanpa modifier agar item di bawah kursor ikut terpilih, seperti klik kanan biasa.
            for t in [CGEventType.leftMouseDown, .leftMouseUp] {
                let ev = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)
                ev?.flags = []
                ev?.post(tap: .cghidEventTap)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (keep ? 0.02 : 0.18)) {
            let (sel, dir) = Self.finderSelection()
            self.show(targets: sel, directory: dir)
        }
    }

    /// Pilihan Finder saat ini + folder tempatnya (atau folder jendela depan / Desktop).
    static func finderSelection() -> ([URL], URL?) {
        let src = """
        tell application "Finder"
            set out to ""
            try
                set sel to selection as alias list
                repeat with i in sel
                    set out to out & POSIX path of i & linefeed
                end repeat
            end try
            set d to ""
            try
                set d to POSIX path of (insertion location as alias)
            end try
            return d & linefeed & "--" & linefeed & out
        end tell
        """
        var err: NSDictionary?
        guard let r = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue else {
            ClickMenu.shared.message = tr("Izinkan PY-Sys mengontrol Finder di System Settings → Privacy & Security → Automation.",
                                          "Allow PY-Sys to control Finder in System Settings → Privacy & Security → Automation.")
            return ([], nil)
        }
        let parts = r.components(separatedBy: "\n--\n")
        let dirStr = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urls = (parts.count > 1 ? parts[1] : "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        var dir: URL? = dirStr.isEmpty ? nil : URL(fileURLWithPath: dirStr, isDirectory: true)
        if let f = urls.first { dir = f.deletingLastPathComponent() }
        return (urls, dir)
    }

    // MARK: Menu

    func show(targets: [URL], directory: URL?) {
        self.targets = targets
        self.directory = directory ?? targets.first?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let menu = buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func item(_ title: String, _ symbol: String?, _ sel: Selector, _ obj: Any? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        mi.target = self
        mi.representedObject = obj
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return mi
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu(title: "Klik Kanan+")
        m.autoenablesItems = false
        let header = NSMenuItem(title: targets.isEmpty ? (directory?.lastPathComponent ?? "PY-Sys")
                                : (targets.count == 1 ? targets[0].lastPathComponent : tr("\(targets.count) item", "\(targets.count) items")),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)
        m.addItem(.separator())

        let has = { (i: ClickItem) in self.cs.has(i) }
        let sel = !targets.isEmpty
        let folderSel = targets.filter { $0.hasDirectoryPath || Self.isDir($0) }

        // Buat
        if has(.newFile) {
            let sub = NSMenu()
            for k in NewFileKind.allCases where cs.has(k) {
                sub.addItem(item(k.title, k.symbol, #selector(doNewFile(_:)), k.rawValue))
            }
            if !sub.items.isEmpty {
                let mi = item(ClickItem.newFile.title, ClickItem.newFile.symbol, #selector(noop))
                mi.submenu = sub
                m.addItem(mi)
            }
        }
        if has(.newFolder) { m.addItem(item(ClickItem.newFolder.title, ClickItem.newFolder.symbol, #selector(doNewFolder))) }
        if has(.openTerminal) { m.addItem(item(ClickItem.openTerminal.title, ClickItem.openTerminal.symbol, #selector(doTerminal))) }
        m.addItem(.separator())

        // Salin informasi
        if has(.copyPath) { m.addItem(item(ClickItem.copyPath.title, ClickItem.copyPath.symbol, #selector(doCopyPath))) }
        if sel && has(.copyName) { m.addItem(item(ClickItem.copyName.title, ClickItem.copyName.symbol, #selector(doCopyName))) }
        if has(.copyTerminalPath) { m.addItem(item(ClickItem.copyTerminalPath.title, ClickItem.copyTerminalPath.symbol, #selector(doCopyTerminal))) }

        // Pindah / salin / favorit
        if sel && (has(.moveTo) || has(.copyTo)) { m.addItem(.separator()) }
        if sel && has(.moveTo) { m.addItem(folderMenu(ClickItem.moveTo, #selector(doMove(_:)))) }
        if sel && has(.copyTo) { m.addItem(folderMenu(ClickItem.copyTo, #selector(doCopy(_:)))) }
        if has(.commonFolders) && !cs.folders.isEmpty {
            let sub = NSMenu()
            for f in cs.folders { sub.addItem(item((f as NSString).lastPathComponent, "folder", #selector(doOpenFolder(_:)), f)) }
            let mi = item(ClickItem.commonFolders.title, ClickItem.commonFolders.symbol, #selector(noop))
            mi.submenu = sub
            m.addItem(mi)
        }
        if !folderSel.isEmpty && has(.addCommon) { m.addItem(item(ClickItem.addCommon.title, ClickItem.addCommon.symbol, #selector(doAddCommon))) }

        // Lainnya
        if sel {
            m.addItem(.separator())
            if has(.shortcutDesktop) { m.addItem(item(ClickItem.shortcutDesktop.title, ClickItem.shortcutDesktop.symbol, #selector(doShortcut))) }
            if has(.airdrop) { m.addItem(item(ClickItem.airdrop.title, ClickItem.airdrop.symbol, #selector(doAirDrop))) }
            if has(.folderFromName) && targets.contains(where: { !Self.isDir($0) }) {
                m.addItem(item(ClickItem.folderFromName.title, ClickItem.folderFromName.symbol, #selector(doFolderFromName)))
            }
            if has(.folderColor) && !folderSel.isEmpty {
                let sub = NSMenu()
                for (name, c) in Self.colors {
                    let mi = item(name, nil, #selector(doFolderColor(_:)), name)
                    mi.image = Self.swatch(c)
                    sub.addItem(mi)
                }
                sub.addItem(.separator())
                sub.addItem(item(tr("Kembalikan ikon asli", "Restore original icon"), "arrow.uturn.backward", #selector(doFolderColor(_:)), "reset"))
                let mi = item(ClickItem.folderColor.title, ClickItem.folderColor.symbol, #selector(noop))
                mi.submenu = sub
                m.addItem(mi)
            }
        }
        if has(.toggleHidden) {
            m.addItem(.separator())
            m.addItem(item(ClickItem.toggleHidden.title, ClickItem.toggleHidden.symbol, #selector(doToggleHidden)))
        }
        if sel && has(.permanentDelete) {
            m.addItem(.separator())
            m.addItem(item(ClickItem.permanentDelete.title, ClickItem.permanentDelete.symbol, #selector(doDelete)))
        }
        // Hapus pemisah ganda / di ujung
        var last: NSMenuItem?
        for mi in m.items {
            if mi.isSeparatorItem && (last?.isSeparatorItem ?? true) { m.removeItem(mi) } else { last = mi }
        }
        if m.items.last?.isSeparatorItem == true { m.removeItem(m.items.last!) }
        return m
    }

    private func folderMenu(_ kind: ClickItem, _ action: Selector) -> NSMenuItem {
        let sub = NSMenu()
        for f in cs.folders { sub.addItem(item((f as NSString).lastPathComponent, "folder", action, f)) }
        if !cs.folders.isEmpty { sub.addItem(.separator()) }
        sub.addItem(item(tr("Pilih folder…", "Choose folder…"), "folder.badge.questionmark", action, "choose"))
        let mi = item(kind.title, kind.symbol, #selector(noop))
        mi.submenu = sub
        return mi
    }

    // MARK: Aksi

    @objc private func noop() {}

    private static func isDir(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
            && u.pathExtension != "app"
    }

    private static func unique(_ dir: URL, _ name: String, _ ext: String) -> URL {
        let fm = FileManager.default
        var u = dir.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
        var n = 2
        while fm.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(name) \(n)" : "\(name) \(n).\(ext)")
            n += 1
        }
        return u
    }

    private func done(_ s: String) {
        lastResult = s
        Notifier.post(title: "Klik Kanan+", body: s)
    }

    private func fail(_ e: Error) {
        lastResult = e.localizedDescription
        let a = NSAlert()
        a.messageText = tr("Tidak berhasil", "Couldn't complete")
        a.informativeText = e.localizedDescription
        a.runModal()
    }

    private func reveal(_ u: URL) { NSWorkspace.shared.activateFileViewerSelecting([u]) }

    @objc private func doNewFile(_ s: NSMenuItem) {
        guard let raw = s.representedObject as? String, let k = NewFileKind(rawValue: raw), let dir = directory else { return }
        let u = Self.unique(dir, k.baseName, k.rawValue)
        do {
            if let text = k.textContent {
                try text.write(to: u, atomically: true, encoding: .utf8)
            } else {
                guard let tpl = Bundle.main.url(forResource: "blank", withExtension: k.rawValue, subdirectory: "Templates") else {
                    throw NSError(domain: "PY-Sys", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        tr("Template \(k.title) tidak ditemukan di aplikasi.", "\(k.title) template not found in the app.")])
                }
                try FileManager.default.copyItem(at: tpl, to: u)
            }
            if cs.openNew { NSWorkspace.shared.open(u) } else { reveal(u) }
            done(tr("Dibuat: \(u.lastPathComponent)", "Created: \(u.lastPathComponent)"))
        } catch { fail(error) }
    }

    @objc private func doNewFolder() {
        guard let dir = directory else { return }
        let u = Self.unique(dir, tr("Folder baru", "New Folder"), "")
        do {
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
            reveal(u)
        } catch { fail(error) }
    }

    private var pathTargets: [URL] { targets.isEmpty ? (directory.map { [$0] } ?? []) : targets }

    private func toClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        done(tr("Disalin ke clipboard", "Copied to clipboard"))
    }

    @objc private func doCopyPath() { toClipboard(pathTargets.map(\.path).joined(separator: "\n")) }
    @objc private func doCopyName() { toClipboard(targets.map(\.lastPathComponent).joined(separator: "\n")) }
    @objc private func doCopyTerminal() {
        toClipboard(pathTargets.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " "))
    }

    @objc private func doTerminal() {
        let dir = targets.count == 1 && Self.isDir(targets[0]) ? targets[0] : directory
        guard let dir, let term = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([dir], withApplicationAt: term, configuration: NSWorkspace.OpenConfiguration())
    }

    private func chooseFolder() -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = tr("Pilih", "Choose")
        NSApp.activate(ignoringOtherApps: true)
        return p.runModal() == .OK ? p.url : nil
    }

    private func destination(_ s: NSMenuItem) -> URL? {
        guard let raw = s.representedObject as? String else { return nil }
        return raw == "choose" ? chooseFolder() : URL(fileURLWithPath: raw, isDirectory: true)
    }

    private func transfer(_ s: NSMenuItem, move: Bool) {
        guard let dest = destination(s) else { return }
        let fm = FileManager.default
        var last: URL?
        do {
            for src in targets {
                let name = src.deletingPathExtension().lastPathComponent
                let to = Self.unique(dest, name, Self.isDir(src) ? "" : src.pathExtension)
                if move { try fm.moveItem(at: src, to: to) } else { try fm.copyItem(at: src, to: to) }
                last = to
            }
            if let last { reveal(last) }
            done(move ? tr("Dipindahkan ke \(dest.lastPathComponent)", "Moved to \(dest.lastPathComponent)")
                      : tr("Disalin ke \(dest.lastPathComponent)", "Copied to \(dest.lastPathComponent)"))
        } catch { fail(error) }
    }

    @objc private func doMove(_ s: NSMenuItem) { transfer(s, move: true) }
    @objc private func doCopy(_ s: NSMenuItem) { transfer(s, move: false) }

    @objc private func doOpenFolder(_ s: NSMenuItem) {
        guard let raw = s.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: raw, isDirectory: true))
    }

    @objc private func doAddCommon() {
        for u in targets where Self.isDir(u) && !cs.folders.contains(u.path) { cs.folders.append(u.path) }
        done(tr("Ditambahkan ke folder favorit", "Added to Common Folders"))
    }

    @objc private func doShortcut() {
        let list = targets.map { "POSIX file \"\($0.path.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")
        let src = "tell application \"Finder\" to make new alias file at desktop to {\(list)}"
        var err: NSDictionary?
        _ = NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err { lastResult = "\(err[NSAppleScript.errorMessage] ?? err)" } else {
            done(tr("Shortcut dibuat di Desktop", "Shortcut created on Desktop"))
        }
    }

    @objc private func doAirDrop() {
        guard let svc = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        svc.perform(withItems: targets)
    }

    @objc private func doFolderFromName() {
        let fm = FileManager.default
        var last: URL?
        do {
            for f in targets where !Self.isDir(f) {
                let dir = f.deletingLastPathComponent()
                var folder = dir.appendingPathComponent(f.deletingPathExtension().lastPathComponent, isDirectory: true)
                if fm.fileExists(atPath: folder.path) && !Self.isDir(folder) {
                    folder = Self.unique(dir, f.deletingPathExtension().lastPathComponent, "")
                }
                if !fm.fileExists(atPath: folder.path) { try fm.createDirectory(at: folder, withIntermediateDirectories: false) }
                let to = Self.unique(folder, f.deletingPathExtension().lastPathComponent, f.pathExtension)
                try fm.moveItem(at: f, to: to)
                last = folder
            }
            if let last { reveal(last) }
        } catch { fail(error) }
    }

    static let colors: [(String, NSColor)] = [
        (tr("Merah", "Red"), .systemRed), (tr("Oranye", "Orange"), .systemOrange), (tr("Kuning", "Yellow"), .systemYellow),
        (tr("Hijau", "Green"), .systemGreen), (tr("Biru", "Blue"), .systemBlue), (tr("Ungu", "Purple"), .systemPurple),
        (tr("Merah muda", "Pink"), .systemPink), (tr("Abu-abu", "Gray"), .systemGray),
    ]

    private static func swatch(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            c.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    /// Ikon folder bawaan diwarnai ulang (mode warna), lalu dipasang sebagai ikon kustom folder.
    private static func tinted(_ color: NSColor) -> NSImage? {
        let base = NSWorkspace.shared.icon(for: .folder)
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { r in
            base.draw(in: r)
            color.withAlphaComponent(0.85).set()
            r.fill(using: .sourceAtop)
            base.draw(in: r, from: .zero, operation: .multiply, fraction: 0.35)
            return true
        }
    }

    @objc private func doFolderColor(_ s: NSMenuItem) {
        guard let key = s.representedObject as? String else { return }
        let img: NSImage? = key == "reset" ? nil : Self.colors.first { $0.0 == key }.flatMap { Self.tinted($0.1) }
        for u in targets where Self.isDir(u) {
            _ = NSWorkspace.shared.setIcon(img, forFile: u.path, options: [])
        }
    }

    @objc private func doToggleHidden() {
        let cur = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles") ?? false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", cur ? "false" : "true"]
        try? p.run()
        p.waitUntilExit()
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        k.arguments = ["Finder"]
        try? k.run()
        done(cur ? tr("File tersembunyi disembunyikan", "Hidden files hidden") : tr("File tersembunyi ditampilkan", "Hidden files shown"))
    }

    @objc private func doDelete() {
        let a = NSAlert()
        a.alertStyle = .critical
        a.messageText = tr("Hapus permanen \(targets.count) item?", "Permanently delete \(targets.count) item(s)?")
        a.informativeText = targets.prefix(5).map(\.lastPathComponent).joined(separator: "\n")
            + (targets.count > 5 ? "\n…" : "")
            + "\n\n" + tr("Tidak masuk Trash dan tidak bisa dibatalkan.", "This skips the Trash and can't be undone.")
        a.addButton(withTitle: tr("Hapus permanen", "Delete permanently"))
        a.addButton(withTitle: tr("Batal", "Cancel"))
        a.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do {
            for u in targets { try FileManager.default.removeItem(at: u) }
            done(tr("\(targets.count) item dihapus permanen", "\(targets.count) item(s) permanently deleted"))
        } catch { fail(error) }
    }

    // MARK: Quick Actions (NSServices) — Finder › klik kanan › Quick Actions › PY-Sys: Klik Kanan+

    @objc func showMenuService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        DispatchQueue.main.async { self.show(targets: urls, directory: urls.first?.deletingLastPathComponent()) }
    }

    @objc func copyPathService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async { self.toClipboard(urls.map(\.path).joined(separator: "\n")) }
    }

    @objc func terminalService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard let u = urls.first else { return }
        DispatchQueue.main.async {
            self.targets = [u]
            self.directory = Self.isDir(u) ? u : u.deletingLastPathComponent()
            self.doTerminal()
        }
    }
}

// MARK: - Utility › Klik Kanan+

struct ClickMenuTab: View {
    @ObservedObject private var cs = ClickSettings.shared
    @ObservedObject private var cm = ClickMenu.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(tr("Aktifkan Klik Kanan+", "Enable Right-Click+"), isOn: Binding(
                get: { cs.enabled },
                set: { v in cs.enabled = v; cm.apply(prompt: v) }))
                .toggleStyle(.switch)
            HStack(spacing: 6) {
                Circle().fill(cm.running ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(cm.running ? tr("Berjalan · berlaku di Finder dan Desktop", "Running · works in Finder and on the Desktop")
                                : tr("Tidak aktif", "Off"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            GroupBox(tr("Cara memunculkan menu", "How to open the menu")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("", isOn: $cs.modifierOn).labelsHidden()
                        Text(tr("1. Tahan", "1. Hold"))
                        Picker("", selection: $cs.trigger) {
                            ForEach(Trigger.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden().frame(width: 120)
                        Text(tr("+ klik kanan", "+ right-click"))
                        Spacer()
                    }
                    HStack {
                        Toggle("", isOn: $cs.middleClick).labelsHidden()
                        Text(tr("2. Klik tombol tengah mouse", "2. Click the middle mouse button"))
                        Spacer()
                    }
                    HStack {
                        Toggle("", isOn: $cs.hotkeyOn).labelsHidden()
                        Text(tr("3. Shortcut ⌃⌥Space (Control + Option + Spasi) untuk file yang dipilih",
                                "3. Shortcut ⌃⌥Space (Control + Option + Space) for the selected files"))
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "checkmark.circle").foregroundStyle(.secondary).frame(width: 20)
                        Text(tr("4. Finder › klik kanan pada file › Quick Actions › “PY-Sys: Klik Kanan+” (selalu tersedia)",
                                "4. Finder › right-click a file › Quick Actions › “PY-Sys: Right-Click+” (always available)"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)
                .disabled(!cs.enabled)
            }

            GroupBox(tr("Isi menu", "Menu items")) {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                    ForEach(ClickItem.allCases) { i in
                        Toggle(isOn: cs.binding(i)) {
                            Label(i.title, systemImage: i.symbol).lineLimit(1)
                        }
                    }
                }
                .font(.caption)
            }

            GroupBox(tr("File baru", "New File")) {
                VStack(alignment: .leading, spacing: 6) {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                        ForEach(NewFileKind.allCases) { k in
                            Toggle(k.title, isOn: cs.binding(k))
                        }
                    }
                    Toggle(tr("Buka file baru secara otomatis", "Open new file automatically"), isOn: $cs.openNew)
                }
                .font(.caption)
            }

            GroupBox(tr("Folder favorit", "Common Folders")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(cs.folders, id: \.self) { f in
                        HStack {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text((f as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { cs.folders.removeAll { $0 == f } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button(tr("Tambah folder…", "Add folder…")) {
                        let p = NSOpenPanel()
                        p.canChooseDirectories = true
                        p.canChooseFiles = false
                        p.allowsMultipleSelection = true
                        NSApp.activate(ignoringOtherApps: true)
                        if p.runModal() == .OK {
                            for u in p.urls where !cs.folders.contains(u.path) { cs.folders.append(u.path) }
                        }
                    }
                    .controlSize(.small)
                }
                .font(.caption)
            }

            Text(tr("Menu ini buatan PY-Sys dan muncul di posisi kursor, bukan di dalam menu klik kanan bawaan Finder. Butuh izin Accessibility (menangkap klik) dan Automation › Finder (membaca file yang dipilih).",
                    "This menu is PY-Sys's own and opens at the pointer, not inside Finder's built-in right-click menu. Needs Accessibility (to catch the click) and Automation › Finder (to read the selection)."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let m = cm.message {
                Text(m).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Accessibility") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Button("Automation") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                }
                .controlSize(.small)
            }
            HStack {
                Button(tr("Tes menu sekarang", "Test the menu now")) {
                    let (sel, dir) = ClickMenu.finderSelection()
                    cm.show(targets: sel, directory: dir)
                }
                .controlSize(.small)
                Spacer()
            }
            GroupBox(tr("Diagnosis", "Diagnostics")) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Accessibility: " + (AXIsProcessTrusted() ? tr("diizinkan", "allowed") : tr("BELUM diizinkan", "NOT allowed")))
                    Text(tr("Klik terakhir: ", "Last click: ") + (cm.lastEvent ?? tr("belum ada yang tertangkap", "nothing caught yet")))
                }
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let r = cm.lastResult {
                Text(r).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
