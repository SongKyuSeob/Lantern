import AppKit
import LanternKit
import SwiftUI

/// 설정 창. 메뉴바 앱이라 창을 열 때 앱을 앞으로 가져온다.
final class SettingsWindowController {
    private let lidMode: LidModeController
    private let safety: SafetyController
    private let agentHooks: AgentHookSetup
    private let agentMonitor: AgentMonitor
    private var window: NSWindow?

    init(lidMode: LidModeController, safety: SafetyController, agentHooks: AgentHookSetup, agentMonitor: AgentMonitor) {
        self.lidMode = lidMode
        self.safety = safety
        self.agentHooks = agentHooks
        self.agentMonitor = agentMonitor
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(
                lidMode: lidMode, safety: safety, agentHooks: agentHooks, agentMonitor: agentMonitor
            ))
            let window = NSWindow(contentViewController: host)
            window.title = "랜턴 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        lidMode.setup.refresh()
        agentHooks.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let lidMode: LidModeController
    @Bindable var safety: SafetyController
    let agentHooks: AgentHookSetup
    let agentMonitor: AgentMonitor

    private var lidModeSetup: LidModeSetup { lidMode.setup }

    var body: some View {
        Form {
            AgentSection(agentHooks: agentHooks, agentMonitor: agentMonitor)
            Section {
                Stepper(value: $safety.batteryThreshold, in: SafetyController.batteryThresholdRange, step: 5) {
                    LabeledContent("배터리 기준", value: "\(safety.batteryThreshold)%")
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
        .frame(width: 460)
        .fixedSize()
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
