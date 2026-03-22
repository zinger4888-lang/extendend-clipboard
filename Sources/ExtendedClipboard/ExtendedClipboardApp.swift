import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import UniformTypeIdentifiers

private enum ClipboardMenuDisplay {
    static let primaryLimit = 10
    static let secondaryLimit = 20
    static let estimatedItemHeight: CGFloat = 24
    static let estimatedMenuPadding: CGFloat = 18
}

@main
struct ExtendedClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ClipboardStore.shared
    @StateObject private var coordinator = ClipboardCoordinator.shared
    @StateObject private var preferences = ClipboardPreferences.shared

    var body: some Scene {
        MenuBarExtra("", systemImage: "list.clipboard.fill") {
            ClipboardMenu(store: store, coordinator: coordinator, preferences: preferences)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ClipboardCoordinator.shared.start()
    }
}

struct ClipboardMenu: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var coordinator: ClipboardCoordinator
    @ObservedObject var preferences: ClipboardPreferences

    var body: some View {
        Group {
            if !coordinator.accessGranted {
                Text("Accessibility Access Required")
                    .font(.headline)

                Text("Without it, the app cannot intercept Cmd+V and show the panel next to the input field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Settings") {
                    coordinator.requestAccess()
                }

                Divider()
            }

            if store.items.isEmpty {
                Text("Copy some text and it will appear here")
            } else {
                ForEach(Array(primaryItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        store.copyToClipboard(item)
                    } label: {
                        Text(menuTitle(for: item, index: index))
                    }
                    .applyShortcutIfNeeded(for: index)
                }

                if !secondaryItems.isEmpty {
                    Menu("See More") {
                        ForEach(Array(secondaryItems.enumerated()), id: \.element.id) { offset, item in
                            Button {
                                store.copyToClipboard(item)
                            } label: {
                                Text(menuTitle(for: item, index: offset + ClipboardMenuDisplay.primaryLimit))
                            }
                        }
                    }
                }
            }

            Divider()

            Button(orderToggleTitle) {
                preferences.toggleSortOrder()
            }

            Button("Clear History") {
                store.clear()
            }
            .disabled(store.items.isEmpty)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            coordinator.refreshAccessStatus()
        }
    }

    private func menuTitle(for item: ClipboardItem, index: Int) -> String {
        let shortcut = index < 9 ? "\(index + 1). " : ""
        return shortcut + item.preview
    }

    private var orderedItems: [ClipboardItem] {
        preferences.sortedItems(from: store.items)
    }

    private var primaryItems: ArraySlice<ClipboardItem> {
        orderedItems.prefix(ClipboardMenuDisplay.primaryLimit)
    }

    private var secondaryItems: ArraySlice<ClipboardItem> {
        orderedItems
            .dropFirst(ClipboardMenuDisplay.primaryLimit)
            .prefix(ClipboardMenuDisplay.secondaryLimit - ClipboardMenuDisplay.primaryLimit)
    }

    private var orderToggleTitle: String {
        switch preferences.sortOrder {
        case .newestFirst:
            "Order: Top to Bottom"
        case .oldestFirst:
            "Order: Bottom to Top"
        case .automatic:
            "Order: Auto"
        }
    }
}

@MainActor
final class ClipboardCoordinator: ObservableObject {
    static let shared = ClipboardCoordinator(store: .shared)

    @Published private(set) var accessGranted = false

    private let store: ClipboardStore
    private let popupMenuController: ClipboardPopupMenuController
    private let preferences: ClipboardPreferences
    private lazy var hotkeyMonitor = PasteHotkeyMonitor { [weak self] in
        self?.presentPicker()
    }
    private var lastTargetApp: NSRunningApplication?

    private init(store: ClipboardStore) {
        self.store = store
        self.preferences = .shared
        self.popupMenuController = ClipboardPopupMenuController(store: store, preferences: preferences)
        popupMenuController.onSelect = { [weak self] item in
            self?.selectAndPaste(item)
        }
        popupMenuController.onClose = { [weak self] in
            self?.closePicker()
        }
    }

    func start() {
        refreshAccessStatus()
        if accessGranted {
            hotkeyMonitor.start()
        }
    }

    func requestAccess() {
        refreshAccessStatus()
        if accessGranted {
            hotkeyMonitor.start()
            return
        }

        Self.openAccessibilitySettings()
    }

    func refreshAccessStatus() {
        accessGranted = Self.checkAccessibility(prompt: false)
        if accessGranted {
            hotkeyMonitor.start()
        }
    }

