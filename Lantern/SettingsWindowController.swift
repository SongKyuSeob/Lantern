import AppKit
import Carbon.HIToolbox
import LanternKit
import SwiftUI

/// 설정 창. 메뉴바 앱이라 창을 열 때 앱을 앞으로 가져온다.
final class SettingsWindowController {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("LanternSettings")

    private let lidMode: LidModeController
    private let safety: SafetyController
    private let agentHooks: AgentHookSetup
    private let agentMonitor: AgentMonitor
    private let shortcuts: GlobalShortcutController
    private let loginItem: LoginItemController
    private let updates: UpdateController
    private var window: NSWindow?

    init(
        lidMode: LidModeController,
        safety: SafetyController,
        agentHooks: AgentHookSetup,
        agentMonitor: AgentMonitor,
        shortcuts: GlobalShortcutController,
        loginItem: LoginItemController,
        updates: UpdateController
    ) {
        self.shortcuts = shortcuts
        self.updates = updates
        self.loginItem = loginItem
        self.lidMode = lidMode
        self.safety = safety
        self.agentHooks = agentHooks
        self.agentMonitor = agentMonitor
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(
                lidMode: lidMode, safety: safety, agentHooks: agentHooks, agentMonitor: agentMonitor,
                shortcuts: shortcuts, loginItem: loginItem, updates: updates
            ))
            let window = NSWindow(contentViewController: host)
            window.title = "랜턴 설정"
            window.identifier = SettingsWindowController.windowIdentifier
            // 높이는 사용자가 조절할 수 있다. 폭은 내용에 맞춰 고정
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 480, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        lidMode.setup.refresh()
        agentHooks.refresh()
        loginItem.refresh()
        // 메뉴바 앱은 macOS 14부터 앞으로 나오라는 요청(activate)이 거절될 수 있어서,
        // 창 자체도 맨 앞에 올린다 (거절되면 다른 앱 창 뒤에 열린다)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    #if DEBUG
    /// 디버그 빌드에서만: 설정 창을 이미지로 저장한다 (화면 녹화 권한 없이 모양을 확인하려고)
    func snapshot(to path: String) {
        window?.contentView?.writeSnapshot(to: path)
    }
    #endif
}

