import SwiftUI
import AppKit
import WebKit
import Carbon
import UserNotifications

// MARK: - Design System
// Tokens lifted 1:1 from the Claude Design prototype (website demo.css + the Rust
// app's popup/theme.rs) so macOS, Linux and Windows render the same surfaces.

enum AppTheme: String {
    case light, dark, system
}

enum Accent: String {
    case warm, cool, coral, mono
}

enum TrayIconStyle: String {
    case number, ring, mark
}

struct Palette {
    let bgStage: Color
    let bgCard: Color
    let bgCardAlt: Color
    let bgInset: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let border: Color
    let borderStrong: Color
    let accent: Color
    let onAccent: Color
    let lvLow: Color
    let lvMid: Color
    let lvHigh: Color
    let lvCrit: Color

    // Tier thresholds match project/app.js levelKey: >=87 crit, >=70 high, >=45 mid, else low.
    func tierColor(_ pct: Int) -> Color {
        if pct >= 87 { return lvCrit }
        if pct >= 70 { return lvHigh }
        if pct >= 45 { return lvMid }
        return lvLow
    }
}

// Per-accent tier ramp (low, mid, high, crit) — verbatim from popup/theme.rs.
func accentRamp(_ accent: Accent) -> (UInt32, UInt32, UInt32, UInt32) {
    switch accent {
    case .warm:  return (0xe0a84a, 0xe07f33, 0xd4583a, 0xc33b2c)
    case .cool:  return (0x36c97a, 0xe0a132, 0xe0613e, 0xd23b30)
    case .coral: return (0xcf9168, 0xcd7548, 0xbd5238, 0xa83c2a)
    case .mono:  return (0x9aa0a6, 0x7d8389, 0x5f656b, 0x494e53)
    }
}

func makePalette(isDark: Bool, accent: Accent) -> Palette {
    let (low, mid, high, crit) = accentRamp(accent)
    let accentInt = Color(hex: 0xc8603f) // single interactive accent across themes
    if isDark {
        return Palette(
            bgStage: Color(hex: 0x0e0e10),
            bgCard: Color(hex: 0x17171a),
            bgCardAlt: Color(hex: 0x1f1f23),
            bgInset: Color(hex: 0x121214),
            textPrimary: Color(hex: 0xf3f2ee),
            textSecondary: Color(hex: 0xc1beb6),
            textMuted: Color(hex: 0x8a8780),
            border: Color(hex: 0x2a2a2e),
            borderStrong: Color(hex: 0x3a3a3e),
            accent: accentInt,
            onAccent: .white,
            lvLow: Color(hex: low), lvMid: Color(hex: mid), lvHigh: Color(hex: high), lvCrit: Color(hex: crit)
        )
    }
    return Palette(
        bgStage: Color(hex: 0xe9e6e0),
        bgCard: Color(hex: 0xfafaf7),
        bgCardAlt: Color(hex: 0xf2f0ea),
        bgInset: Color(hex: 0xeeebe3),
        textPrimary: Color(hex: 0x1a1a1c),
        textSecondary: Color(hex: 0x4a4740),
        textMuted: Color(hex: 0x807c73),
        border: Color(hex: 0xd5d0c4),
        borderStrong: Color(hex: 0xbcb6a8),
        accent: accentInt,
        onAccent: .white,
        lvLow: Color(hex: low), lvMid: Color(hex: mid), lvHigh: Color(hex: high), lvCrit: Color(hex: crit)
    )
}

// Tray color mirrors the popup meter exactly (4-tier ramp: low/mid/high/crit),
// keyed by session percent. Thresholds match `Palette.tierColor`.
func trayTierNSColor(_ pct: Int, _ accent: Accent) -> NSColor {
    let (low, mid, high, crit) = accentRamp(accent)
    let hex: UInt32
    if pct >= 87 { hex = crit }
    else if pct >= 70 { hex = high }
    else if pct >= 45 { hex = mid }
    else { hex = low }
    return NSColor(hex: hex)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0,
            opacity: 1.0
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255.0,
            green: CGFloat((hex >> 8) & 0xff) / 255.0,
            blue: CGFloat(hex & 0xff) / 255.0,
            alpha: 1.0
        )
    }
}

// Fill {pct}/{limit}/{reset} tokens — mirrors notify.rs render_template.
func renderNotificationTemplate(_ template: String, pct: Int, limit: String, reset: String) -> String {
    return template
        .replacingOccurrences(of: "{pct}", with: "\(pct)%")
        .replacingOccurrences(of: "{limit}", with: limit)
        .replacingOccurrences(of: "{reset}", with: reset)
}