    func presentPicker() {
        refreshAccessStatus()

        guard accessGranted else {
            return
        }

        store.refreshFromSystemPasteboard()

        lastTargetApp = NSWorkspace.shared.frontmostApplication

        guard !store.items.isEmpty else {
            return
        }

        let anchor = AccessibilityLocator.bestAvailableAnchorRect()
        NSApp.activate(ignoringOtherApps: true)
        popupMenuController.present(anchoredTo: anchor)
    }

    func closePicker() {
        popupMenuController.dismiss()
    }

    private func selectAndPaste(_ item: ClipboardItem) {
        store.copyToClipboard(item)
        popupMenuController.dismiss()

        guard let targetApp = lastTargetApp else {
            return
        }

        targetApp.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.hotkeyMonitor.skipNextPasteShortcut()
            Self.simulatePaste()
        }
    }

    private static func checkAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private static func simulatePaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var observedChangeCount: Int
    private var timer: Timer?
    private let maxItems = 20
    private(set) var latestSnapshot: ClipboardPasteboardSnapshot

    private init() {
        observedChangeCount = pasteboard.changeCount
        latestSnapshot = ClipboardPasteboardSnapshot.capture(from: pasteboard)
        startMonitoring()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.value, forType: .string)
        observedChangeCount = pasteboard.changeCount
        refreshTimestamp(for: item.id)
    }

    func clear() {
        items.removeAll()
    }

    func refreshFromSystemPasteboard() {
        observedChangeCount = pasteboard.changeCount
        latestSnapshot = ClipboardPasteboardSnapshot.capture(from: pasteboard)

        guard case let .text(value) = latestSnapshot.kind else {
            return
        }

        ingestTextValue(value)
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureLatestClipboardValue()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func captureLatestClipboardValue() {
        guard pasteboard.changeCount != observedChangeCount else {
            return
        }

        observedChangeCount = pasteboard.changeCount
        latestSnapshot = ClipboardPasteboardSnapshot.capture(from: pasteboard)

        guard case let .text(value) = latestSnapshot.kind else { return }
        ingestTextValue(value)
    }

    private func refreshTimestamp(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let reused = items.remove(at: index)
        items.insert(ClipboardItem(id: reused.id, value: reused.value, copiedAt: .now), at: 0)
    }

    private func ingestTextValue(_ value: String) {
        if let first = items.first, first.value == value {
            return
        }

        items.removeAll { $0.value == value }
        items.insert(ClipboardItem(value: value), at: 0)

        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }
}

@MainActor
final class ClipboardPopupMenuController: NSObject {
    var onSelect: ((ClipboardItem) -> Void)?
    var onClose: (() -> Void)?

    private let store: ClipboardStore
    private let preferences: ClipboardPreferences
    private var currentMenu: NSMenu?
    private var didTriggerSelection = false

    init(store: ClipboardStore, preferences: ClipboardPreferences) {
        self.store = store
        self.preferences = preferences
    }

    func present(anchoredTo anchorRect: CGRect) {
        let presentation = contextMenuPresentation(using: anchorRect)
        let menu = buildMenu(opensUpward: presentation.opensUpward)
        currentMenu = menu
        didTriggerSelection = false

        menu.popUp(positioning: menu.items.first, at: presentation.point, in: nil)

        currentMenu = nil

        if !didTriggerSelection {
            onClose?()
        }
    }

    func dismiss() {
        currentMenu?.cancelTracking()
        currentMenu = nil
    }

    private struct PopupPresentation {
        let point: NSPoint
        let opensUpward: Bool
    }

    private func contextMenuPresentation(using anchorRect: CGRect) -> PopupPresentation {
        let mouse = NSEvent.mouseLocation
        let anchorDistance = hypot(anchorRect.midX - mouse.x, anchorRect.midY - mouse.y)
        let point: NSPoint
        let opensUpward: Bool

        if anchorDistance <= 24 {
            point = NSPoint(x: mouse.x + 3, y: mouse.y + 1)
            opensUpward = shouldOpenUpward(near: mouse)
        } else {
            let anchorPoint = CGPoint(x: anchorRect.maxX, y: anchorRect.midY)
            point = NSPoint(x: anchorRect.maxX + 3, y: anchorRect.midY)
            opensUpward = shouldOpenUpward(near: anchorPoint)
        }

        return PopupPresentation(
            point: point,
            opensUpward: opensUpward
        )
    }

