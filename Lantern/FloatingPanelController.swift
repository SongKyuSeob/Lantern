import AppKit
import LanternKit
import SwiftUI

/// 화면 오른쪽 위에 늘 떠 있는 창.
///
/// 평소에는 반투명하고 클릭이 뒤로 통과한다. 메뉴바 아이콘을 왼쪽 클릭하면 활성 상태가 되어 조작할 수 있고,
/// 창 밖을 클릭하거나 10초 동안 아무것도 하지 않으면 평소 상태로 돌아간다.
final class FloatingPanelController {
    private let state: PanelState
    private let panel: FloatingPanel

    private var outsideClickMonitor: Any?
    private var activityMonitor: Any?
    private var idleTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    private static let idleTimeout: TimeInterval = 10
    /// 화면 가장자리(메뉴바 아래, 오른쪽 끝)에서 띄우는 거리
    private static let margin = NSSize(width: 12, height: 10)
    private static let escapeKeyCode: UInt16 = 53

    init(awake: AwakeController, power: PowerStateMonitor, state: PanelState) {
        self.state = state
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.acceptsMouseMovedEvents = true

        let host = NSHostingController(rootView: PanelView(awake: awake, power: power, state: state))
        host.sizingOptions = .preferredContentSize
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        panel.contentViewController = host

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeAtTopRight() }
        }
        // 내용에 따라 높이가 바뀌어도 오른쪽 위 모서리를 그 자리에 둔다
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeAtTopRight() }
        }

        applyMode()
        observeMode()
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        placeAtTopRight()
        panel.orderFrontRegardless()
    }

    func hide() {
        state.mode = .passive
        panel.orderOut(nil)
    }

    /// 메뉴바 아이콘 왼쪽 클릭: 평소 ↔ 활성
    func toggleActive() {
        if !panel.isVisible {
            show()
            state.mode = .active
        } else {
            state.mode = state.mode == .active ? .passive : .active
        }
    }

    /// 메뉴의 "시각…": 창을 펼쳐 시각 고르기를 연다
    func showTimePicker() {
        show()
        state.isCollapsed = false
        state.tab = .awake
        state.isPickingTime = true
        state.mode = .active
    }

    // MARK: - 평소 / 활성

    private func observeMode() {
        withObservationTracking {
            _ = state.mode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyMode()
                self?.observeMode()
            }
        }
    }

    private func applyMode() {
        switch state.mode {
        case .passive:
            stopWatchingActivity()
            state.isPickingTime = false
            panel.ignoresMouseEvents = true
            panel.allowsKey = false
            panel.hasShadow = false
            giveBackKeyFocus()
        case .active:
            panel.ignoresMouseEvents = false
            panel.allowsKey = true
            panel.hasShadow = true
            if panel.isVisible { panel.makeKey() }
            startWatchingActivity()
        }
        panel.invalidateShadow()
    }

    /// 창이 키 입력을 받고 있었다면 원래 앱으로 돌려준다
    private func giveBackKeyFocus() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func startWatchingActivity() {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.mode = .passive }
            }
        }
        if activityMonitor == nil {
            activityMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .mouseMoved]
            ) { [weak self] event in
                let isEscape = event.type == .keyDown && event.keyCode == Self.escapeKeyCode
                let consumed = MainActor.assumeIsolated { self?.handleLocalActivity(isEscape: isEscape) ?? false }
                return consumed ? nil : event
            }
        }
        restartIdleTimer()
    }

    private func stopWatchingActivity() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        outsideClickMonitor = nil
        activityMonitor = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// 창 안에서 무언가 하면 10초를 다시 센다. Esc는 평소 상태로 돌아가고 `true`(이벤트 삼킴)
    private func handleLocalActivity(isEscape: Bool) -> Bool {
        if isEscape, !state.isPickingTime {
            state.mode = .passive
            return true
        }
        restartIdleTimer()
        return false
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.idleTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    /// 시각을 고르는 중이거나 마우스가 창 위에 있으면 조금 더 기다린다
    private func idleTimerFired() {
        if state.isPickingTime || panel.frame.contains(NSEvent.mouseLocation) {
            restartIdleTimer()
        } else {
            state.mode = .passive
        }
    }

    // MARK: - 위치

    /// 메뉴바가 있는 화면의 오른쪽 위에 붙인다
    private func placeAtTopRight() {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - Self.margin.width,
            y: visible.maxY - size.height - Self.margin.height
        )
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }
}

/// 테두리 없는 떠 있는 창.
final class FloatingPanel: NSPanel {
    /// 활성 상태일 때만 키 입력(시각 입력, Esc)을 받는다
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