// UserNotifications wrapper — handles auth, foreground presentation, and falls
// back to a plain alert if the system rejects the request (common for ad-hoc
// signed / unsigned builds where the system Notification Center won't show our
// banners). The fallback is what lets the Preview button actually do something
// visible even when notifications aren't fully wired up.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private var authorized = false
    private var requestedAuth = false

    func bootstrap() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorized = (settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional)
                if settings.authorizationStatus == .notDetermined {
                    self?.requestAuthorization()
                }
            }
        }
    }

    func requestAuthorization() {
        guard !requestedAuth else { return }
        requestedAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
            }
        }
    }

    func send(title: String, body: String, sound: Bool = true, isPreview: Bool = false) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { [weak self] error in
            if let error = error {
                NSLog("❌ Notification delivery failed: \(error.localizedDescription)")
                if isPreview {
                    DispatchQueue.main.async {
                        self?.showFallbackAlert(title: title, body: body, reason: error.localizedDescription)
                    }
                }
                return
            }
            // Re-check authorization. If still .denied, surface a fallback so
            // the preview button isn't silent on ad-hoc builds.
            if isPreview {
                center.getNotificationSettings { settings in
                    if settings.authorizationStatus == .denied {
                        DispatchQueue.main.async {
                            self?.showFallbackAlert(
                                title: title,
                                body: body,
                                reason: "Notifications are denied for this app in System Settings → Notifications → ClaudeUsageBar."
                            )
                        }
                    }
                }
            }
        }
    }

    private func showFallbackAlert(title: String, body: String, reason: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(body)\n\n\(reason)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // Show banners even when the app is in the foreground (popup open). Without
    // this delegate, UN suppresses notifications when our app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

// Main entry point
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var popupPanel: NSPanel?
    var popupHosting: NSHostingController<UsageView>?
    var settingsWindow: NSWindow?
    var settingsHosting: NSHostingController<UsageView>?
    var refreshTimer: Timer?
    var updateCheckTimer: Timer?
    var usageManager: UsageManager!
    var statusManager: StatusManager!
    var updateManager: UpdateManager!
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bootstrap UserNotifications (auth + foreground delegate). For ad-hoc
        // builds the system may still deny banners — the service shows an alert
        // fallback for the Preview button so it's never silent.
        NotificationService.shared.bootstrap()
        NSLog("✅ App launched, notifications ready")

        // Create status bar item with variable length for compact display
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Create Claude logo as initial icon
            updateStatusIcon(percentage: 0)
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self

            // Force the button to be visible
            button.appearsDisabled = false
            button.isEnabled = true
        }

        // Initialize managers
        usageManager = UsageManager(statusItem: statusItem, delegate: self)
        statusManager = StatusManager()
        updateManager = UpdateManager()

        // Fetch initial data
        usageManager.fetchUsage()
        statusManager.fetch()
        updateManager.fetch()

        rescheduleRefreshTimer()
        rescheduleUpdateCheckTimer()

        // Tick every minute so the tray countdown stays current when enabled.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self, self.usageManager?.showTimeInTray == true else { return }
            self.usageManager.refreshTray()
        }

        // Set up Cmd+U keyboard shortcut
        setupKeyboardShortcut()
    }

    func setupKeyboardShortcut() {
        // Check Accessibility permissions
        checkAccessibilityPermissions()

        // Only register if user has the shortcut enabled
        if usageManager.shortcutEnabled {
            registerGlobalHotKey()
        }
    }

    func setShortcutEnabled(_ enabled: Bool) {
        if enabled {
            registerGlobalHotKey()
        } else {
            unregisterGlobalHotKey()
        }
    }

    func checkAccessibilityPermissions() {
        // Check if app has Accessibility permissions
        let trusted = AXIsProcessTrusted()

        if !trusted {
            NSLog("⚠️ Accessibility permissions not granted")
            // Show alert to guide user
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "ClaudeUsageBar needs Accessibility permission to use the Cmd+U keyboard shortcut.\n\nPlease enable it in:\nSystem Settings → Privacy & Security → Accessibility"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Skip for Now")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Open System Settings
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        } else {
            NSLog("✅ Accessibility permissions granted")
        }
    }

    func registerGlobalHotKey() {
        // Guard against double registration
        if hotKeyRef != nil { return }

        var hotKeyID = EventHotKeyID()
        // Use simple numeric ID instead of FourCharCode
        hotKeyID.signature = 0x436C5542 // 'ClUB' as hex
        hotKeyID.id = 1

        // Cmd+U key code
        let keyCode: UInt32 = 32 // 'U' key
        let modifiers: UInt32 = UInt32(cmdKey)

        // Create event spec for hotkey
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        // Install event handler
        var handler: EventHandlerRef?
        let callback: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            // Get the AppDelegate instance
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()

            // Toggle popover
            DispatchQueue.main.async {
                appDelegate.togglePopover()
            }

            return noErr
        }

        // Install the handler
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &handler)

        // Register the hotkey
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr {
            NSLog("✅ Registered Cmd+U hotkey successfully")
        } else {
            NSLog("❌ Failed to register hotkey, status: \(status)")
        }
    }

    func unregisterGlobalHotKey() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
            NSLog("🗑️ Unregistered Cmd+U hotkey")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotKey()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func rescheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(60, usageManager?.refreshIntervalSeconds ?? 300))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.usageManager.fetchUsage()
            self?.statusManager.fetch()
        }
    }

    @objc func rescheduleUpdateCheckTimer() {
        updateCheckTimer?.invalidate()
        guard usageManager?.autoCheckForUpdates == true else { return }
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            self?.updateManager.fetch()
        }
    }

    // Pin the popup panel + settings window to the user-selected theme so the
    // NSVisualEffectView material matches the SwiftUI palette (otherwise material
    // tracks the system appearance while palette tracks the in-app setting).
    func appearanceForUserTheme() -> NSAppearance? {
        switch usageManager?.theme {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    func applyAppearanceToWindows() {
        let appearance = appearanceForUserTheme()
        popupPanel?.appearance = appearance
        settingsWindow?.appearance = appearance
    }

    @objc func openSettingsWindow() {
        closePopover()
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = UsageView(
            usageManager: usageManager,
            statusManager: statusManager,
            updateManager: updateManager,
            settingsWindowMode: true
        )
        let hosting = NSHostingController(rootView: content)
        settingsHosting = hosting

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage Bar — Settings"
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        settingsWindow = window
        applyAppearanceToWindows()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func closeSettingsWindow() {
        settingsWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing == settingsWindow {
            settingsWindow = nil
            settingsHosting = nil
        }
    }

    @objc func togglePopover() {
        if popupPanel?.isVisible == true {
            closePopover()
        } else {
            openPopover()
        }
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right click - show menu
            let menu = NSMenu()
            let toggleItem = NSMenuItem(title: "Toggle Usage (⌘U)", action: #selector(togglePopover), keyEquivalent: "u")
            toggleItem.keyEquivalentModifierMask = .command
            menu.addItem(toggleItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit ClaudeUsageBar", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left click - toggle popover
            togglePopover()
        }
    }

    func openPopover() {
        guard statusItem.button != nil else { return }

        if popupPanel == nil {
            let hosting = NSHostingController(rootView: UsageView(
                usageManager: usageManager,
                statusManager: statusManager,
                updateManager: updateManager
            ))
            popupHosting = hosting

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hosting
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false
            // Round the host to match SwiftUI's popover material clipping.
            hosting.view.wantsLayer = true
            hosting.view.layer?.cornerRadius = 10
            hosting.view.layer?.masksToBounds = true

            popupPanel = panel
        }

        DispatchQueue.main.async {
            self.usageManager.updatePercentages()
        }

        applyAppearanceToWindows()
        positionPopupPanel()
        popupPanel?.orderFrontRegardless()

        // Re-anchor on next runloop tick once SwiftUI has measured intrinsic size,
        // so the panel sits flush under the icon at its real height.
        DispatchQueue.main.async { [weak self] in
            self?.positionPopupPanel()
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    // Resize the popup panel to match SwiftUI's measured content size, then
    // re-anchor under the icon so the bottom stays inside the visible frame.
    func syncPopupPanelSize() {
        guard let panel = popupPanel, let host = popupHosting?.view else { return }
        let target = host.fittingSize
        if target.width <= 0 || target.height <= 0 { return }
        let current = panel.frame.size
        if abs(current.width - target.width) < 0.5 && abs(current.height - target.height) < 0.5 { return }
        var frame = panel.frame
        // Keep the same top edge so the panel doesn't appear to jump.
        let topY = frame.maxY
        frame.size = target
        frame.origin.y = topY - target.height
        panel.setFrame(frame, display: true)
        positionPopupPanel()
    }

    func positionPopupPanel() {
        guard let panel = popupPanel,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }
        let buttonScreenFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let panelSize = panel.frame.size
        let gap: CGFloat = 4

        // Decide which edge of the visible frame the status item sits on.
        // macOS status bar is normally top, but Stage Manager / external screens
        // can shift the visible region; pick the edge closest to the icon.
        let dTop = abs(buttonScreenFrame.minY - visible.maxY)
        let dBottom = abs(buttonScreenFrame.maxY - visible.minY)
        let dLeft = abs(buttonScreenFrame.minX - visible.minX)
        let dRight = abs(buttonScreenFrame.maxX - visible.maxX)
        let minDist = min(dTop, dBottom, dLeft, dRight)

        var origin = NSPoint.zero
        if minDist == dTop {
            // Bar at top → drop panel below the icon.
            origin.x = buttonScreenFrame.midX - panelSize.width / 2
            origin.y = buttonScreenFrame.minY - panelSize.height - gap
        } else if minDist == dBottom {
            // Bar at bottom → pop panel above the icon.
            origin.x = buttonScreenFrame.midX - panelSize.width / 2
            origin.y = buttonScreenFrame.maxY + gap
        } else if minDist == dLeft {
            // Bar at left → fly out to the right.
            origin.x = buttonScreenFrame.maxX + gap
            origin.y = buttonScreenFrame.midY - panelSize.height / 2
        } else {
            // Bar at right → fly out to the left.
            origin.x = buttonScreenFrame.minX - panelSize.width - gap
            origin.y = buttonScreenFrame.midY - panelSize.height / 2
        }

        // Clamp inside the visible frame so nothing slides under the menu bar.
        origin.x = max(visible.minX + gap, min(origin.x, visible.maxX - panelSize.width - gap))
        origin.y = max(visible.minY + gap, min(origin.y, visible.maxY - panelSize.height - gap))

        panel.setFrameOrigin(origin)
    }

    func closePopover() {
        popupPanel?.orderOut(nil)

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func updateStatusIcon(percentage: Int) {
        guard let button = statusItem.button else { return }

        // Read appearance settings; updateStatusIcon can fire before usageManager
        // exists (initial 0% paint), so fall back to defaults.
        let style: TrayIconStyle
        let accent: Accent
        let showPct: Bool
        let showTime: Bool
        let resetDate: Date?
        if let manager = usageManager {
            style = manager.trayIconStyle
            accent = manager.accent
            showPct = manager.showPercentInTray
            showTime = manager.showTimeInTray
            resetDate = manager.sessionResetsAt
        } else {
            style = .mark
            accent = .warm
            showPct = true
            showTime = false
            resetDate = nil
        }

        // Color tracks the session tier (amber → red), replacing green/yellow/red.
        let color = trayTierNSColor(percentage, accent)

        // Build the trailing title: " 10% (1h10m)" / " 10%" / " (1h10m)" / "".
        var parts: [String] = []
        if showPct { parts.append("\(percentage)%") }
        if showTime, let date = resetDate, let rem = compactTimeRemaining(date) {
            parts.append("(\(rem))")
        }
        let title = parts.isEmpty ? "" : " " + parts.joined(separator: " ")

        switch style {
        case .ring:
            button.image = createRingIcon(color: color, percentage: percentage)
        case .mark:
            button.image = createSparkIcon(color: color)
        case .number:
            button.image = createDotIcon(color: color)
        }
        button.title = title
        button.attributedTitle = NSAttributedString(string: button.title)
    }

    func createRingIcon(color: NSColor, percentage: Int) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)

        image.lockFocus()

        let center = NSPoint(x: 8, y: 8)
        let radius: CGFloat = 6.0
        let lineWidth: CGFloat = 2.2

        // Faded full-circle track.
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.28).setStroke()
        track.stroke()

        // Progress arc, clockwise from 12 o'clock.
        let pct = max(0, min(100, percentage))
        if pct > 0 {
            let arc = NSBezierPath()
            let start: CGFloat = 90
            let end = start - CGFloat(pct) / 100.0 * 360.0
            arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false

        return image
    }

    func createDotIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let radius: CGFloat = 4.0
        let rect = NSRect(x: 8 - radius, y: 8 - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // Compact remaining time for the tray strip. Returns nil if past or unavailable.
    // Examples: "45m", "3h10m", "2d4h", "1d".
    func compactTimeRemaining(_ date: Date) -> String? {
        let total = Int(date.timeIntervalSinceNow)
        if total <= 0 { return nil }
        let minutes = (total / 60) % 60
        let hours = (total / 3600) % 24
        let days = total / 86400
        if days > 0 {
            return hours > 0 ? "\(days)d\(hours)h" : "\(days)d"
        }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }

    func createSparkIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)

        image.lockFocus()

        // SVG path: M8 1L9 6L13 3L10 7L15 8L10 9L13 13L9 10L8 15L7 10L3 13L6 9L1 8L6 7L3 3L7 6L8 1Z
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8, y: 1))
        path.line(to: NSPoint(x: 9, y: 6))
        path.line(to: NSPoint(x: 13, y: 3))
        path.line(to: NSPoint(x: 10, y: 7))
        path.line(to: NSPoint(x: 15, y: 8))
        path.line(to: NSPoint(x: 10, y: 9))
        path.line(to: NSPoint(x: 13, y: 13))
        path.line(to: NSPoint(x: 9, y: 10))
        path.line(to: NSPoint(x: 8, y: 15))
        path.line(to: NSPoint(x: 7, y: 10))
        path.line(to: NSPoint(x: 3, y: 13))
        path.line(to: NSPoint(x: 6, y: 9))
        path.line(to: NSPoint(x: 1, y: 8))
        path.line(to: NSPoint(x: 6, y: 7))
        path.line(to: NSPoint(x: 3, y: 3))
        path.line(to: NSPoint(x: 7, y: 6))
        path.close()

        color.setFill()
        path.fill()

        image.unlockFocus()
        image.isTemplate = false

        return image
    }
}

