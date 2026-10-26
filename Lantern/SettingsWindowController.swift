import AppKit
import LanternKit
import SwiftUI

/// 설정 창. 메뉴바 앱이라 창을 열 때 앱을 앞으로 가져온다.
final class SettingsWindowController {
    private let lidMode: LidModeController
    private let safety: SafetyController
    private var window: NSWindow?

    init(lidMode: LidModeController, safety: SafetyController) {
        self.lidMode = lidMode
        self.safety = safety
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(lidMode: lidMode, safety: safety))
            let window = NSWindow(contentViewController: host)
            window.title = "랜턴 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        lidMode.setup.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let lidMode: LidModeController
    @Bindable var safety: SafetyController

    private var lidModeSetup: LidModeSetup { lidMode.setup }

    var body: some View {
        Form {
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
