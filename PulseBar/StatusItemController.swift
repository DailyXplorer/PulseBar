import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private static let logger = Logger(subsystem: "com.dailyxplorer.pulsebar", category: "status-item")
    private static let expandedDelegateSetter = NSSelectorFromString("setExpandedInterfaceDelegate:")
    private static let expandedDelegateGetter = NSSelectorFromString("expandedInterfaceDelegate")
    private static let expandedSessionGetter = NSSelectorFromString("expandedInterfaceSession")
    private static let cancelSessionSelector = NSSelectorFromString("cancel")
    private static let didBeginExpandedSessionSelector = NSSelectorFromString(
        "statusItem:didBeginExpandedInterfaceSession:"
    )
    private static let didEndExpandedSessionSelector = NSSelectorFromString(
        "statusItemDidEndExpandedInterfaceSession:animated:"
    )

    private let systemMonitor: SystemMonitor
    private let appSettings: AppSettingsStore
    private let statusItem: NSStatusItem
    private let panel: StatusPanel
    private var cancellables: Set<AnyCancellable> = []
    private var usesExpandedInterfaceSessions = false
    private var interactionAnchorRect: NSRect?

    var isReady: Bool {
        statusItem.isVisible && isInteractionConnected
    }

    private var isInteractionConnected: Bool {
        if usesExpandedInterfaceSessions {
            guard let delegate = statusItem.perform(Self.expandedDelegateGetter)?.takeUnretainedValue() else {
                return false
            }

            return delegate === self
                && responds(to: Self.didBeginExpandedSessionSelector)
                && responds(to: Self.didEndExpandedSessionSelector)
        }

        return statusItem.button?.target === self
            && statusItem.button?.action == #selector(togglePanel(_:))
    }

    init(systemMonitor: SystemMonitor, appSettings: AppSettingsStore) {
        self.systemMonitor = systemMonitor
        self.appSettings = appSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        configureStatusItem()
        observeMenuBarLabel()

        Self.logger.notice(
            "Status item configured ready=\(self.isReady, privacy: .public) expandedSessions=\(self.usesExpandedInterfaceSessions, privacy: .public)"
        )
    }

    private func configurePanel() {
        let rootView = MenuBarView()
            .environmentObject(systemMonitor)
            .environmentObject(appSettings)
            .environmentObject(systemMonitor.globalMetricsStore)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.delegate = self
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.toolTip = "PulseBar"
        button.setAccessibilityLabel("PulseBar")
        updateMenuBarLabel(showCPU: appSettings.showMenuBarCPU, cpuUsagePercent: nil)
        if statusItem.responds(to: Self.expandedDelegateSetter) {
            _ = statusItem.perform(Self.expandedDelegateSetter, with: self)
            usesExpandedInterfaceSessions = true
        } else {
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp])
        }
    }

    private func observeMenuBarLabel() {
        appSettings.$showMenuBarCPU
            .combineLatest(systemMonitor.globalMetricsStore.$metrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] showCPU, metrics in
                guard let self else { return }

                updateMenuBarLabel(
                    showCPU: showCPU,
                    cpuUsagePercent: metrics?.cpuUsagePercent
                )
                systemMonitor.applyMenuBarCPUMode(showCPU)
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarLabel(showCPU: Bool, cpuUsagePercent: Double?) {
        guard let button = statusItem.button else {
            return
        }

        if showCPU, let cpuUsagePercent {
            let roundedCPU = Int(cpuUsagePercent.rounded())
            button.image = nil
            button.imagePosition = .noImage
            button.title = "\(roundedCPU)%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.setAccessibilityLabel("PulseBar CPU \(roundedCPU) percent")
        } else {
            let image = NSImage(named: HugeIcon.menuBarDashboard.rawValue)
            image?.isTemplate = true
            button.title = ""
            button.image = image
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("PulseBar")
        }
    }

    @objc
    private func togglePanel(_ sender: Any?) {
        captureInteractionAnchor()

        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard !panel.isVisible else {
            return
        }

        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        systemMonitor.setCadence(.foreground)
        Self.logger.info("PulseBar interface shown")
    }

    private func hidePanel() {
        guard panel.isVisible else {
            return
        }

        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        systemMonitor.setCadence(appSettings.showMenuBarCPU ? .background : .off)
        interactionAnchorRect = nil
        Self.logger.info("PulseBar interface hidden")
    }

    private func positionPanel() {
        let anchorRect = validatedStatusItemAnchorRect() ?? interactionAnchorRect
        let screen = anchorRect.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? statusItem.button?.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let screenPadding: CGFloat = 8
        let preferredPanelHeight: CGFloat = 600
        let availableHeight = max(1, visibleFrame.height - (screenPadding * 2))
        let panelHeight = min(preferredPanelHeight, availableHeight)
        panel.setContentSize(NSSize(width: 480, height: panelHeight))

        let panelSize = panel.frame.size
        let anchor = anchorRect ?? NSRect(
            x: visibleFrame.maxX - 24,
            y: screen.frame.maxY - 33,
            width: 24,
            height: 26
        )
        let preferredX = anchor.midX - panelSize.width / 2
        let minimumX = visibleFrame.minX + screenPadding
        let maximumX = visibleFrame.maxX - panelSize.width - screenPadding
        let x = min(max(preferredX, minimumX), maximumX)
        let preferredY = anchor.minY - panelSize.height - 6
        let minimumY = visibleFrame.minY + screenPadding
        let maximumY = visibleFrame.maxY - panelSize.height - screenPadding
        let y = min(max(preferredY, minimumY), maximumY)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func statusItemAnchorRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else {
            return nil
        }

        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    private func validatedStatusItemAnchorRect() -> NSRect? {
        guard let anchorRect = statusItemAnchorRect(),
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) }),
              anchorRect.midY >= screen.visibleFrame.maxY - 2,
              anchorRect.midY <= screen.frame.maxY + 2 else {
            return nil
        }

        return anchorRect
    }

    private func captureInteractionAnchor() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              point.y >= screen.visibleFrame.maxY - 2,
              point.y <= screen.frame.maxY + 2 else {
            interactionAnchorRect = nil
            return
        }

        interactionAnchorRect = NSRect(
            x: point.x - 12,
            y: point.y - 12,
            width: 24,
            height: 24
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible else {
            return
        }

        if usesExpandedInterfaceSessions, cancelExpandedInterfaceSession() {
            return
        }

        hidePanel()
    }

    @objc(statusItem:didBeginExpandedInterfaceSession:)
    private func statusItem(
        _ statusItem: NSStatusItem,
        didBeginExpandedInterfaceSession session: AnyObject
    ) {
        captureInteractionAnchor()
        showPanel()
    }

    @objc(statusItemDidEndExpandedInterfaceSession:animated:)
    private func statusItemDidEndExpandedInterfaceSession(
        _ statusItem: NSStatusItem,
        animated: Bool
    ) {
        hidePanel()
    }

    @discardableResult
    private func cancelExpandedInterfaceSession() -> Bool {
        guard let session = statusItem.perform(Self.expandedSessionGetter)?.takeUnretainedValue(),
              session.responds(to: Self.cancelSessionSelector) else {
            return false
        }

        _ = session.perform(Self.cancelSessionSelector)
        return true
    }