// NSColor extension for hex conversion
extension NSColor {
    var hexString: String {
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else {
            return "#000000"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// Main entry point
@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

class UsageManager: ObservableObject {
    @Published var sessionUsage: Int = 0
    @Published var sessionLimit: Int = 100
    @Published var weeklyUsage: Int = 0
    @Published var weeklyLimit: Int = 100
    @Published var weeklySonnetUsage: Int = 0
    @Published var weeklySonnetLimit: Int = 100
    @Published var sessionResetsAt: Date?
    @Published var weeklyResetsAt: Date?
    @Published var weeklySonnetResetsAt: Date?
    @Published var lastUpdated: Date = Date()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var usageNotificationsEnabled: Bool = true
    @Published var statusNotificationsEnabled: Bool = true
    @Published var openAtLogin: Bool = false
    @Published var hasWeeklySonnet: Bool = false
    @Published var hasFetchedData: Bool = false
    @Published var isAccessibilityEnabled: Bool = false
    @Published var shortcutEnabled: Bool = true

    // Design-system settings (parity with the Rust app's storage.rs Settings).
    @Published var theme: AppTheme = .system
    @Published var accent: Accent = .warm
    @Published var trayIconStyle: TrayIconStyle = .number
    @Published var showPercentInTray: Bool = true
    @Published var showTimeInTray: Bool = false
    @Published var showServiceStatus: Bool = false
    @Published var autoCheckForUpdates: Bool = true
    @Published var refreshIntervalSeconds: Int = 300
    @Published var sessionWarnThreshold: Int = 80
    @Published var weeklyWarnThreshold: Int = 80
    @Published var notifMessageTemplate: String =
        "Heads up — you've used {pct} of your {limit} limit. Resets {reset}."

    private var statusItem: NSStatusItem?
    private var sessionCookie: String = ""
    private weak var delegate: AppDelegate?
    private var lastNotifiedThreshold: Int = 0

    init(statusItem: NSStatusItem?, delegate: AppDelegate? = nil) {
        self.statusItem = statusItem
        self.delegate = delegate
        loadSessionCookie()
        loadSettings()
        checkAccessibilityStatus()
    }

    func checkAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    func loadSessionCookie() {
        if let savedCookie = UserDefaults.standard.string(forKey: "claude_session_cookie") {
            sessionCookie = savedCookie
        }
    }

    func loadSettings() {
        // Migrate from legacy single notifications_enabled flag (pre-v1.1) to split flags
        let hasUsageKey  = UserDefaults.standard.object(forKey: "usage_notifications_enabled")  != nil
        let hasStatusKey = UserDefaults.standard.object(forKey: "status_notifications_enabled") != nil

        if !hasUsageKey || !hasStatusKey {
            let legacyHasKey = UserDefaults.standard.object(forKey: "notifications_enabled") != nil
            let legacyValue  = legacyHasKey ? UserDefaults.standard.bool(forKey: "notifications_enabled") : true
            if !hasUsageKey {
                usageNotificationsEnabled = legacyValue
                UserDefaults.standard.set(legacyValue, forKey: "usage_notifications_enabled")
            }
            if !hasStatusKey {
                statusNotificationsEnabled = legacyValue
                UserDefaults.standard.set(legacyValue, forKey: "status_notifications_enabled")
            }
        }
        if hasUsageKey {
            usageNotificationsEnabled = UserDefaults.standard.bool(forKey: "usage_notifications_enabled")
        }
        if hasStatusKey {
            statusNotificationsEnabled = UserDefaults.standard.bool(forKey: "status_notifications_enabled")
        }

        openAtLogin = UserDefaults.standard.bool(forKey: "open_at_login")
        lastNotifiedThreshold = UserDefaults.standard.integer(forKey: "last_notified_threshold")
        // Default shortcut to enabled if not previously set
        if UserDefaults.standard.object(forKey: "shortcut_enabled") == nil {
            shortcutEnabled = true
        } else {
            shortcutEnabled = UserDefaults.standard.bool(forKey: "shortcut_enabled")
        }

        // Design-system settings — keys mirror the Rust app's storage.rs field names.
        if let raw = UserDefaults.standard.string(forKey: "theme"), let v = AppTheme(rawValue: raw) {
            theme = v
        }
        if let raw = UserDefaults.standard.string(forKey: "accent"), let v = Accent(rawValue: raw) {
            accent = v
        }
        if let raw = UserDefaults.standard.string(forKey: "tray_icon_style"), let v = TrayIconStyle(rawValue: raw) {
            trayIconStyle = v
        }
        if UserDefaults.standard.object(forKey: "show_percent_in_tray") != nil {
            showPercentInTray = UserDefaults.standard.bool(forKey: "show_percent_in_tray")
        }
        if UserDefaults.standard.object(forKey: "show_time_in_tray") != nil {
            showTimeInTray = UserDefaults.standard.bool(forKey: "show_time_in_tray")
        }
        if UserDefaults.standard.object(forKey: "show_service_status") != nil {
            showServiceStatus = UserDefaults.standard.bool(forKey: "show_service_status")
        }
        if UserDefaults.standard.object(forKey: "auto_check_for_updates") != nil {
            autoCheckForUpdates = UserDefaults.standard.bool(forKey: "auto_check_for_updates")
        }
        let storedInterval = UserDefaults.standard.integer(forKey: "refresh_interval_seconds")
        if [60, 300, 900].contains(storedInterval) {
            refreshIntervalSeconds = storedInterval
        }
        if UserDefaults.standard.object(forKey: "session_warn_threshold") != nil {
            sessionWarnThreshold = UserDefaults.standard.integer(forKey: "session_warn_threshold")
        }
        if UserDefaults.standard.object(forKey: "weekly_warn_threshold") != nil {
            weeklyWarnThreshold = UserDefaults.standard.integer(forKey: "weekly_warn_threshold")
        }
        if let raw = UserDefaults.standard.string(forKey: "notif_message_template"), !raw.isEmpty {
            notifMessageTemplate = raw
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(usageNotificationsEnabled,  forKey: "usage_notifications_enabled")
        UserDefaults.standard.set(statusNotificationsEnabled, forKey: "status_notifications_enabled")
        UserDefaults.standard.set(openAtLogin, forKey: "open_at_login")
        UserDefaults.standard.set(shortcutEnabled, forKey: "shortcut_enabled")
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
        UserDefaults.standard.set(accent.rawValue, forKey: "accent")
        UserDefaults.standard.set(trayIconStyle.rawValue, forKey: "tray_icon_style")
        UserDefaults.standard.set(showPercentInTray, forKey: "show_percent_in_tray")
        UserDefaults.standard.set(showTimeInTray, forKey: "show_time_in_tray")
        UserDefaults.standard.set(showServiceStatus, forKey: "show_service_status")
        UserDefaults.standard.set(autoCheckForUpdates, forKey: "auto_check_for_updates")
        UserDefaults.standard.set(refreshIntervalSeconds, forKey: "refresh_interval_seconds")
        UserDefaults.standard.set(sessionWarnThreshold, forKey: "session_warn_threshold")
        UserDefaults.standard.set(weeklyWarnThreshold, forKey: "weekly_warn_threshold")
        UserDefaults.standard.set(notifMessageTemplate, forKey: "notif_message_template")
        UserDefaults.standard.synchronize()
    }

    // Re-render the menu-bar icon from current usage + appearance settings. Called
    // after a tray-affecting setting (style/accent/show-percent) changes.
    func refreshTray() {
        let pct = sessionLimit > 0 ? Int((Double(sessionUsage) / Double(sessionLimit)) * 100) : 0
        delegate?.updateStatusIcon(percentage: pct)
    }

    func saveSessionCookie(_ cookie: String) {
        NSLog("ClaudeUsage: Saving cookie, length: \(cookie.count)")
        sessionCookie = cookie
        UserDefaults.standard.set(cookie, forKey: "claude_session_cookie")
        UserDefaults.standard.synchronize()
        NSLog("ClaudeUsage: Cookie saved successfully")
    }

    func clearSessionCookie() {
        NSLog("ClaudeUsage: Clearing cookie")
        sessionCookie = ""
        UserDefaults.standard.removeObject(forKey: "claude_session_cookie")
        UserDefaults.standard.synchronize()

        // Reset all data
        sessionUsage = 0
        weeklyUsage = 0
        weeklySonnetUsage = 0
        sessionResetsAt = nil
        weeklyResetsAt = nil
        weeklySonnetResetsAt = nil
        hasFetchedData = false
        hasWeeklySonnet = false
        errorMessage = nil
        lastNotifiedThreshold = 0
        UserDefaults.standard.set(0, forKey: "last_notified_threshold")

        // Update status bar to show 0%
        delegate?.updateStatusIcon(percentage: 0)

        NSLog("ClaudeUsage: Cookie cleared, data reset")
    }

    func fetchOrganizationId(completion: @escaping (String?) -> Void) {
        // Get org ID from the lastActiveOrg cookie value
        let cookieParts = sessionCookie.components(separatedBy: ";")
        for part in cookieParts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                let orgId = trimmed.replacingOccurrences(of: "lastActiveOrg=", with: "")
                NSLog("📋 Found org ID in cookie: \(orgId)")
                completion(orgId)
                return
            }
        }

        // If not in cookie, fetch from bootstrap
        guard let url = URL(string: "https://claude.ai/api/bootstrap") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionCookie)", forHTTPHeaderField: "Cookie")

        NSLog("📡 Fetching bootstrap to get org ID...")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any],
                  let lastActiveOrgId = account["lastActiveOrgId"] as? String else {
                NSLog("❌ Could not parse org ID from bootstrap")
                completion(nil)
                return
            }
            NSLog("✅ Got org ID from bootstrap: \(lastActiveOrgId)")
            completion(lastActiveOrgId)
        }.resume()
    }

    func fetchUsage() {
        guard !sessionCookie.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "Session cookie not set"
                self.updateStatusBar()
            }
            return
        }

        isLoading = true
        errorMessage = nil

        // Extract org ID from cookie
        fetchOrganizationId { [weak self] orgId in
            guard let self = self, let orgId = orgId else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Could not get org ID from cookie"
                    self?.isLoading = false
                }
                return
            }

            self.fetchUsageWithOrgId(orgId)
        }
    }

    func fetchUsageWithOrgId(_ orgId: String) {
        let urlString = "https://claude.ai/api/organizations/\(orgId)/usage"

        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use the full cookie string (user provides all cookies, not just sessionKey)
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("claude.ai", forHTTPHeaderField: "authority")

        NSLog("🔍 Fetching from: \(urlString)")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    NSLog("❌ Error: \(error.localizedDescription)")
                    self?.errorMessage = "Network error"
                    self?.updateStatusBar()
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.errorMessage = "Invalid response"
                    self?.updateStatusBar()
                    return
                }

                NSLog("📡 Status: \(httpResponse.statusCode)")

                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    NSLog("📦 Response: \(responseString)")
                }

                if httpResponse.statusCode == 200, let data = data {
                    self?.parseUsageData(data)
                } else {
                    self?.errorMessage = "HTTP \(httpResponse.statusCode)"
                }

                self?.updateStatusBar()
            }
        }.resume()
    }

    func parseUsageData(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Invalid JSON"
                return
            }

            NSLog("📊 Parsing usage data...")

            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Parse the actual claude.ai response format
            if let fiveHour = json["five_hour"] as? [String: Any] {
                if let sessionUtil = fiveHour["utilization"] as? Double {
                    sessionUsage = Int(sessionUtil)
                    sessionLimit = 100
                }
                if let resetsAtString = fiveHour["resets_at"] as? String {
                    NSLog("🕐 Session resets_at string: \(resetsAtString)")
                    if let resetsAt = iso8601Formatter.date(from: resetsAtString) {
                        sessionResetsAt = resetsAt
                        NSLog("✅ Parsed session reset time: \(resetsAt)")
                    } else {
                        NSLog("❌ Failed to parse session reset time")
                    }
                }
            }

            if let sevenDay = json["seven_day"] as? [String: Any] {
                if let weeklyUtil = sevenDay["utilization"] as? Double {
                    weeklyUsage = Int(weeklyUtil)
                    weeklyLimit = 100
                }
                if let resetsAtString = sevenDay["resets_at"] as? String {
                    NSLog("🕐 Weekly resets_at string: \(resetsAtString)")
                    if let resetsAt = iso8601Formatter.date(from: resetsAtString) {
                        weeklyResetsAt = resetsAt
                        NSLog("✅ Parsed weekly reset time: \(resetsAt)")
                    } else {
                        NSLog("❌ Failed to parse weekly reset time")
                    }
                }
            }

            // Check for seven_day_sonnet (Pro plan feature)
            if let sevenDaySonnet = json["seven_day_sonnet"] as? [String: Any] {
                hasWeeklySonnet = true
                if let sonnetUtil = sevenDaySonnet["utilization"] as? Double {
                    weeklySonnetUsage = Int(sonnetUtil)
                    weeklySonnetLimit = 100
                }
                if let resetsAtString = sevenDaySonnet["resets_at"] as? String {
                    NSLog("🕐 Weekly Sonnet resets_at string: \(resetsAtString)")
                    if let resetsAt = iso8601Formatter.date(from: resetsAtString) {
                        weeklySonnetResetsAt = resetsAt
                        NSLog("✅ Parsed weekly Sonnet reset time: \(resetsAt)")
                    } else {
                        NSLog("❌ Failed to parse weekly Sonnet reset time")
                    }
                }
            } else {
                hasWeeklySonnet = false
            }

            // Log what we found
            NSLog("✅ Parsed: Session \(sessionUsage)%, Weekly \(weeklyUsage)%\(hasWeeklySonnet ? ", Weekly Sonnet \(weeklySonnetUsage)%" : "")")

            lastUpdated = Date()
            errorMessage = nil
            hasFetchedData = true

            // Update percentage values for progress bars
            updatePercentages()
        } catch {
            NSLog("❌ Parse error: \(error.localizedDescription)")
            errorMessage = "Parse error"
        }
    }

    func updateStatusBar() {
        let sessionPercent = Int((Double(sessionUsage) / Double(sessionLimit)) * 100)

        // Update the icon color
        delegate?.updateStatusIcon(percentage: sessionPercent)

        // Check for notification thresholds
        checkNotificationThresholds(percentage: sessionPercent)
    }

    func checkNotificationThresholds(percentage: Int) {
        guard usageNotificationsEnabled else { return }

        // Single configurable warning threshold, matching the Rust app's notify path.
        let threshold = sessionWarnThreshold
        if percentage >= threshold && lastNotifiedThreshold < threshold {
            sendUsageNotification(pct: percentage, limit: "session", reset: relativeResetText(sessionResetsAt))
            lastNotifiedThreshold = threshold
            UserDefaults.standard.set(lastNotifiedThreshold, forKey: "last_notified_threshold")
            UserDefaults.standard.synchronize()
        }

        // Re-arm once usage drops back below the threshold.
        if percentage < threshold && lastNotifiedThreshold != 0 {
            lastNotifiedThreshold = 0
            UserDefaults.standard.set(0, forKey: "last_notified_threshold")
            UserDefaults.standard.synchronize()
        }
    }

    func sendUsageNotification(pct: Int, limit: String, reset: String) {
        let body = renderNotificationTemplate(notifMessageTemplate, pct: pct, limit: limit, reset: reset)
        NotificationService.shared.send(title: "Claude Usage Alert", body: body)
    }

    func sendTestNotification() {
        let body = renderNotificationTemplate(
            notifMessageTemplate,
            pct: sessionWarnThreshold,
            limit: "session",
            reset: relativeResetText(sessionResetsAt)
        )
        NotificationService.shared.send(
            title: "Claude Usage Alert (Preview)",
            body: body,
            isPreview: true
        )
    }

    func relativeResetText(_ date: Date?) -> String {
        guard let date = date else { return "soon" }
        let secs = Int(date.timeIntervalSinceNow)
        if secs <= 0 { return "now" }
        let mins = secs / 60
        let hours = mins / 60
        if hours >= 1 { return "in \(hours)h \(mins % 60)m" }
        return "in \(mins)m"
    }

    @Published var sessionPercentage: Double = 0.0
    @Published var weeklyPercentage: Double = 0.0
    @Published var weeklySonnetPercentage: Double = 0.0

    func updatePercentages() {
        sessionPercentage = Double(sessionUsage) / Double(sessionLimit)
        weeklyPercentage = Double(weeklyUsage) / Double(weeklyLimit)
        weeklySonnetPercentage = Double(weeklySonnetUsage) / Double(weeklySonnetLimit)
    }
}