    private func buildMenu(opensUpward: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let orderedItems = preferences.sortedPopupItems(from: store.items, opensUpward: opensUpward)

        for (index, item) in orderedItems.prefix(ClipboardMenuDisplay.primaryLimit).enumerated() {
            menu.addItem(makeClipboardMenuItem(for: item, index: index))
        }

        let overflowItems = Array(
            orderedItems
                .dropFirst(ClipboardMenuDisplay.primaryLimit)
                .prefix(ClipboardMenuDisplay.secondaryLimit - ClipboardMenuDisplay.primaryLimit)
        )

        if !overflowItems.isEmpty {
            let overflowMenuItem = NSMenuItem(title: "See More", action: nil, keyEquivalent: "")
            let overflowMenu = NSMenu()

            for (offset, item) in overflowItems.enumerated() {
                overflowMenu.addItem(
                    makeClipboardMenuItem(
                        for: item,
                        index: offset + ClipboardMenuDisplay.primaryLimit
                    )
                )
            }

            overflowMenuItem.submenu = overflowMenu
            menu.addItem(overflowMenuItem)
        }

        return menu
    }

    private func shouldOpenUpward(near point: CGPoint) -> Bool {
        guard let screen = NSScreen.screenContaining(CGRect(origin: point, size: .zero)) ?? NSScreen.main else {
            return false
        }

        let availableBelow = point.y - screen.visibleFrame.minY
        return availableBelow < estimatedMenuHeight() + 8
    }

    private func estimatedMenuHeight() -> CGFloat {
        let primaryCount = min(store.items.count, ClipboardMenuDisplay.primaryLimit)
        let hasOverflow = store.items.count > ClipboardMenuDisplay.primaryLimit
        let visibleItemCount = primaryCount + (hasOverflow ? 1 : 0)

        return CGFloat(visibleItemCount) * ClipboardMenuDisplay.estimatedItemHeight
            + ClipboardMenuDisplay.estimatedMenuPadding
    }

    private func makeClipboardMenuItem(for item: ClipboardItem, index: Int) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: "\(index + 1). \(item.popupPreview)",
            action: #selector(selectClipboardItem(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.representedObject = item
        return menuItem
    }

    @objc
    private func selectClipboardItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem else {
            return
        }

        didTriggerSelection = true
        onSelect?(item)
    }

}

@MainActor
final class ClipboardPreferences: ObservableObject {
    static let shared = ClipboardPreferences()

    @Published var sortOrder: ClipboardSortOrder {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        }
    }

    private static let sortOrderKey = "clipboard.sortOrder"

    private init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.sortOrderKey)
        sortOrder = ClipboardSortOrder(rawValue: storedValue ?? "") ?? .newestFirst
    }

    func toggleSortOrder() {
        switch sortOrder {
        case .newestFirst:
            sortOrder = .oldestFirst
        case .oldestFirst:
            sortOrder = .automatic
        case .automatic:
            sortOrder = .newestFirst
        }
    }

    func sortedItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        switch sortOrder {
        case .newestFirst:
            return items
        case .oldestFirst:
            return items.reversed()
        case .automatic:
            return items
        }
    }

    func sortedPopupItems(from items: [ClipboardItem], opensUpward: Bool) -> [ClipboardItem] {
        switch sortOrder {
        case .newestFirst:
            return items
        case .oldestFirst:
            return items.reversed()
        case .automatic:
            return opensUpward ? items.reversed() : items
        }
    }
}

enum ClipboardSortOrder: String {
    case newestFirst
    case oldestFirst
    case automatic
}

final class PasteHotkeyMonitor {
    private let onTrigger: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let pasteboard = NSPasteboard.general
    private var skipNextMatchingShortcut = false

    init(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
    }

    func start() {
        guard eventTap == nil else {
            return
        }

        let events = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<PasteHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: events,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func skipNextPasteShortcut() {
        skipNextMatchingShortcut = true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let isPasteShortcut = keyCode == CGKeyCode(kVK_ANSI_V)
            && flags.contains(.maskCommand)
            && !flags.contains(.maskAlternate)

        guard isPasteShortcut else {
            return Unmanaged.passUnretained(event)
        }

        if skipNextMatchingShortcut {
            skipNextMatchingShortcut = false
            return Unmanaged.passUnretained(event)
        }

        guard shouldInterceptPaste() else {
            return Unmanaged.passUnretained(event)
        }

        let trigger = onTrigger
        Task { @MainActor in
            trigger()
        }

        return nil
    }

    private func shouldInterceptPaste() -> Bool {
        let snapshot = ClipboardPasteboardSnapshot.capture(from: pasteboard)
        if case .text = snapshot.kind {
            return true
        }

        return false
    }
}

struct ClipboardPasteboardSnapshot {
    let changeCount: Int
    let kind: ClipboardPayloadKind

