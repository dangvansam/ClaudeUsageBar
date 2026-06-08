import SwiftUI
import AppKit
import WebKit
import Carbon

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

// Tray color uses the 3-tier ramp (low/mid/high) keyed by session percent, matching
// the Rust app's icon.rs HealthTier (>=87 high, >=70 mid, else low).
func trayTierNSColor(_ pct: Int, _ accent: Accent) -> NSColor {
    let (low, mid, high, _) = accentRamp(accent)
    let hex: UInt32 = pct >= 87 ? high : (pct >= 70 ? mid : low)
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

// Main entry point
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var usageManager: UsageManager!
    var statusManager: StatusManager!
    var updateManager: UpdateManager!
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSUserNotification (deprecated but works without permissions for unsigned apps)
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

        // Create popover
        popover = NSPopover()
        // Initial guess; SwiftUI's intrinsic size (capped at 600) will drive the actual size.
        popover.contentSize = NSSize(width: 360, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: UsageView(
            usageManager: usageManager,
            statusManager: statusManager,
            updateManager: updateManager
        ))

        // Fetch initial data
        usageManager.fetchUsage()
        statusManager.fetch()
        updateManager.fetch()

        // Usage + Anthropic status are time-sensitive — poll every 5 min.
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            self.usageManager.fetchUsage()
            self.statusManager.fetch()
        }

        // App updates are infrequent (new release at most weekly) — poll every 3 hours.
        Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { _ in
            self.updateManager.fetch()
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

    @objc func togglePopover() {
        if popover.isShown {
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
        if let button = statusItem.button {
            // Force UI refresh by updating percentages
            DispatchQueue.main.async {
                self.usageManager.updatePercentages()
            }

            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Add event monitor to detect clicks outside the popover
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if self?.popover.isShown == true {
                    self?.closePopover()
                }
            }
        }
    }

    func closePopover() {
        popover.performClose(nil)

        // Remove event monitor
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
        if let manager = usageManager {
            style = manager.trayIconStyle
            accent = manager.accent
            showPct = manager.showPercentInTray
        } else {
            style = .mark
            accent = .warm
            showPct = true
        }

        // Color tracks the session tier (amber → red), replacing green/yellow/red.
        let color = trayTierNSColor(percentage, accent)

        // Number style with the percentage hidden has nothing to show → Mark.
        let effective: TrayIconStyle = (style == .number && !showPct) ? .mark : style

        switch effective {
        case .ring:
            button.image = createRingIcon(color: color, percentage: percentage)
            button.title = showPct ? " \(percentage)%" : ""
        case .mark:
            button.image = createSparkIcon(color: color)
            button.title = ""
        case .number:
            button.image = createSparkIcon(color: color)
            button.title = " \(percentage)%"
        }
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
        let notification = NSUserNotification()
        notification.title = "Claude Usage Alert"
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    func sendTestNotification() {
        sendUsageNotification(
            pct: sessionWarnThreshold,
            limit: "session",
            reset: relativeResetText(sessionResetsAt)
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

        let notification = NSUserNotification()
        if indicator == "none" {
            notification.title = "Claude is back online"
            notification.informativeText = "All systems operational"
        } else {
            notification.title = "Claude status: \(description)"
            notification.informativeText = "Visit status.anthropic.com for details"
        }
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
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
                    let n = NSUserNotification()
                    n.title = "ClaudeUsageBar \(version) is available"
                    n.informativeText = title
                    n.soundName = NSUserNotificationDefaultSoundName
                    NSUserNotificationCenter.default.deliver(n)
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

struct UsageView: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var statusManager: StatusManager
    @ObservedObject var updateManager: UpdateManager
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
        .frame(width: showingSettings ? 470 : 360, height: min(max(measuredHeight, 100), maxPopupHeight))
        .background(pal.bgStage)
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
                    reset: usageManager.sessionResetsAt.map { "Resets \(formatResetTime($0))" }
                )

                meterRow(
                    name: "Weekly (7 day)",
                    pct: Int(usageManager.weeklyPercentage * 100),
                    reset: usageManager.weeklyResetsAt.map { "Resets \(formatResetTime($0, includeDate: true))" }
                )

                if usageManager.hasWeeklySonnet {
                    meterRow(
                        name: "Weekly Sonnet (7 day)",
                        pct: Int(usageManager.weeklySonnetPercentage * 100),
                        reset: usageManager.weeklySonnetResetsAt.map { "Resets \(formatResetTime($0, includeDate: true))" }
                    )
                }
            }

            if statusManager.hasFetched {
                Divider()
            }

            // Anthropic service status (compact; expandable on issue)
            if statusManager.hasFetched {
                let effective = statusManager.effectiveIndicator
                let filteredIncidents = statusManager.filteredIncidents
                let filteredAffected = statusManager.filteredAffectedComponents
                let hasIssue = effective != "none"
                    && (!filteredIncidents.isEmpty || !filteredAffected.isEmpty)

                VStack(alignment: .leading, spacing: 8) {
                    // Compact header row
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(statusColor(for: effective))
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(effective == "none"
                                 ? "All Claude services operational"
                                 : statusManager.statusDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(statusContextLine(for: statusManager))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if hasIssue {
                            Button(action: { showingStatusDetails.toggle() }) {
                                HStack(spacing: 2) {
                                    Text(showingStatusDetails ? "Hide" : "Details")
                                    Image(systemName: showingStatusDetails ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    // Expanded panel
                    if hasIssue && showingStatusDetails {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredIncidents) { incident in
                                VStack(alignment: .leading, spacing: 6) {
                                    // Title
                                    Text(incident.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .fixedSize(horizontal: false, vertical: true)

                                    // Status badge + updated time
                                    HStack(spacing: 8) {
                                        Text(incident.status.uppercased())
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(badgeColor(for: incident.status))
                                            .cornerRadius(3)
                                        if let updated = incident.updatedAt {
                                            Text("Updated \(relativeTime(updated))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    // Body
                                    if !incident.latestUpdate.isEmpty {
                                        Text(incident.latestUpdate)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .padding(.top, 2)
                                    }
                                }
                            }

                            // Affected components (when no formal incident)
                            if filteredIncidents.isEmpty && !filteredAffected.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Affected services")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    ForEach(filteredAffected) { c in
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(pal.lvMid)
                                                .frame(width: 5, height: 5)
                                            Text(c.name).font(.caption2)
                                            Spacer()
                                            Text(componentLabel(c.status))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }

                            Divider()

                            HStack {
                                if let lastCheck = statusManager.lastUpdated {
                                    Text("Checked \(relativeTime(lastCheck))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    NSWorkspace.shared.open(URL(string: "https://status.claude.com")!)
                                }) {
                                    Text("Open status page →")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(10)
                        .background(pal.lvMid.opacity(0.12))
                        .cornerRadius(6)
                    }
                }
            }

            if usageManager.hasFetchedData {
            Divider()

            HStack {
                Text("Last updated: \(formatTime(usageManager.lastUpdated))")
                    .font(.caption)
                    .foregroundColor(pal.textMuted)
                Spacer()
                Button("Refresh") {
                    usageManager.fetchUsage()
                    statusManager.fetch()
                    updateManager.fetch()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(pal.accent)
            }
            }

            Button(showingCookieInput ? "Hide Cookie" : "Set Session Cookie") {
                showingCookieInput.toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)

            if showingCookieInput {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("How to get your session cookie:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/Artzainnn/ClaudeUsageBar/blob/main/setup-guide.png")!)
                        }) {
                            Text("View tutorial →")
                                .font(.caption2)
                                .foregroundColor(pal.accent)
                        }
                        .buttonStyle(.borderless)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Go to Settings > Usage on claude.ai")
                        Text("2. Press F12 (or Cmd+Option+I)")
                        Text("3. Go to Network tab")
                        Text("4. Refresh page, click 'usage' request")
                        Text("5. Find 'Cookie' in Request Headers")
                        Text("6. Copy full cookie value\n   (starts with anthropic-device-id=...)")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paste full cookie string:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        VStack(spacing: 4) {
                            PasteableTextField(text: $sessionCookieInput, placeholder: "Paste cookie here...")
                                .frame(height: 60)
                                .cornerRadius(4)

                            HStack(spacing: 8) {
                                Button("Save Cookie & Fetch") {
                                    NSLog("ClaudeUsage: Save clicked, input length: \(sessionCookieInput.count)")
                                    if sessionCookieInput.isEmpty {
                                        usageManager.errorMessage = "Cookie field is empty!"
                                    } else {
                                        usageManager.saveSessionCookie(sessionCookieInput)
                                        usageManager.fetchUsage()
                                        usageManager.errorMessage = "Cookie saved, fetching..."
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                if usageManager.hasFetchedData {
                                    Button("Clear Cookie") {
                                        sessionCookieInput = ""
                                        usageManager.clearSessionCookie()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
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

                Button(action: { showingSettings = true }) {
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
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color.white.opacity(0.22) : tab.tileColor)
                        .frame(width: 22, height: 22)
                    Image(systemName: tab.sfSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(active ? pal.onAccent : pal.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? pal.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var pageHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(settingsPage.tileColor)
                        .frame(width: 26, height: 26)
                    Image(systemName: settingsPage.sfSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(settingsPage.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(pal.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 8) {
            groupLabel("Startup")
            settingRow("Launch at login", "Open Usage Bar automatically when you sign in") {
                toggleSwitch(usageManager.openAtLogin) { v in
                    usageManager.openAtLogin = v
                    usageManager.saveSettings()
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
            groupLabel("Icon style")
            HStack(spacing: 8) {
                iconStyleCard(.number, "Number")
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
        VStack(alignment: .leading, spacing: 8) {
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
            } else {
                groupLabel("Account")
                Text("Not signed in — paste your claude.ai cookie below.")
                    .font(.system(size: 13))
                    .foregroundColor(pal.textSecondary)
            }
            groupLabel("Session cookie")
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
                pillButton("Open claude.ai", primary: false) {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai")!)
                }
                Spacer()
                if usageManager.hasFetchedData {
                    pillButton("Sign out", primary: false) {
                        sessionCookieInput = ""
                        usageManager.clearSessionCookie()
                    }
                }
            }
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(pal.textMuted)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    func settingRow<Trailing: View>(
        _ title: String,
        _ subtitle: String?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(pal.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(pal.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(pal.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(pal.border, lineWidth: 1))
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
            Text("82%").font(.system(size: 13, weight: .bold)).foregroundColor(pal.lvMid)
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

    func formatResetTime(_ date: Date, includeDate: Bool = false) -> String {
        let formatter = DateFormatter()

        if includeDate {
            // Format: "on 31 Jan 2026 at 7:59 AM"
            formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
            return "on \(formatter.string(from: date))"
        } else {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
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