// MARK: - Anthropic Service Status

struct StatusIncident: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String           // investigating | identified | monitoring | resolved
    let latestUpdate: String
    let updatedAt: Date?
    let componentIds: [String]
}

struct AffectedComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String           // degraded_performance | partial_outage | major_outage
}

struct StatusComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String           // operational | degraded_performance | ...
}

private let defaultTrackedComponents: [StatusComponent] = [
    StatusComponent(id: "c-claude-ai",      name: "claude.ai",                          status: "operational"),
    StatusComponent(id: "c-claude-console", name: "Claude Console (platform.claude.com)", status: "operational"),
    StatusComponent(id: "c-claude-api",     name: "Claude API (api.anthropic.com)",     status: "operational"),
    StatusComponent(id: "c-claude-code",    name: "Claude Code",                         status: "operational"),
    StatusComponent(id: "c-claude-cowork",  name: "Claude Cowork",                       status: "operational"),
    StatusComponent(id: "c-claude-gov",     name: "Claude for Government",              status: "operational"),
]

private let defaultTrackedComponentIdSet: Set<String> = Set(
    defaultTrackedComponents.map { $0.id }.filter { $0 != "c-claude-gov" }
)

class StatusManager: ObservableObject {
    @Published var indicator: String = "none"        // none | minor | major | critical (raw, global)
    @Published var statusDescription: String = "All systems operational"
    @Published var incidents: [StatusIncident] = []
    @Published var affectedComponents: [AffectedComponent] = []
    @Published var allComponents: [StatusComponent] = defaultTrackedComponents
    @Published var selectedComponentIds: Set<String> = defaultTrackedComponentIdSet
    @Published var lastUpdated: Date?
    @Published var hasFetched: Bool = false

    // Canonical URL (status.anthropic.com 302-redirects here)
    private let endpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!

    init() {
        if let saved = UserDefaults.standard.array(forKey: "tracked_component_ids") as? [String] {
            selectedComponentIds = Set(saved)
        }
        // Clean up legacy debug pref if present
        UserDefaults.standard.removeObject(forKey: "status_preview_mode")
    }