#if DEBUG
    func runPresentationSmokeTest(completion: @escaping (PresentationSmokeTestReport) -> Void) {
        guard isReady else {
            completion(
                makeSmokeTestReport(
                    interfaceVisible: false,
                    interfaceWithinVisibleScreen: false,
                    failure: "Status item is not ready."
                )
            )
            return
        }

        guard let button = statusItem.button else {
            completion(
                makeSmokeTestReport(
                    interfaceVisible: false,
                    interfaceWithinVisibleScreen: false,
                    failure: "Status item button is unavailable."
                )
            )
            return
        }

        if usesExpandedInterfaceSessions {
            showPanel()
        } else {
            button.performClick(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }

            let interfaceVisible = panel.isVisible
                && panel.contentViewController?.view.window?.isVisible == true
            let interfaceWithinVisibleScreen = panel.screen?.visibleFrame.contains(panel.frame) == true
            let failure: String?
            if !interfaceVisible {
                failure = "Panel did not become visible."
            } else if !interfaceWithinVisibleScreen {
                failure = "Panel is not fully contained in the visible screen."
            } else {
                failure = nil
            }
            let report = makeSmokeTestReport(
                interfaceVisible: interfaceVisible,
                interfaceWithinVisibleScreen: interfaceWithinVisibleScreen,
                failure: failure
            )

            if usesExpandedInterfaceSessions {
                if !cancelExpandedInterfaceSession() {
                    hidePanel()
                }
            } else if panel.isVisible {
                button.performClick(nil)
            }
            completion(report)
        }
    }

    private func makeSmokeTestReport(
        interfaceVisible: Bool,
        interfaceWithinVisibleScreen: Bool,
        failure: String?
    ) -> PresentationSmokeTestReport {
        PresentationSmokeTestReport(
            ready: isReady && interfaceVisible && interfaceWithinVisibleScreen,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundlePath: Bundle.main.bundlePath,
            statusItemVisible: statusItem.isVisible,
            interactionConnected: isInteractionConnected,
            expandedInterfaceSessions: usesExpandedInterfaceSessions,
            interfaceVisible: interfaceVisible,
            interfaceWithinVisibleScreen: interfaceWithinVisibleScreen,
            panelFrame: CodableRect(panel.frame),
            failure: failure
        )
    }
#endif
}

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

#if DEBUG
struct PresentationSmokeTestReport: Codable {
    let ready: Bool
    let processIdentifier: Int32
    let bundlePath: String
    let statusItemVisible: Bool
    let interactionConnected: Bool
    let expandedInterfaceSessions: Bool
    let interfaceVisible: Bool
    let interfaceWithinVisibleScreen: Bool
    let panelFrame: CodableRect
    let failure: String?
}

struct CodableRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}
#endif
