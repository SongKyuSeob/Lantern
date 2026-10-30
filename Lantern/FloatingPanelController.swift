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
    /// 마우스가 창을 벗어났는지 짧은 간격으로 본다. 이 창은 다른 앱의 포커스를 뺏지 않아 창 위의 마우스 이동이 오지 않는다
    private var mouseExitTimer: Timer?
    private var wasMouseOver = false
    private var screenObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    private static let idleTimeout: TimeInterval = 10
    /// 화면 가장자리(메뉴바 아래, 오른쪽 끝)에서 띄우는 거리
    private static let margin = NSSize(width: 12, height: 10)
    private static let escapeKeyCode: UInt16 = 53

    init(
        awake: AwakeController,
        power: PowerStateMonitor,
        state: PanelState,
        lidMode: LidModeController,
        safety: SafetyController,
        agentMonitor: AgentMonitor,
        agentAwake: AgentAwakeController,
        todoStore: TodoStore,
        updates: UpdateController,
        openSettings: @escaping () -> Void,
        openHistory: @escaping () -> Void
    ) {
        self.state = state
        corner = UserDefaults.standard.string(forKey: Self.cornerKey).flatMap(PanelCorner.init) ?? .topRight
        screenID = (UserDefaults.standard.object(forKey: Self.screenKey) as? Int).map { CGDirectDisplayID($0) }
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
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
        // 창은 어두운 테마 하나로 고정한다. 시스템이 라이트 모드여도 유리 배경이 밝아지지 않게 창 자체를 어둡게 둔다
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.acceptsMouseMovedEvents = true
        // 키 입력을 돌려줄 때 창을 잠깐 내렸다 올리는데, 기본 페이드(0.3초)가 재생되면 창이 꺼졌다 뜨는 것처럼 보인다
        panel.animationBehavior = .none

        let host = NSHostingController(rootView: PanelView(
            awake: awake, power: power, state: state,
            lidMode: lidMode, safety: safety,
            agentMonitor: agentMonitor, agentAwake: agentAwake, todoStore: todoStore, updates: updates,
            openSettings: openSettings, openHistory: openHistory
        ))
        host.sizingOptions = .preferredContentSize
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        panel.contentViewController = host

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        // 내용에 따라 높이가 바뀌어도 붙인 모서리를 그 자리에 둔다.
        // 이 알림은 SwiftUI가 화면을 배치하는 도중에 오므로, 배치가 끝난 뒤에 옮긴다 (배치 중 재배치 경고 방지)
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }

        state.onHeaderDrag = { [weak self] phase in self?.handleHeaderDrag(phase) }
        applyMode()
        observeMode()
        #if DEBUG
        observeDebugCommands()
        #endif
    }

    #if DEBUG
    private var debugObserver: NSObjectProtocol?

    /// 디버그 빌드에서만: 터미널에서 창 동작을 흉내 내 확인한다.
    /// `com.songkyuseob.lantern.debug` 알림에 `toggle`(아이콘 클릭) · `chevron`(⌃/⌄) · `outside`(창 밖 클릭) · `pickTime`
    /// · `snapshot:<경로>`(창을 PNG로 저장)
    private func observeDebugCommands() {
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.songkyuseob.lantern.debug"), object: nil, queue: .main
        ) { [weak self] notification in
            let command = notification.object as? String
            MainActor.assumeIsolated {
                guard let self else { return }
                switch command {
                case "toggle": self.toggleActive()
                case "chevron":
                    self.state.isCollapsed.toggle()
                    self.state.mode = .passive
                case "outside": self.state.mode = .passive
                case "pickTime": self.state.isPickingTime.toggle()
                case let command? where command.hasPrefix("snapshot:"):
                    self.panel.contentView?.writeSnapshot(to: String(command.dropFirst("snapshot:".count)))
                default: break
                }
            }
        }
    }
    #endif

    var isVisible: Bool { panel.isVisible }

    func show() {
        place()
        panel.orderFrontRegardless()
        if state.mode == .passive { updateHoverFade() }
    }

    func hide() {
        state.mode = .passive
        panel.orderOut(nil)
    }

    /// 숨기기 단축키: 숨기기 ↔ 보이기
    func toggleHidden() {
        if panel.isVisible { hide() } else { show() }
    }

    /// 메뉴바 아이콘 왼쪽 클릭: 평소 ↔ 활성
    func toggleActive() {
        if !panel.isVisible {
            show()
            state.mode = .active
        } else if state.mode == .active {
            state.mode = .passive
        } else {
            state.mode = .active
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
            startHoverFade()
            state.isPickingTime = false
            state.isEditingText = false
            panel.ignoresMouseEvents = true
            panel.allowsKey = false
            panel.hasShadow = false
            giveBackKeyFocus()
        case .active:
            stopHoverFade()
            panel.ignoresMouseEvents = false
            panel.allowsKey = true
            // Liquid Glass는 둥근 모서리 밖까지 옅게 그려져 창 그림자가 네모나게 잡히므로 창 그림자는 쓰지 않는다
            panel.hasShadow = false
            if panel.isVisible { panel.makeKey() }
            startWatchingActivity()
        }
        panel.invalidateShadow()
    }

    /// 창이 키 입력을 받고 있었다면 원래 앱으로 돌려준다
    /// 창을 잠깐 내렸다 다시 올려 키 입력을 놓는다 (페이드 없이, `animationBehavior = .none`)
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
                #if DEBUG
                // 시연 모드(화면 캡처용)에서는 캡처 도구를 눌러도 창이 닫히지 않게 한다
                if DemoData.isEnabled { return }
                #endif
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
        if mouseExitTimer == nil {
            wasMouseOver = isMouseOver
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkMouseExit() }
            }
            RunLoop.main.add(timer, forMode: .common)
            mouseExitTimer = timer
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
        mouseExitTimer?.invalidate()
        mouseExitTimer = nil
    }

    /// 창 안에서 무언가 하면 10초를 다시 센다. Esc는 평소 상태로 돌아가고 `true`(이벤트 삼킴)
    private func handleLocalActivity(isEscape: Bool) -> Bool {
        if isEscape, !state.isPickingTime, !state.isEditingText {
            state.mode = .passive
            return true
        }
        restartIdleTimer()
        // 끌기 끝을 놓쳐 창이 모서리가 아닌 곳에 남았으면, 다음 움직임에 모서리로 붙인다
        if dragStart == nil, panel.frame.origin != cornerOrigin() { place(animated: true) }
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

    private var isMouseOver: Bool { panel.frame.contains(NSEvent.mouseLocation) }

    /// 마우스가 창을 벗어나면 그때부터 10초를 다시 센다
    private func checkMouseExit() {
        let isOver = isMouseOver
        if wasMouseOver, !isOver { restartIdleTimer() }
        wasMouseOver = isOver
    }

    /// 시각을 고르는 중이거나 마우스가 창 위에 있으면 조금 더 기다린다. 마우스가 벗어나면 `checkMouseExit`가 다시 센다
    private func idleTimerFired() {
        #if DEBUG
        if DemoData.isEnabled { return }
        #endif
        if state.isPickingTime || state.isEditingText || isMouseOver {
            restartIdleTimer()
        } else {
            state.mode = .passive
        }
    }

    // MARK: - 마우스를 올리면 흐려짐

    /// 평소 창은 클릭이 뒤로 통과하니, 그 아래를 보거나 누르려고 커서를 올리면 거의 투명하게 비켜 준다
    private static let hoverAlpha: CGFloat = 0.12
    /// 마지막으로 정한 불투명도. 애니메이션 도중의 값과 비교하면 흐린 채 멈출 수 있어 목표값을 따로 둔다
    private var targetAlpha: CGFloat = 1
    private var hoverMonitor: Any?
    /// 흐려진 동안 커서가 벗어났는지 직접 확인한다. 커서가 순간 이동하면 마지막 이동 알림이 오지 않을 수 있다
    private var hoverCheckTimer: Timer?

    private func startHoverFade() {
        if hoverMonitor == nil {
            // 평소 창은 마우스 이벤트를 받지 않으므로, 다른 앱으로 가는 이동을 지켜본다
            hoverMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateHoverFade() }
            }
        }
        updateHoverFade()
    }

    private func stopHoverFade() {
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
        hoverMonitor = nil
        stopHoverCheck()
        setAlpha(1)
    }

    private func updateHoverFade() {
        let isOver = panel.isVisible && panel.frame.contains(NSEvent.mouseLocation)
        setAlpha(isOver ? Self.hoverAlpha : 1)
        if isOver { startHoverCheck() } else { stopHoverCheck() }
    }

    private func startHoverCheck() {
        guard hoverCheckTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHoverFade() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverCheckTimer = timer
    }

    private func stopHoverCheck() {
        hoverCheckTimer?.invalidate()
        hoverCheckTimer = nil
    }

    private func setAlpha(_ alpha: CGFloat) {
        guard targetAlpha != alpha else { return }
        targetAlpha = alpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = alpha
        }
    }

    // MARK: - 위치

    /// 창을 붙인 모서리와 화면. 활성 창의 위쪽 탭 줄을 끌어 옮기고, 놓으면 가장 가까운 모서리에 붙는다
    private var corner: PanelCorner
    private var screenID: CGDirectDisplayID?
    /// 끌기 시작할 때의 커서와 창 위치
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    /// 끄는 동안 마우스 버튼이 실제로 눌려 있는지 짧은 간격으로 확인한다.
    /// 창이 커서와 함께 움직이면 SwiftUI의 끌기 끝이나 mouseUp 이벤트가 오지 않을 때가 있어서, 버튼 상태를 직접 본다
    private var dragReleaseTimer: Timer?

    private static let cornerKey = "panel.corner"
    private static let screenKey = "panel.screenID"

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// 위쪽 탭 줄을 끌 때 불린다
    private func handleHeaderDrag(_ phase: PanelState.DragPhase) {
        switch phase {
        case .changed:
            let mouse = NSEvent.mouseLocation
            if dragStart == nil {
                dragStart = (mouse, panel.frame.origin)
                let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if NSEvent.pressedMouseButtons & 1 == 0 {
                            self.handleHeaderDrag(.ended)
                        } else if let start = self.dragStart {
                            // SwiftUI가 끄는 중 알림을 멈춰도 창이 커서를 따라가게 한다
                            let now = NSEvent.mouseLocation
                            self.panel.setFrameOrigin(NSPoint(x: start.origin.x + now.x - start.mouse.x, y: start.origin.y + now.y - start.mouse.y))
                        }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                dragReleaseTimer = timer
            }
            guard let start = dragStart else { return }
            panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        case .ended:
            dragReleaseTimer?.invalidate()
            dragReleaseTimer = nil
            guard dragStart != nil else { return }
            dragStart = nil
            snapToNearestCorner()
        }
    }

    /// 창 가운데가 있는 화면(걸쳐 있거나 밖이면 가장 가까운 화면)의 가장 가까운 모서리에 붙이고 기억한다
    private func snapToNearestCorner() {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screens = NSScreen.screens
        let screen = screens.first { $0.frame.contains(center) }
            ?? screens.min { distance(center, to: $0.frame) < distance(center, to: $1.frame) }
        guard let screen else { return }
        corner = PanelCorner.nearest(to: center, in: screen.visibleFrame)
        screenID = Self.displayID(of: screen)
        UserDefaults.standard.set(corner.rawValue, forKey: Self.cornerKey)
        if let screenID { UserDefaults.standard.set(Int(screenID), forKey: Self.screenKey) }
        place(animated: true)
    }

    private func distance(_ point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// 기억한 화면(빠졌으면 메뉴바가 있는 첫 화면)의 기억한 모서리에 붙였을 때의 창 위치
    private func cornerOrigin() -> NSPoint? {
        let screens = NSScreen.screens
        let chosen = screenID.flatMap { id in screens.first { Self.displayID(of: $0) == id } }
        guard let screen = chosen ?? screens.first else { return nil }
        return corner.origin(size: panel.frame.size, in: screen.visibleFrame, margin: Self.margin)
    }

    /// 기억한 화면(빠졌으면 메뉴바가 있는 첫 화면)의 기억한 모서리에 붙인다.
    /// 위쪽 모서리면 아래로, 아래쪽 모서리면 위로 펼쳐진다
    private func place(animated: Bool = false) {
        guard dragStart == nil, let origin = cornerOrigin(), panel.frame.origin != origin else { return }
        // 창 이동 애니메이션은 animator() 대신 창 전용 setFrame(animate:)을 쓴다 (animator로는 창이 옮겨지지 않았음)
        panel.setFrame(NSRect(origin: origin, size: panel.frame.size), display: true, animate: animated)
    }
}

/// 테두리 없는 떠 있는 창.
final class FloatingPanel: NSPanel {
    /// 활성 상태일 때만 키 입력(시각 입력, Esc)을 받는다
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