    func toggleComponent(_ id: String) {
        if selectedComponentIds.contains(id) {
            selectedComponentIds.remove(id)
        } else {
            selectedComponentIds.insert(id)
        }
        UserDefaults.standard.set(Array(selectedComponentIds), forKey: "tracked_component_ids")
    }

    func isTracked(_ id: String) -> Bool {
        selectedComponentIds.contains(id)
    }

    // MARK: - Filtered/effective views (respect tracked components)

    var filteredAffectedComponents: [AffectedComponent] {
        affectedComponents.filter { selectedComponentIds.contains($0.id) }
    }

    var filteredIncidents: [StatusIncident] {
        incidents.filter { incident in
            guard !incident.componentIds.isEmpty else { return true }
            return incident.componentIds.contains(where: { selectedComponentIds.contains($0) })
        }
    }

    var effectiveIndicator: String {
        let trackedComponents = allComponents.filter { selectedComponentIds.contains($0.id) }
        let max = trackedComponents.map { severity(for: $0.status) }.max() ?? 0
        switch max {
        case 0:  return "none"
        case 1:  return "minor"
        case 2:  return "major"
        default: return "critical"
        }
    }

    private func severity(for componentStatus: String) -> Int {
        switch componentStatus {
        case "operational":          return 0
        case "under_maintenance":    return 1
        case "degraded_performance": return 1
        case "partial_outage":       return 2
        case "major_outage":         return 3
        default:                     return 0
        }
    }

    func fetch() {
        let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }
            self.parse(data)
        }.resume()
    }

    private func parse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let indicator = status["indicator"] as? String,
              let desc = status["description"] as? String else {
            return
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        var parsedIncidents: [StatusIncident] = []
        if let raw = json["incidents"] as? [[String: Any]] {
            for inc in raw {
                guard let id = inc["id"] as? String,
                      let name = inc["name"] as? String,
                      let st = inc["status"] as? String else { continue }
                if st == "resolved" || st == "postmortem" { continue }
                let updates = inc["incident_updates"] as? [[String: Any]] ?? []
                let latest = (updates.first?["body"] as? String) ?? ""
                let dateStr = (updates.first?["created_at"] as? String) ?? (inc["updated_at"] as? String)
                let updatedAt = dateStr.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
                let compIds = (inc["components"] as? [[String: Any]] ?? [])
                    .compactMap { $0["id"] as? String }
                parsedIncidents.append(StatusIncident(
                    id: id, name: name, status: st, latestUpdate: latest,
                    updatedAt: updatedAt,
                    componentIds: compIds
                ))
            }
        }

        var parsedAffected: [AffectedComponent] = []
        var parsedAll: [StatusComponent] = []
        if let raw = json["components"] as? [[String: Any]] {
            for c in raw {
                guard let id = c["id"] as? String,
                      let name = c["name"] as? String,
                      let st = c["status"] as? String else { continue }
                parsedAll.append(StatusComponent(id: id, name: name, status: st))
                if st != "operational" {
                    parsedAffected.append(AffectedComponent(id: id, name: name, status: st))
                }
            }
        }

        DispatchQueue.main.async {
            let isFirstFetch = !self.hasFetched

            self.indicator = indicator
            self.statusDescription = desc
            self.incidents = parsedIncidents
            self.affectedComponents = parsedAffected
            if !parsedAll.isEmpty {
                self.allComponents = parsedAll
                // First time we see real components: track all except Claude for Government by default
                if UserDefaults.standard.array(forKey: "tracked_component_ids") == nil {
                    let defaultIds = parsedAll
                        .filter { !$0.name.localizedCaseInsensitiveContains("Government") }
                        .map { $0.id }
                    self.selectedComponentIds = Set(defaultIds)
                    UserDefaults.standard.set(Array(self.selectedComponentIds),
                                              forKey: "tracked_component_ids")
                }
            }
            self.lastUpdated = Date()
            self.hasFetched = true

            // Notify on transitions of EFFECTIVE (filtered) indicator
            let effective = self.effectiveIndicator
            let previous = UserDefaults.standard.string(forKey: "last_effective_indicator")
            if !isFirstFetch, let previous = previous, previous != effective {
                self.notifyStatusChange(to: effective, description: desc)
            }
            UserDefaults.standard.set(effective, forKey: "last_effective_indicator")
        }
    }

    private func notifyStatusChange(to indicator: String, description: String) {
        guard UserDefaults.standard.bool(forKey: "status_notifications_enabled") else { return }

        let title: String
        let body: String
        if indicator == "none" {
            title = "Claude is back online"
            body = "All systems operational"
        } else {
            title = "Claude status: \(description)"
            body = "Visit status.anthropic.com for details"
        }
        NotificationService.shared.send(title: title, body: body)
        NSLog("📬 Sent status-change notification: \(indicator)")
    }
}

// MARK: - App Updates

struct BannerButton: Equatable {
    let label: String
    let url: URL?         // optional — opens this URL (validated)
    let action: String?   // "dismiss" closes the banner; nil = no extra side effect
    let style: String?    // "primary" | "secondary" | nil
}

struct AvailableUpdate: Equatable {
    let version: String
    let title: String
    let body: String
    let buttons: [BannerButton]
}

class UpdateManager: ObservableObject {
    @Published var available: AvailableUpdate?

    // Served directly from the repo via GitHub — free, unlimited, no Vercel meter.
    // Same file as website/latest.json so existing v1.1 users on Vercel see the same JSON.
    private let endpoint = URL(string: "https://raw.githubusercontent.com/Artzainnn/ClaudeUsageBar/main/website/latest.json")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static let allowedHostSuffixes = [
        "github.com",
        "claudeusagebar.com"
    ]