#if DEBUG
extension NSView {
    /// 이 뷰를 PNG로 저장한다
    func writeSnapshot(to path: String) {
        layoutSubtreeIfNeeded()
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return }
        cacheDisplay(in: bounds, to: rep)
        // 창 배경은 이 뷰가 그리지 않으므로, 창 배경색을 먼저 깔고 그 위에 얹는다 (다크 모드의 흰 글자가 보이게)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            (window?.backgroundColor ?? .windowBackgroundColor).setFill()
            NSRect(origin: .zero, size: bounds.size).fill()
        }
        rep.draw(in: NSRect(origin: .zero, size: bounds.size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let output = NSBitmapImageRep(data: tiff) else { return }
        try? output.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif

struct SettingsView: View {
    let lidMode: LidModeController
    @Bindable var safety: SafetyController
    let agentHooks: AgentHookSetup
    let agentMonitor: AgentMonitor
    let shortcuts: GlobalShortcutController
    let loginItem: LoginItemController
    let updates: UpdateController

    private var lidModeSetup: LidModeSetup { lidMode.setup }

    enum Tab: String, CaseIterable {
        case general, agents, power

        var title: String {
            switch self {
            case .general: "일반"
            case .agents: "에이전트"
            case .power: "전원"
            }
        }
    }

    @AppStorage("settings.tab") private var tab: Tab = .general

    /// 내용이 늘어나도 창이 화면 밖으로 넘치지 않게 탭으로 나누고, 탭 안은 스크롤된다.
    /// 기본 TabView는 테두리가 창 가장자리와 어긋나게 그려져서, 위쪽 세그먼트 + 아래 Form으로 만든다
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch tab {
            case .general:
                Form {
                    GeneralSection(loginItem: loginItem)
                    UpdateSection(updates: updates)
                    ShortcutSection(shortcuts: shortcuts)
                }
                .formStyle(.grouped)
            case .agents:
                Form {
                    AgentSection(agentHooks: agentHooks, agentMonitor: agentMonitor)
                }
                .formStyle(.grouped)
            case .power:
                powerForm
            }
        }
        .frame(minWidth: 480, idealWidth: 480, maxWidth: 480, minHeight: 360, idealHeight: 560, maxHeight: .infinity, alignment: .top)
    }

    private var powerForm: some View {
        Form {
            Section {
                // 값은 오른쪽 끝, 다른 줄("권한 · 설치됨")과 같은 자리에 둔다
                LabeledContent("배터리 기준") {
                    HStack(spacing: 6) {
                        Text("\(safety.batteryThreshold)%")
                            .monospacedDigit()
                        Stepper("", value: $safety.batteryThreshold, in: SafetyController.batteryThresholdRange, step: 5)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("배터리")
            } footer: {
                Text("충전기를 연결하지 않은 채 배터리가 이 아래로 내려가면 깨어 있기를 꺼요. 뚜껑을 닫아 둔 상태였다면 맥을 바로 재워요. 기준 아래에서는 뚜껑 닫아도 유지를 켤 수 없어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("권한") {
                    HStack(spacing: 8) {
                        statusLabel
                        switch lidModeSetup.status {
                        case .installed:
                            Button("제거…") {
                                lidModeSetup.uninstall()
                                lidMode.refresh()
                            }
                        case .notInstalled:
                            Button("설치…") { lidModeSetup.install() }
                        case .unknown:
                            EmptyView()
                        }
                    }
                }
                if let error = lidModeSetup.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("뚜껑 닫아도 유지 (뚜껑 모드)")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("깨어 있는 동안 외장 모니터 없이 뚜껑을 닫아도 맥이 잠들지 않게 해요. 깨어 있기가 끝나거나 맥이 많이 뜨거워지면 저절로 꺼져요. 처음 한 번 관리자 비밀번호가 필요해요.")
                    Text("설치하면 아래 세 명령만 비밀번호 없이 실행할 수 있어요. 이 맥의 다른 프로그램도 같은 명령을 쓸 수 있지만, 할 수 있는 일은 잠들지 않게 하거나 재우는 것뿐이에요.")
                    Text(allowedCommands)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch lidModeSetup.status {
        case .unknown: Text("확인 중…").foregroundStyle(.secondary)
        case .installed: Label("설치됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .notInstalled: Text("설치 안 됨").foregroundStyle(.secondary)
        }
    }

    private var allowedCommands: String {
        SudoersRule.Command.allCases
            .map { "sudo " + ([SudoersRule.pmsetPath] + $0.arguments).joined(separator: " ") }
            .joined(separator: "\n")
    }
}

/// "에이전트 연결" 칸. 에이전트별로 hook을 연결·해제하고, 신호가 실제로 오는지 보여 준다
private struct AgentSection: View {
    let agentHooks: AgentHookSetup
    let agentMonitor: AgentMonitor

    var body: some View {
        Section {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                LabeledContent(agent.displayName) {
                    HStack(spacing: 8) {
                        status(agent)
                        switch agentHooks.status(of: agent) {
                        case .connected:
                            Button("해제") { agentHooks.disconnect(agent) }
                        case .notConnected:
                            Button("연결") { agentHooks.connect(agent) }
                        case .programMissing:
                            EmptyView()
                        }
                    }
                }
            }
            if let error = agentHooks.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("에이전트 연결")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("연결하면 \"언제까지 · 에이전트\"를 골랐을 때 에이전트가 일하는 동안만 깨어 있어요. 에이전트 설정 파일에 랜턴 hook을 더하고, 다른 hook은 건드리지 않아요. 바꾸기 전 파일은 같은 폴더에 .lantern-backup으로 남겨요.")
                Text("Codex는 연결한 뒤 Codex를 다시 켜서 /hooks에서 랜턴 hook을 한 번 승인해야 동작해요. Claude Code는 처음 여는 폴더를 신뢰해야 hook이 동작해요.")
                Text(AgentStatusText.rulesHelp)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func status(_ agent: AgentKind) -> some View {
        switch agentHooks.status(of: agent) {
        case .programMissing:
            Text("설치 안 됨").foregroundStyle(.secondary)
        case .notConnected:
            Text("연결 안 됨").foregroundStyle(.secondary)
        case .connected:
            if let last = agentMonitor.lastSignalAt[agent] {
                Label("연결됨 · 마지막 신호 \(last.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("연결됨 · 아직 신호 없음", systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .help("에이전트에게 지시를 한 번 보내면 신호가 와요")
            }
        }
    }
}

/// "단축키" 칸. 동작마다 버튼을 누른 뒤 원하는 조합을 누르면 바뀐다
private struct ShortcutSection: View {
    let shortcuts: GlobalShortcutController
    @State private var recording: ShortcutAction?
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        Section {
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                row(action)
            }
            if let hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let failed = ShortcutAction.allCases.first(where: shortcuts.failedActions.contains) {
                Text("\(failed.title) 단축키를 등록하지 못했어요. 다른 조합으로 바꿔 주세요.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("단축키")
        } footer: {
            Text("어느 앱에서든 쓸 수 있어요. 창 열기·닫기는 메뉴바 아이콘을 누른 것과 같고, 메뉴바 아이콘이 가려져 안 보일 때도 쓸 수 있어요. 바꾸려면 버튼을 누른 뒤 원하는 조합을 누르세요 (Esc로 취소).\n⌃ 또는 ⌥가 들어간 조합만 쓸 수 있어요. ⌘ 조합은 대부분 앱이 이미 쓰고 있어서, 랜턴이 가져가면 모든 앱에서 그 기능이 막히기 때문이에요.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onDisappear { stopRecording() }
        // 녹화 중에 설정 창을 닫거나 다른 창으로 옮기면 녹화를 취소한다
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.identifier == SettingsWindowController.windowIdentifier { stopRecording() }
        }
    }

    private func row(_ action: ShortcutAction) -> some View {
        LabeledContent(action.title) {
            HStack(spacing: 8) {
                Button {
                    recording == action ? stopRecording() : startRecording(action)
                } label: {
                    // 버튼 바깥이 아니라 버튼 안쪽 폭을 넓혀, 옆 버튼과 사이가 벌어지지 않게 한다
                    Text(recording == action ? "키를 누르세요…" : shortcuts.shortcut(for: action)?.displayString ?? "없음")
                        .frame(minWidth: 72)
                }
                if recording != action {
                    if shortcuts.shortcut(for: action) != nil {
                        Button("끄기") { shortcuts.update(action, to: nil) }
                    }
                    if shortcuts.shortcut(for: action) != action.defaultShortcut {
                        Button("기본값") { apply(action.defaultShortcut, to: action) }
                    }
                }
            }
        }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        hint = nil
        recording = action
        // 지금 조합을 다시 누를 수도 있으니, 입력받는 동안 등록을 잠시 내린다
        shortcuts.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 설정 창에서 누른 키만 받는다 (플로팅 창의 할 일 입력 등은 그대로 둔다)
            guard event.window?.identifier == SettingsWindowController.windowIdentifier else { return event }
            let modifiers = event.modifierFlags.intersection(KeyShortcut.allowedModifiers)
            if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
                stopRecording()
                return nil
            }
            let candidate = KeyShortcut(keyCode: event.keyCode, modifiers: modifiers)
            if candidate.isValid {
                apply(candidate, to: action)
                stopRecording()
            } else {
                hint = "⌃ 또는 ⌥와 함께 눌러 주세요."
            }
            return nil
        }
    }

    /// 다른 동작이 쓰고 있는 조합이면 바꾸지 않고 알려 준다
    private func apply(_ shortcut: KeyShortcut, to action: ShortcutAction) {
        if let other = shortcuts.conflict(shortcut, for: action) {
            hint = "\(shortcut.displayString)는 이미 \(other.title)에 쓰고 있어요."
            return
        }
        hint = nil
        shortcuts.update(action, to: shortcut)
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording != nil else { return }
        recording = nil
        shortcuts.resume()
    }
}

/// "업데이트" 칸: 지금 버전, 직접 확인, 하루 한 번 자동 확인
private struct UpdateSection: View {
    @Bindable var updates: UpdateController

    var body: some View {
        Section {
            Toggle(isOn: $updates.automaticallyChecks) {
                Text("업데이트 자동으로 확인")
                Text("하루 한 번 새 버전이 있는지 확인해요. 설치는 직접 눌러야 해요.")
            }
            HStack {
                Text("버전 \(updates.currentVersion)")
                if let version = updates.availableVersion {
                    Text("· \(version) 나옴")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("업데이트 확인") { updates.checkForUpdates() }
            }
        } header: {
            Text("업데이트")
        }
    }
}

/// "일반" 칸: 로그인할 때 열기
private struct GeneralSection: View {
    let loginItem: LoginItemController

    var body: some View {
        Section {
            Toggle("로그인할 때 열기", isOn: Binding(
                get: { loginItem.status != .disabled },
                set: { loginItem.setEnabled($0) }
            ))
            if loginItem.status == .requiresApproval {
                HStack {
                    Text("시스템 설정에서 랜턴을 허용해야 켜져요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("시스템 설정 열기") { loginItem.openSystemSettings() }
                }
            }
            if let error = loginItem.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("일반")
        }
    }
}