    static func capture(from pasteboard: NSPasteboard) -> ClipboardPasteboardSnapshot {
        let items = pasteboard.pasteboardItems ?? []
        let allTypes = items.flatMap(\.types)

        if containsFilePayload(allTypes) {
            return ClipboardPasteboardSnapshot(changeCount: pasteboard.changeCount, kind: .fileLike)
        }

        if containsImagePayload(allTypes) {
            return ClipboardPasteboardSnapshot(changeCount: pasteboard.changeCount, kind: .imageLike)
        }

        if let text = firstMeaningfulText(in: items) {
            return ClipboardPasteboardSnapshot(changeCount: pasteboard.changeCount, kind: .text(text))
        }

        return ClipboardPasteboardSnapshot(changeCount: pasteboard.changeCount, kind: .unsupported)
    }

    private static func firstMeaningfulText(in items: [NSPasteboardItem]) -> String? {
        for item in items {
            if let plainText = preferredPlainText(from: item) {
                return plainText
            }

            if let richText = renderedTextFallback(from: item) {
                return richText
            }
        }

        return nil
    }

    private static func preferredPlainText(from item: NSPasteboardItem) -> String? {
        for type in preferredPlainTextTypes {
            if let value = item.string(forType: type)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        for type in item.types where isStrictPlainTextType(type) {
            if let value = item.string(forType: type)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static func renderedTextFallback(from item: NSPasteboardItem) -> String? {
        if let htmlData = item.data(forType: .html),
           let attributed = try? NSAttributedString(
                data: htmlData,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
           ) {
            let value = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        if let rtfData = item.data(forType: .rtf),
           let attributed = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            let value = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static var preferredPlainTextTypes: [NSPasteboard.PasteboardType] {
        [
            .string,
            NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
            NSPasteboard.PasteboardType(UTType.utf16PlainText.identifier),
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
            NSPasteboard.PasteboardType(UTType.text.identifier),
        ]
    }

    private static func isStrictPlainTextType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if type == .string {
            return true
        }

        guard let utType = UTType(type.rawValue) else {
            return false
        }

        return utType.conforms(to: .plainText)
            || utType.conforms(to: .utf8PlainText)
            || utType.conforms(to: .utf16PlainText)
    }

    private static func containsImagePayload(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { type in
            guard let utType = UTType(type.rawValue) else {
                return false
            }

            return utType.conforms(to: .image)
        }
    }

    private static func containsFilePayload(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { type in
            if type == .fileURL {
                return true
            }

            guard let utType = UTType(type.rawValue) else {
                return false
            }

            return utType.conforms(to: .fileURL)
        }
    }
}

enum ClipboardPayloadKind {
    case text(String)
    case imageLike
    case fileLike
    case unsupported
}

enum AccessibilityLocator {
    private static let maximumPointerDistanceForAccessibilityAnchor: CGFloat = 180

    static func bestAvailableAnchorRect() -> CGRect {
        let mouseRect = mouseAnchorRect()

        guard let anchorRect = caretOrFocusedRect() else {
            return mouseRect
        }

        let mousePoint = CGPoint(x: mouseRect.midX, y: mouseRect.midY)
        let anchorPoint = CGPoint(x: anchorRect.midX, y: anchorRect.midY)

        if hypot(anchorPoint.x - mousePoint.x, anchorPoint.y - mousePoint.y) > maximumPointerDistanceForAccessibilityAnchor {
            return mouseRect
        }

        return anchorRect
    }

    static func caretOrFocusedRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
        let rawCaretRect = caretRect(for: focused)
        let caretRect = rawCaretRect.flatMap(usableRect(fromCaretRect:))

        if let caretRect {
            return caretRect
        }

        if let inferredCaretRect = inferredCaretRect(for: focused) {
            return inferredCaretRect
        }

        let elementRect = elementRect(for: focused).flatMap(usableRect(fromElementRect:))

        if let elementRect {
            return elementRect
        }

        return nil
    }

    static func mouseAnchorRect() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 10, y: mouse.y - 10, width: 20, height: 20)
    }

    private static func caretRect(for element: AXUIElement) -> CGRect? {
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
              let selectedRangeValue else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsValue
        ) == .success,
        let boundsValue,
        CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(boundsValue, to: AXValue.self)

        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }

        return rect
    }

    private static func usableRect(fromCaretRect rect: CGRect) -> CGRect? {
        guard isUsableCaretRect(rect) else {
            return nil
        }

        return convertToAppKitCoordinates(rect)
    }

    private static func elementRect(for element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func usableRect(fromElementRect rect: CGRect) -> CGRect? {
        guard isUsableElementRect(rect) else {
            return nil
        }

        return convertToAppKitCoordinates(rect)
    }

    private static func inferredCaretRect(for element: AXUIElement) -> CGRect? {
        guard let selectedRange = selectedTextRange(for: element) else {
            return nil
        }

        let textLength = textLength(for: element)

        if selectedRange.length > 0,
           let nextRect = characterRect(
                at: selectedRange.location,
                textLength: textLength,
                in: element
           ) {
            return collapsedRect(atX: nextRect.minX, basedOn: nextRect)
        }

        if let nextRect = characterRect(
            at: selectedRange.location,
            textLength: textLength,
            in: element
        ) {
            return collapsedRect(atX: nextRect.minX, basedOn: nextRect)
        }

        if let previousRect = characterRect(
            at: selectedRange.location - 1,
            textLength: textLength,
            in: element
        ) {
            return collapsedRect(atX: previousRect.maxX, basedOn: previousRect)
        }

        return nil
    }

    private static func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)

        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private static func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)

        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private static func selectedTextRange(for element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private static func textLength(for element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID(),
              let stringValue = value as? String else {
            return nil
        }

        return (stringValue as NSString).length
    }

    private static func characterRect(at location: Int, textLength: Int?, in element: AXUIElement) -> CGRect? {
        guard location >= 0 else {
            return nil
        }

        if let textLength, location >= textLength {
            return nil
        }

        var range = CFRange(location: location, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success,
        let boundsValue,
        CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(boundsValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }

        return usableRect(fromCaretRect: rect)
    }

    private static func collapsedRect(atX x: CGFloat, basedOn rect: CGRect) -> CGRect {
        CGRect(x: x, y: rect.origin.y, width: 0, height: rect.height)
    }

    private static func convertToAppKitCoordinates(_ rect: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            let flipped = CGRect(
                x: rect.origin.x,
                y: screen.frame.maxY - rect.origin.y - rect.size.height,
                width: rect.size.width,
                height: rect.size.height
            )

            if screen.frame.intersects(flipped) {
                return flipped
            }
        }

        let referenceFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(
            x: rect.origin.x,
            y: referenceFrame.maxY - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private static func isUsableCaretRect(_ rect: CGRect) -> Bool {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite else {
            return false
        }

        guard rect.origin.x >= 0,
              rect.origin.y >= 0 else {
            return false
        }

        // Browsers often report a zero-height rect for the URL field caret.
        return rect.height >= 4
    }

    private static func isUsableElementRect(_ rect: CGRect) -> Bool {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite else {
            return false
        }

        return rect.width >= 20 && rect.height >= 12
    }
}

private extension View {
    @ViewBuilder
    func applyShortcutIfNeeded(for index: Int) -> some View {
        switch index {
        case 0: keyboardShortcut("1")
        case 1: keyboardShortcut("2")
        case 2: keyboardShortcut("3")
        case 3: keyboardShortcut("4")
        case 4: keyboardShortcut("5")
        case 5: keyboardShortcut("6")
        case 6: keyboardShortcut("7")
        case 7: keyboardShortcut("8")
        case 8: keyboardShortcut("9")
        default: self
        }
    }
}

private extension NSScreen {
    static func screenContaining(_ rect: CGRect) -> NSScreen? {
        screens.first { $0.visibleFrame.intersects(rect) }
    }
}

struct ClipboardItem: Identifiable {
    let id: UUID
    let value: String
    let copiedAt: Date

    init(id: UUID = UUID(), value: String, copiedAt: Date = .now) {
        self.id = id
        self.value = value
        self.copiedAt = copiedAt
    }

    var preview: String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        if singleLine.count <= 90 {
            return singleLine
        }

        return String(singleLine.prefix(90)) + "…"
    }

    var popupPreview: String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        if singleLine.count <= 28 {
            return singleLine
        }

        return String(singleLine.prefix(28)) + "…"
    }

    var timestampText: String {
        copiedAt.formatted(date: .omitted, time: .shortened)
    }
}