    static func isSafeURL(_ url: URL) -> Bool {
        guard url.scheme == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return allowedHostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) })
    }

    private static func parseButtons(from json: [String: Any]) -> [BannerButton] {
        // Explicit `buttons` array (new schema, supports any combination)
        if let raw = json["buttons"] as? [[String: Any]] {
            return raw.compactMap { dict -> BannerButton? in
                guard let label = dict["label"] as? String, !label.isEmpty else { return nil }
                let urlStr = dict["url"] as? String
                let url = urlStr.flatMap { URL(string: $0) }
                if let url = url, !isSafeURL(url) { return nil }   // reject unsafe URLs
                return BannerButton(
                    label: label,
                    url: url,
                    action: dict["action"] as? String,
                    style: dict["style"] as? String
                )
            }
        }
        // Back-compat: legacy `download_url` builds the default 2-button layout
        if let urlStr = json["download_url"] as? String,
           let url = URL(string: urlStr),
           isSafeURL(url) {
            return [
                BannerButton(label: "Download", url: url, action: nil, style: "primary"),
                BannerButton(label: "Later",    url: nil, action: "dismiss", style: nil)
            ]
        }
        return []
    }

    func fetch() {
        let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = json["version"] as? String,
                  let title = json["title"] as? String,
                  let body = json["description"] as? String else {
                NSLog("⚠️ Update fetch failed or invalid payload")
                return
            }

            let buttons = Self.parseButtons(from: json)

            DispatchQueue.main.async {
                guard self.isNewer(remote: version, than: self.currentVersion) else {
                    self.available = nil
                    return
                }

                let update = AvailableUpdate(version: version, title: title, body: body, buttons: buttons)

                if self.available != update {
                    self.available = update
                    NSLog("⬆️ Update available: \(version)")
                }

                let lastNotified = UserDefaults.standard.string(forKey: "last_notified_update_version")
                // Update notifications fire regardless of usage/status toggles — they're
                // version-once and tied to user-initiated upgrade flow, not noise.
                if lastNotified != version {
                    NotificationService.shared.send(
                        title: "ClaudeUsageBar \(version) is available",
                        body: title
                    )
                    UserDefaults.standard.set(version, forKey: "last_notified_update_version")
                    NSLog("📬 Sent update notification for \(version)")
                }
            }
        }.resume()
    }

    func dismissCurrent() {
        if let v = available?.version {
            UserDefaults.standard.set(v, forKey: "dismissed_update_version")
        }
        available = nil
    }

    var isCurrentDismissed: Bool {
        guard let v = available?.version else { return false }
        return UserDefaults.standard.string(forKey: "dismissed_update_version") == v
    }

    private func isNewer(remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let c = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(r.count, c.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}

// Custom NSTextField that properly handles paste
class CustomTextField: NSTextField {
    var onTextChange: ((String) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if (event.modifierFlags.contains(.command)) {
                switch event.charactersIgnoringModifiers {
                case "v":
                    if let string = NSPasteboard.general.string(forType: .string) {
                        self.stringValue = string
                        onTextChange?(string)
                        NSLog("ClaudeUsage: Pasted text length: \(string.count)")
                        return true
                    }
                case "a":
                    self.currentEditor()?.selectAll(nil)
                    return true
                case "c":
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(self.stringValue, forType: .string)
                    return true
                case "x":
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(self.stringValue, forType: .string)
                    self.stringValue = ""
                    onTextChange?("")
                    return true
                default:
                    break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?(self.stringValue)
    }
}

// Custom TextView that ensures keyboard commands work
class PasteableNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v": // Paste
                paste(nil)
                return true
            case "c": // Copy
                copy(nil)
                return true
            case "x": // Cut
                cut(nil)
                return true
            case "a": // Select All
                selectAll(nil)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// Multi-line text field with proper paste support
struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PasteableNSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true

        // Enable wrapping
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PasteableNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteableTextField

        init(_ parent: PasteableTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// NSVisualEffectView wrapper for native macOS vibrancy / liquid-glass background.
// Behind-window blending dimmed for popups (`.popover`/`.hudWindow`) and the
// settings shell (`.windowBackground`), with a `.sidebar` variant for nav strips.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = emphasized
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
    }
}

// MARK: - Auto-acquire claude.ai cookie

// Probe for an existing Claude Code CLI login. The CLI stores its OAuth bundle
// in the system Keychain under service "Claude Code-credentials". We only check
// for existence — never read the actual token (a) because it's for the API host
// (api.anthropic.com), not the claude.ai web endpoints this app uses, and (b) to
// avoid surfacing a Keychain prompt the user can't act on yet.
enum ClaudeCodeAuthProbe {
    static func detect() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}

// In-app claude.ai login sheet. Hosts a WKWebView, polls its cookie store, and
// emits the full Cookie-header string the moment a `sessionKey` for .claude.ai
// appears. Format matches what the manual paste flow expects so downstream
// fetch code (fetchOrganizationId / fetchUsage) needs no changes.
struct ClaudeLoginSheet: View {
    let onCookieCaptured: (String) -> Void
    let onCancel: () -> Void

    @State private var loading: Bool = true
    @State private var capturing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundColor(.accentColor)
                Text("Sign in to claude.ai")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if loading || capturing {
                    ProgressView().controlSize(.small)
                }
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            ClaudeLoginWebView(
                onCookieCaptured: { cookie in
                    capturing = true
                    onCookieCaptured(cookie)
                },
                onLoadingChange: { loading = $0 }
            )
            .frame(width: 520, height: 640)

            Divider()
            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundColor(.secondary)
                Text("Tip: use email or Apple sign-in. Google sign-in is blocked inside in-app web views by Google.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

// Shared persistent web data store for the login sheet. macOS 14+ supports
// named persistent stores via `.init(forIdentifier:)`; on macOS 12/13 we fall
// back to the default store (still persists across launches, but shared with
// any other webview the app might add later).
enum ClaudeLoginDataStore {
    static let shared: WKWebsiteDataStore = {
        if #available(macOS 14.0, *) {
            // Stable UUID derived from a constant string so the store name is
            // identical across launches and the cookie jar persists.
            let id = UUID(uuidString: "C1A07E10-1234-4DEF-A001-CLAUDELOGIN") ?? UUID()
            return WKWebsiteDataStore(forIdentifier: id)
        }
        return WKWebsiteDataStore.default()
    }()
}

struct ClaudeLoginWebView: NSViewRepresentable {
    let onCookieCaptured: (String) -> Void
    let onLoadingChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieCaptured: onCookieCaptured, onLoadingChange: onLoadingChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = ClaudeLoginDataStore.shared
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = nil // use system Safari UA — better Cloudflare success
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        context.coordinator.webView = webView
        context.coordinator.startCookiePolling()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopCookiePolling()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookieCaptured: (String) -> Void
        let onLoadingChange: (Bool) -> Void
        weak var webView: WKWebView?
        private var pollTimer: Timer?
        private var captured = false

        init(onCookieCaptured: @escaping (String) -> Void,
             onLoadingChange: @escaping (Bool) -> Void) {
            self.onCookieCaptured = onCookieCaptured
            self.onLoadingChange = onLoadingChange
        }

        func startCookiePolling() {
            // Cookies arrive after navigation completes; poll the store every
            // second until a `sessionKey` for .claude.ai shows up. Stop on capture.
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkCookies()
            }
        }

        func stopCookiePolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }

        private func checkCookies() {
            guard !captured, let webView = webView else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.captured else { return }
                let claudeCookies = cookies.filter { c in
                    let d = c.domain.lowercased()
                    return d.hasSuffix("claude.ai")
                }
                guard claudeCookies.contains(where: { $0.name == "sessionKey" }) else { return }
                self.captured = true
                self.stopCookiePolling()
                let serialized = claudeCookies
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                DispatchQueue.main.async {
                    self.onCookieCaptured(serialized)
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChange(true)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChange(false)
            checkCookies()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingChange(false)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingChange(false)
        }
    }
}

struct UsageView: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var statusManager: StatusManager
    @ObservedObject var updateManager: UpdateManager
    var settingsWindowMode: Bool = false
    @State private var sessionCookieInput: String = ""
    @State private var showingCookieInput: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingStatusDetails: Bool = false
    @State private var settingsPage: SettingsTab = .general
    @State private var measuredHeight: CGFloat = 250

    private let maxPopupHeight: CGFloat = 600

    // Resolve the active palette from the user's theme + accent each render.
    var pal: Palette {
        let isDark: Bool
        switch usageManager.theme {
        case .light: isDark = false
        case .dark: isDark = true
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return makePalette(isDark: isDark, accent: usageManager.accent)
    }

    var body: some View {
        if settingsWindowMode {
            windowSettingsScene
                .frame(width: 920, height: 680, alignment: .topLeading)
                .background(
                    VisualEffectBackground(material: .windowBackground, blendingMode: .behindWindow)
                        .ignoresSafeArea()
                )
                .onAppear {
                    if let savedCookie = UserDefaults.standard.string(forKey: "claude_session_cookie") {
                        sessionCookieInput = String(savedCookie.prefix(20)) + "..."
                    }
                    usageManager.updatePercentages()
                }
        } else {
            ScrollView {
                Group {
                    if showingSettings {
                        settingsScene
                    } else {
                        content
                    }
                }
                .padding(showingSettings ? 0 : 16)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(width: showingSettings ? 470 : 440, height: min(max(measuredHeight, 100), maxPopupHeight))
            .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
            .onPreferenceChange(ContentHeightKey.self) { value in
                guard value > 0 else { return }
                measuredHeight = value
            }
            .onAppear {
                if let savedCookie = UserDefaults.standard.string(forKey: "claude_session_cookie") {
                    sessionCookieInput = String(savedCookie.prefix(20)) + "..."
                }
                usageManager.updatePercentages()
            }
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Usage")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(pal.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            // App update / announcement banner
            if let update = updateManager.available, !updateManager.isCurrentDismissed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("⬆️")
                        Text("Version \(update.version) available")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: { updateManager.dismissCurrent() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    Text(update.title)
                        .font(.caption)
                    Text(update.body)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !update.buttons.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(update.buttons.indices, id: \.self) { i in
                                bannerButton(update.buttons[i])
                            }
                        }
                    }
                }
                .padding(8)
                .background(pal.accent.opacity(0.12))
                .cornerRadius(6)
            }

            if let error = usageManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(pal.lvHigh)
                    .padding(.bottom, 8)
            }

            // Only show usage if data has been fetched
            if !usageManager.hasFetchedData {
                Text("👋 Welcome! Set your session cookie below to get started.")
                    .font(.subheadline)
                    .foregroundColor(pal.textSecondary)
                    .padding(.vertical, 8)
            }

            // Usage meters (custom rounded tracks, tier-colored amber → red)
            if usageManager.hasFetchedData {
                meterRow(
                    name: "Session (5 hour)",
                    pct: Int(usageManager.sessionPercentage * 100),
                    reset: usageManager.sessionResetsAt.map { resetLabel($0, includeDate: false) }
                )

                meterRow(
                    name: "Weekly (7 day)",
                    pct: Int(usageManager.weeklyPercentage * 100),
                    reset: usageManager.weeklyResetsAt.map { resetLabel($0, includeDate: true) }
                )

                if usageManager.hasWeeklySonnet {
                    meterRow(
                        name: "Weekly Sonnet (7 day)",
                        pct: Int(usageManager.weeklySonnetPercentage * 100),
                        reset: usageManager.weeklySonnetResetsAt.map { resetLabel($0, includeDate: true) }
                    )
                }
            }

            if usageManager.showServiceStatus && statusManager.hasFetched {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(statusColor(for: statusManager.effectiveIndicator))
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusManager.effectiveIndicator == "none"
                             ? "All Claude services operational"
                             : statusManager.statusDescription)
                            .font(.system(size: 12))
                            .foregroundColor(pal.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let lastCheck = statusManager.lastUpdated {
                            Text("Checked \(relativeTime(lastCheck))")
                                .font(.system(size: 11))
                                .foregroundColor(pal.textMuted)
                        }
                    }
                    Spacer()
                }
            }

            // Support + Settings footer
            HStack(spacing: 14) {
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://donate.stripe.com/3cIcN5b5H7Q8ay8bIDfIs02")!)
                }) {
                    HStack(spacing: 4) {
                        Text("☕")
                        Text("Buy Dev a Coffee")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(pal.accent)

                Spacer()

                Button(action: {
                    (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(pal.textSecondary)
            }
        }
    }

    // MARK: - Usage meter

    func meterRow(name: String, pct: Int, reset: String?) -> some View {
        let p = max(0, min(100, pct))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(pal.textPrimary)
                Spacer()
                if let reset = reset {
                    Text(reset)
                        .font(.system(size: 12))
                        .foregroundColor(pal.textMuted)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(pal.bgInset)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pal.tierColor(p))
                        .frame(width: max(0, geo.size.width * CGFloat(p) / 100.0))
                }
            }
            .frame(height: 8)
            Text("\(p)% used")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(pal.tierColor(p))
        }
    }

    // MARK: - Settings scene (sidebar + 5 pages, mirroring the Rust app IA)

    enum SettingsTab {
        case general, appearance, notifications, account, about

        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Tray & Appearance"
            case .notifications: return "Notifications"
            case .account: return "Account"
            case .about: return "About"
            }
        }
        // Tile colors copied from project/app.js PAGEMETA.
        var tileColor: Color {
            switch self {
            case .general: return Color(hex: 0x5a6b7a)
            case .appearance: return Color(hex: 0xc8603f)
            case .notifications: return Color(hex: 0xe0823a)
            case .account: return Color(hex: 0x8a6db0)
            case .about: return Color(hex: 0x7d8389)
            }
        }
        var sfSymbol: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .notifications: return "bell"
            case .account: return "person"
            case .about: return "info.circle"
            }
        }
    }

    var settingsScene: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { showingSettings = false }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Text("Done")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(pal.accent)
                Spacer()
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(pal.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                settingsSidebar
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                    settingsPageView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    var windowSettingsScene: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                groupLabel("General")
                navItem(.general)
                groupLabel("Appearance")
                navItem(.appearance)
                navItem(.notifications)
                groupLabel("Account")
                navItem(.account)
                navItem(.about)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(width: 200, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
            .overlay(Rectangle().frame(width: 1).foregroundColor(pal.border), alignment: .trailing)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                    settingsPageView
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            groupLabel("General")
            navItem(.general)
            groupLabel("Appearance")
            navItem(.appearance)
            navItem(.notifications)
            groupLabel("Account")
            navItem(.account)
            navItem(.about)
        }
        .padding(10)
        .frame(width: 150, alignment: .topLeading)
        .background(pal.bgInset)
        .overlay(Rectangle().frame(width: 1).foregroundColor(pal.border), alignment: .trailing)
    }

    func navItem(_ tab: SettingsTab) -> some View {
        let active = settingsPage == tab
        return Button(action: { settingsPage = tab }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color.white.opacity(0.25) : tab.tileColor)
                        .frame(width: 30, height: 30)
                    Image(systemName: tab.sfSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(active ? pal.onAccent : pal.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? pal.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var pageHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(settingsPage.tileColor)
                        .frame(width: 38, height: 38)
                    Image(systemName: settingsPage.sfSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(settingsPage.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(pal.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            Divider()
        }
    }

    @ViewBuilder
    var settingsPageView: some View {
        switch settingsPage {
        case .general: generalPage
        case .appearance: appearancePage
        case .notifications: notificationsPage
        case .account: accountPage
        case .about: aboutPage
        }
    }

    var generalPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Startup")
            settingRow("Launch at login", "Open Usage Bar automatically when you sign in") {
                toggleSwitch(usageManager.openAtLogin) { v in
                    usageManager.openAtLogin = v
                    usageManager.saveSettings()
                }
            }
            settingRow("Check for updates automatically", "Look for a new version of Usage Bar in the background") {
                toggleSwitch(usageManager.autoCheckForUpdates) { v in
                    usageManager.autoCheckForUpdates = v
                    usageManager.saveSettings()
                    (NSApplication.shared.delegate as? AppDelegate)?.rescheduleUpdateCheckTimer()
                }
            }

            groupLabel("Appearance")
            settingRow("Theme", "Match your system or pick a side") {
                segmentedControl(
                    [("light", "Light"), ("dark", "Dark"), ("system", "System")],
                    selected: usageManager.theme.rawValue
                ) { v in
                    usageManager.theme = AppTheme(rawValue: v) ?? .system
                    usageManager.saveSettings()
                    usageManager.refreshTray()
                    (NSApplication.shared.delegate as? AppDelegate)?.applyAppearanceToWindows()
                }
            }

            groupLabel("Data")
            settingRow("Refresh interval", "How often usage is pulled") {
                segmentedControl(
                    [("60", "1m"), ("300", "5m"), ("900", "15m")],
                    selected: String(usageManager.refreshIntervalSeconds)
                ) { v in
                    usageManager.refreshIntervalSeconds = Int(v) ?? 300
                    usageManager.saveSettings()
                    (NSApplication.shared.delegate as? AppDelegate)?.rescheduleRefreshTimer()
                }
            }
            settingRow("Show service status", "Display Claude status line in the popover") {
                toggleSwitch(usageManager.showServiceStatus) { v in
                    usageManager.showServiceStatus = v
                    usageManager.saveSettings()
                }
            }

            groupLabel("Input")
            settingRow("Global hotkey (⌘U)", "Toggle the popover from anywhere") {
                toggleSwitch(usageManager.shortcutEnabled) { v in
                    usageManager.shortcutEnabled = v
                    usageManager.saveSettings()
                    (NSApplication.shared.delegate as? AppDelegate)?.setShortcutEnabled(v)
                }
            }
            if usageManager.shortcutEnabled && !usageManager.isAccessibilityEnabled {
                pillButton("Grant Accessibility Permission", primary: true) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }

    var appearancePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("Tray icon")
            settingRow("Show percentage in tray", "Display the busiest limit as a number") {
                toggleSwitch(usageManager.showPercentInTray) { v in
                    usageManager.showPercentInTray = v
                    usageManager.saveSettings()
                    usageManager.refreshTray()
                }
            }
            settingRow("Show session reset time", "Append the 5-hour session countdown, e.g. 3h10m") {
                toggleSwitch(usageManager.showTimeInTray) { v in
                    usageManager.showTimeInTray = v
                    usageManager.saveSettings()
                    usageManager.refreshTray()
                }
            }
            groupLabel("Icon style")
            HStack(spacing: 8) {
                iconStyleCard(.number, "Dot")
                iconStyleCard(.ring, "Ring")
                iconStyleCard(.mark, "Mark")
            }
            groupLabel("Accent palette")
            HStack(spacing: 10) {
                accentSwatch(.warm, Color(hex: 0xe0a84a), Color(hex: 0xd4583a))
                accentSwatch(.cool, Color(hex: 0x36c97a), Color(hex: 0xe0613e))
                accentSwatch(.coral, Color(hex: 0xcf9168), Color(hex: 0xbd5238))
                accentSwatch(.mono, Color(hex: 0x9aa0a6), Color(hex: 0x5f656b))
                Spacer()
            }
            Text("Bars shade from amber → red as a limit fills. The palette sets the family.")
                .font(.system(size: 12))
                .foregroundColor(pal.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var notificationsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("Alerts")
            settingRow("Enable notifications", "Warn you before you hit a limit") {
                toggleSwitch(usageManager.usageNotificationsEnabled) { v in
                    usageManager.usageNotificationsEnabled = v
                    usageManager.saveSettings()
                }
            }
            settingRow("Service status notifications", "Ping when Claude status changes") {
                toggleSwitch(usageManager.statusNotificationsEnabled) { v in
                    usageManager.statusNotificationsEnabled = v
                    usageManager.saveSettings()
                }
            }
            settingRow("Session warning at", "Notify when your 5-hour limit reaches") {
                segmentedControl(
                    [("75", "75%"), ("85", "85%"), ("95", "95%")],
                    selected: "\(usageManager.sessionWarnThreshold)"
                ) { v in
                    usageManager.sessionWarnThreshold = Int(v) ?? 85
                    usageManager.saveSettings()
                }
            }
            settingRow("Weekly warning at", "Notify when your 7-day limit reaches") {
                segmentedControl(
                    [("80", "80%"), ("90", "90%"), ("95", "95%")],
                    selected: "\(usageManager.weeklyWarnThreshold)"
                ) { v in
                    usageManager.weeklyWarnThreshold = Int(v) ?? 90
                    usageManager.saveSettings()
                }
            }
            groupLabel("Custom message")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Tokens:").font(.system(size: 11)).foregroundColor(pal.textMuted)
                    kbd("{pct}")
                    kbd("{limit}")
                    kbd("{reset}")
                }
                TextEditor(text: Binding(
                    get: { usageManager.notifMessageTemplate },
                    set: { newValue in
                        usageManager.notifMessageTemplate = String(newValue.prefix(160))
                        usageManager.saveSettings()
                    }
                ))
                .font(.system(size: 13))
                .foregroundColor(pal.textPrimary)
                .frame(height: 64)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(pal.bgInset))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.border, lineWidth: 1))
                Text("\(usageManager.notifMessageTemplate.count)/160")
                    .font(.system(size: 11))
                    .foregroundColor(pal.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            pillButton("Preview notification", primary: true) {
                usageManager.sendTestNotification()
            }
            groupLabel("Status alerts: services to track")
            ForEach(statusManager.allComponents) { component in
                settingRow(component.name, nil) {
                    toggleSwitch(statusManager.isTracked(component.id)) { _ in
                        statusManager.toggleComponent(component.id)
                    }
                }
            }
        }
    }

    var accountPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usageManager.hasFetchedData {
                groupLabel("Signed in")
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(pal.accent).frame(width: 36, height: 36)
                        Image(systemName: "sparkle").foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected to claude.ai")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(pal.textPrimary)
                        Text("Session cookie stored on this Mac.")
                            .font(.system(size: 12))
                            .foregroundColor(pal.textMuted)
                    }
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(pal.bgCard))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(pal.border, lineWidth: 1))

                HStack(spacing: 8) {
                    pillButton("Sign out", primary: false) {
                        sessionCookieInput = ""
                        usageManager.clearSessionCookie()
                    }
                    pillButton("Open claude.ai", primary: false) {
                        NSWorkspace.shared.open(URL(string: "https://claude.ai")!)
                    }
                    Spacer()
                }
            } else {
                signedOutAccountSection
            }
        }
    }

    @State private var showingLoginSheet: Bool = false
    @State private var pasteCookieExpanded: Bool = false
    @State private var claudeCodeDetected: Bool = false

    var signedOutAccountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            groupLabel("Account")
            Text("Sign in to claude.ai to read your usage limits. No data leaves your Mac.")
                .font(.system(size: 13))
                .foregroundColor(pal.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                pillButton("Sign in with claude.ai", primary: true) {
                    showingLoginSheet = true
                }
                pillButton("Open claude.ai", primary: false) {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai")!)
                }
                Spacer()
            }

            if claudeCodeDetected {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "terminal")
                        .foregroundColor(pal.accent)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code login detected")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(pal.textPrimary)
                        Text("API-token sign-in via Claude Code is on the roadmap. For now, use the claude.ai sign-in above.")
                            .font(.system(size: 12))
                            .foregroundColor(pal.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(pal.bgInset))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.border, lineWidth: 1))
            }

            DisclosureGroup(isExpanded: $pasteCookieExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    PasteableTextField(text: $sessionCookieInput, placeholder: "Paste full Cookie header here…")
                        .frame(height: 60)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(pal.bgInset))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.border, lineWidth: 1))
                    Text("How: claude.ai → DevTools (F12) → Network tab → open any /api/organizations/* request → copy the entire Cookie header.")
                        .font(.system(size: 12))
                        .foregroundColor(pal.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        pillButton("Save cookie", primary: true) {
                            if !sessionCookieInput.isEmpty {
                                usageManager.saveSessionCookie(sessionCookieInput)
                                usageManager.fetchUsage()
                            }
                        }
                        Spacer()
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Paste cookie manually")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(pal.textSecondary)
            }
        }
        .onAppear {
            claudeCodeDetected = ClaudeCodeAuthProbe.detect()
        }
        .sheet(isPresented: $showingLoginSheet) {
            ClaudeLoginSheet(
                onCookieCaptured: { cookie in
                    usageManager.saveSessionCookie(cookie)
                    usageManager.fetchUsage()
                    showingLoginSheet = false
                },
                onCancel: { showingLoginSheet = false }
            )
        }
    }

    var aboutPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(pal.accent).frame(width: 44, height: 44)
                    Image(systemName: "sparkle").font(.system(size: 20)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage Bar")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(pal.textPrimary)
                    Text("ClaudeUsageBar for macOS")
                        .font(.system(size: 12))
                        .foregroundColor(pal.textMuted)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            groupLabel("App")
            settingRow("Website", nil) {
                pillButton("Visit", primary: false) {
                    NSWorkspace.shared.open(URL(string: "https://claudeusagebar.com")!)
                }
            }
            settingRow("Source code", nil) {
                pillButton("GitHub", primary: false) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Artzainnn/ClaudeUsageBar")!)
                }
            }
            groupLabel("License")
            Text("MIT. Made for macOS, Windows & Linux. Not affiliated with Anthropic.")
                .font(.system(size: 12))
                .foregroundColor(pal.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Settings components

    func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(pal.textMuted)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    func settingRow<Trailing: View>(
        _ title: String,
        _ subtitle: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(pal.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(pal.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(pal.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(pal.border, lineWidth: 1))
    }

    func toggleSwitch(_ value: Bool, _ onChange: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { value }, set: { onChange($0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(pal.accent)
    }

    func segmentedControl(
        _ options: [(String, String)],
        selected: String,
        onPick: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt in
                let active = opt.0 == selected
                Text(opt.1)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(active ? pal.onAccent : pal.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(active ? pal.accent : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(opt.0) }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(pal.bgInset))
    }

    func iconStyleCard(_ style: TrayIconStyle, _ label: String) -> some View {
        let selected = usageManager.trayIconStyle == style
        return VStack(spacing: 8) {
            iconStylePreview(style).frame(height: 26)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(pal.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? pal.bgInset : pal.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? pal.accent : pal.border, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            usageManager.trayIconStyle = style
            usageManager.saveSettings()
            usageManager.refreshTray()
        }
    }

    @ViewBuilder
    func iconStylePreview(_ style: TrayIconStyle) -> some View {
        switch style {
        case .number:
            Circle().fill(pal.lvMid).frame(width: 10, height: 10)
        case .ring:
            ZStack {
                Circle().stroke(pal.borderStrong, lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(pal.lvMid, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
        case .mark:
            Image(systemName: "sparkle").font(.system(size: 18)).foregroundColor(pal.lvMid)
        }
    }

    func accentSwatch(_ acc: Accent, _ c1: Color, _ c2: Color) -> some View {
        let selected = usageManager.accent == acc
        return RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(
                stops: [.init(color: c1, location: 0.5), .init(color: c2, location: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: 30, height: 30)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? pal.accent : pal.border, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
            .onTapGesture {
                usageManager.accent = acc
                usageManager.saveSettings()
                usageManager.refreshTray()
            }
    }

    func kbd(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(pal.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(pal.bgCardAlt))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(pal.border, lineWidth: 1))
    }

    func pillButton(_ label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(primary ? pal.onAccent : pal.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(primary ? pal.accent : pal.bgInset))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(primary ? Color.clear : pal.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // Reset label combining the absolute time and the remaining time, e.g.
    // "Resets at 19:20 · in 1h 10m" or "Resets on 13 Jun 2026 at 9:00 PM · in 3d 1h 20m".
    func resetLabel(_ date: Date, includeDate: Bool) -> String {
        let base = "Resets \(formatResetTime(date, includeDate: includeDate))"
        if let remaining = formatTimeRemaining(date) {
            return "\(base) · in \(remaining)"
        }
        return base
    }

    // Human-readable remaining time, e.g. "1h 10m" / "3d 1h 20m" / "45m".
    // Returns nil if the date is in the past.
    func formatTimeRemaining(_ date: Date) -> String? {
        let total = Int(date.timeIntervalSinceNow)
        if total <= 0 { return nil }
        let minutes = (total / 60) % 60
        let hours = (total / 3600) % 24
        let days = total / 86400
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(days)d \(minutes)m"
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    func formatResetTime(_ date: Date, includeDate: Bool = false) -> String {
        let formatter = DateFormatter()

        if includeDate {
            // Format: "on 13/06 at 20:59"
            formatter.dateFormat = "dd/MM 'at' HH:mm"
            return "on \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "HH:mm"
            return "at \(formatter.string(from: date))"
        }
    }

    func colorForPercentage(_ percentage: Double) -> Color {
        return pal.tierColor(Int(percentage * 100))
    }

    func statusColor(for indicator: String) -> Color {
        switch indicator {
        case "none":     return Color(hex: 0x35c46b)
        case "minor":    return pal.lvMid
        case "major":    return pal.lvHigh
        case "critical": return pal.lvCrit
        default:         return pal.textMuted
        }
    }

    func statusLabel(for indicator: String, description: String) -> String {
        if indicator == "none" {
            return "Claude: all systems operational"
        }
        return "Claude: \(description)"
    }

    func relativeTime(_ date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 {
            let m = elapsed / 60
            return "\(m) min\(m == 1 ? "" : "s") ago"
        }
        if elapsed < 86_400 {
            let h = elapsed / 3600
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        let d = elapsed / 86_400
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }

    func statusContextLine(for sm: StatusManager) -> String {
        let tracked = sm.allComponents.filter { sm.selectedComponentIds.contains($0.id) }
        let trackedNames = tracked.prefix(4).map { shortName($0.name) }.joined(separator: ", ")
        let extra = tracked.count > 4 ? " +\(tracked.count - 4)" : ""
        let trackedSummary = tracked.isEmpty ? "No services tracked" : "Tracks \(trackedNames)\(extra)"

        if sm.effectiveIndicator == "none" {
            if let lastCheck = sm.lastUpdated {
                return "\(trackedSummary) · checked \(relativeTime(lastCheck))"
            }
            return trackedSummary
        }
        let affected = sm.filteredAffectedComponents
        if !affected.isEmpty {
            let names = affected.prefix(3).map { shortName($0.name) }.joined(separator: ", ")
            let more = affected.count > 3 ? " +\(affected.count - 3)" : ""
            return "Affects: \(names)\(more)"
        }
        if let lastCheck = sm.lastUpdated {
            return "Checked \(relativeTime(lastCheck))"
        }
        return ""
    }

    func shortName(_ raw: String) -> String {
        if let paren = raw.range(of: " (") {
            return String(raw[..<paren.lowerBound])
        }
        return raw
    }

    @ViewBuilder
    func bannerButton(_ btn: BannerButton) -> some View {
        let tap = {
            if let url = btn.url {
                NSWorkspace.shared.open(url)
            }
            if btn.action == "dismiss" {
                updateManager.dismissCurrent()
            }
        }
        if btn.style == "primary" {
            Button(btn.label, action: tap)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Button(btn.label, action: tap)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    func badgeColor(for status: String) -> Color {
        switch status {
        case "investigating": return pal.lvHigh
        case "identified":    return pal.lvMid
        case "monitoring":    return pal.accent
        case "resolved":      return Color(hex: 0x35c46b)
        default:              return pal.textMuted
        }
    }

    func componentLabel(_ status: String) -> String {
        switch status {
        case "degraded_performance": return "degraded"
        case "partial_outage":       return "partial outage"
        case "major_outage":         return "major outage"
        case "under_maintenance":    return "maintenance"
        default:                     return status
        }
    }

}
