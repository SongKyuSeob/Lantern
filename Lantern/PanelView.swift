import AppKit
import LanternKit
import SwiftUI

/// 플로팅 창의 내용. 평소 / 접힘 / 활성 세 가지 모습이 있다 (Figma 시안 v2.5).
struct PanelView: View {
    let awake: AwakeController
    let power: PowerStateMonitor
    @Bindable var state: PanelState
    let lidMode: LidModeController
    let safety: SafetyController
    let openSettings: () -> Void

    var body: some View {
        Group {
            // 활성 상태는 접어 두었어도 전체 창. 접기는 평소 상태의 모습만 정한다
            if state.mode == .active {
                ActivePanel(awake: awake, power: power, state: state, lidMode: lidMode, safety: safety, openSettings: openSettings)
            } else if state.isCollapsed {
                CollapsedBar(awake: awake)
            } else {
                PassiveSummary(awake: awake, power: power)
            }
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.18), value: state.mode)
    }
}

// MARK: - 활성

private struct ActivePanel: View {
    let awake: AwakeController
    let power: PowerStateMonitor
    @Bindable var state: PanelState
    let lidMode: LidModeController
    let safety: SafetyController
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch state.tab {
            case .awake: AwakeTab(awake: awake, power: power, state: state, lidMode: lidMode, safety: safety, openSettings: openSettings)
            case .todo: TodoTab()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .panelBackground(RoundedRectangle(cornerRadius: 14), passive: false)
    }

    private var header: some View {
        HStack {
            SegmentedPicker(
                items: [(PanelState.Tab.todo, "할 일"), (.awake, "깨어 있기")],
                selection: state.tab,
                style: .tab
            ) { state.tab = $0 }
            Spacer()
            Button {
                state.isCollapsed.toggle()
                if state.isCollapsed { state.mode = .passive }
            } label: {
                Image(systemName: state.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(state.isCollapsed ? "펼쳐 두기" : "접어 두기")
        }
    }
}

private struct AwakeTab: View {
    let awake: AwakeController
    let power: PowerStateMonitor
    @Bindable var state: PanelState
    let lidMode: LidModeController
    let safety: SafetyController
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusCard(awake: awake)
            durationRow
            if state.isPickingTime {
                TimePickerRow(awake: awake, state: state)
            }
            if let lid = AwakeText.lidClose(LidClosePrediction.outcome(for: power.snapshot)) {
                Divider()
                lidRows(lid)
                LidModeRow(awake: awake, lidMode: lidMode, safety: safety, openSettings: openSettings)
            }
            if awake.isAwake {
                Divider()
                HStack {
                    Button("화면 끄기") { awake.turnOffDisplay() }
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("깨어 있기 끄기") { awake.stop() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primaryLight)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }
        }
    }

    private enum Choice: Hashable {
        case option(AwakeOption)
        case pickTime
    }

    private var durationRow: some View {
        let selected: Choice = {
            if state.isPickingTime { return .pickTime }
            let option = awake.current?.option ?? awake.lastOption
            if case .timeOfDay = option { return .pickTime }
            return .option(option)
        }()
        return HStack {
            Text("언제까지")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            SegmentedPicker(
                items: [
                    (Choice.option(.indefinite), "계속"),
                    (.option(.hours(1)), "1시간"),
                    (.option(.hours(2)), "2시간"),
                    (.pickTime, "시각"),
                ],
                selection: selected,
                style: .segment
            ) { choice in
                switch choice {
                case .option(let option):
                    state.isPickingTime = false
                    awake.start(option)
                case .pickTime:
                    state.isPickingTime.toggle()
                }
            }
        }
        .padding(.leading, 2)
    }

    private func lidRows(_ lid: (staysAwake: Bool, value: String, detail: String)) -> some View {
        let color = lid.staysAwake ? Theme.good : Theme.bad
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("지금 뚜껑을 닫으면")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(lid.staysAwake ? Theme.goodDot : Theme.bad).frame(width: 5, height: 5)
                    Text(lid.value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(color)
                }
            }
            Text(lid.detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 2)
    }
}

/// "뚜껑 닫아도 유지" 스위치. 권한이 없으면 자물쇠를 눌러 설정 창으로 간다
private struct LidModeRow: View {
    let awake: AwakeController
    let lidMode: LidModeController
    let safety: SafetyController
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("뚜껑 닫아도 유지")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(canToggle ? 0.85 : 0.45))
                if let note {
                    Text(note.text)
                        .font(.system(size: 11))
                        .foregroundStyle(note.isError ? Theme.bad : .white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if lidMode.setup.status == .notInstalled {
                Button(action: openSettings) {
                    Label("설정", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.primaryLight)
                }
                .buttonStyle(.plain)
                .help("권한 설치는 설정 창에서 해요")
            } else {
                Toggle("", isOn: Binding(
                    get: { lidMode.isOn },
                    set: { $0 ? lidMode.enable() : lidMode.disable() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(Theme.primary)
                .disabled(!canToggle)
            }
        }
        .padding(.horizontal, 2)
    }

    /// 켜져 있으면 언제든 끌 수 있고, 꺼져 있으면 조건이 맞을 때만 켤 수 있다
    private var canToggle: Bool {
        lidMode.isOn || (lidMode.setup.status == .installed && awake.isAwake && safety.lidModeBlock == nil)
    }

    private var note: (text: String, isError: Bool)? {
        if let error = lidMode.lastError { return (error, true) }
        if lidMode.isOn { return nil }
        if lidMode.setup.status == .notInstalled { return ("처음 한 번 권한 설치가 필요해요", false) }
        if !awake.isAwake { return ("깨어 있는 동안만 켤 수 있어요", false) }
        switch safety.lidModeBlock {
        case .lowBattery(let threshold): return ("배터리가 \(threshold)% 이하라 켤 수 없어요", false)
        case .tooHot: return ("맥이 뜨거워서 지금은 켤 수 없어요", false)
        case nil: return nil
        }
    }
}

/// 남은 시간 카드
private struct StatusCard: View {
    let awake: AwakeController

    var body: some View {
        HStack {
            if let session = awake.current {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        FlameDot(size: 6)
                        Text("깨어 있는 중 · \(AwakeText.until(session) ?? AwakeText.label(for: session.option))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.flameText)
                    }
                    if let remaining = awake.remaining {
                        Text("\(Text(RemainingTimeFormat.string(from: remaining)).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white))\(Text(" 남음").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.5)))")
                            .tracking(-0.3)
                            .monospacedDigit()
                    } else {
                        Text("끌 때까지 깨어 있음")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        HollowDot(size: 6)
                        Text("깨어 있기 꺼짐")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text("맥이 평소처럼 잠들어요")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button("\(AwakeText.label(for: awake.lastOption)) 시작 ›") { awake.startWithLastOption() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryLight)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fillCard))
    }
}

/// "시각" 세그먼트를 눌렀을 때 나오는 시각 고르기
private struct TimePickerRow: View {
    let awake: AwakeController
    @Bindable var state: PanelState
    @State private var time = TimePickerRow.initialTime()

    var body: some View {
        HStack(spacing: 8) {
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
            Text(preview)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("시작") {
                state.isPickingTime = false
                awake.start(option)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.primaryLight)
        }
        .padding(.horizontal, 2)
    }

    private var option: AwakeOption {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return .timeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// 이미 지난 시각이면 "내일 …까지"
    private var preview: String {
        let now = Date()
        guard let end = option.endDate(startingAt: now) else { return "" }
        return AwakeText.until(end, from: now)
    }

    /// 지금부터 두 시간 뒤 정각
    private static func initialTime() -> Date {
        let calendar = Calendar.current
        let later = Date().addingTimeInterval(2 * 3600)
        return calendar.date(bySettingHour: calendar.component(.hour, from: later), minute: 0, second: 0, of: later) ?? later
    }
}

private struct TodoTab: View {
    var body: some View {
        Text("할 일은 M4에서 만들어요")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
    }
}

// MARK: - 평소

/// 평소 상태: 상태 한 줄 + 설명 한 줄. 클릭은 뒤로 통과한다
private struct PassiveSummary: View {
    let awake: AwakeController
    let power: PowerStateMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = awake.current {
                HStack {
                    HStack(spacing: 7) {
                        FlameDot(size: 7)
                        Text("깨어 있는 중")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.flameTextPassive)
                    }
                    Spacer()
                    if let remaining = awake.remaining {
                        Text("\(Text(RemainingTimeFormat.string(from: remaining)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))\(Text(" 남음").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6)))")
                            .monospacedDigit()
                    }
                }
                detailLine(session)
            } else {
                HStack(spacing: 7) {
                    HollowDot(size: 7)
                    Text("깨어 있기 꺼짐")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .panelBackground(RoundedRectangle(cornerRadius: 14), passive: true)
    }

    /// "오후 4:30까지 · 지금 닫아도 유지됨"
    private func detailLine(_ session: AwakeSession) -> some View {
        let until = AwakeText.until(session) ?? AwakeText.label(for: session.option)
        let base = Text(until).foregroundStyle(.white.opacity(0.65))
        let line: Text
        if let lid = AwakeText.lidClose(LidClosePrediction.outcome(for: power.snapshot)) {
            let lead = lid.staysAwake ? " · 지금 닫아도 " : " · 지금 닫으면 "
            let value = Text(lid.value)
                .fontWeight(.medium)
                .foregroundStyle(lid.staysAwake ? Theme.goodPassive : Theme.bad)
            line = Text("\(base)\(Text(lead).foregroundStyle(.white.opacity(0.65)))\(value)")
        } else {
            line = base
        }
        return line.font(.system(size: 11))
    }
}

// MARK: - 접힘

/// 한 줄로 접어 둔 평소 모습. 클릭은 뒤로 통과한다
private struct CollapsedBar: View {
    let awake: AwakeController

    var body: some View {
        HStack {
            if awake.isAwake {
                HStack(spacing: 7) {
                    FlameDot(size: 7)
                    Text("\(Text("깨어 있는 중").foregroundStyle(Theme.flameTextPassive))\(Text(" · \(shortStatus)").foregroundStyle(.white))")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: 7) {
                    HollowDot(size: 7)
                    Text("깨어 있기 꺼짐")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .panelBackground(Capsule(), passive: true)
    }

    private var shortStatus: String {
        if let remaining = awake.remaining { return RemainingTimeFormat.string(from: remaining) }
        return awake.current.map { AwakeText.label(for: $0.option) } ?? ""
    }
}

// MARK: - 부품

/// 탭과 "언제까지"에 쓰는 작은 세그먼트
private struct SegmentedPicker<Value: Hashable>: View {
    enum Style { case tab, segment }

    let items: [(Value, String)]
    let selection: Value
    let style: Style
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: style == .tab ? 2 : 1) {
            ForEach(items, id: \.0) { value, title in
                let isSelected = value == selection
                Button { onSelect(value) } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(foreground(isSelected))
                        .padding(.horizontal, style == .tab ? 9 : 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(background(isSelected)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fillTrack))
    }

    private func foreground(_ isSelected: Bool) -> Color {
        switch (style, isSelected) {
        case (.tab, true): Theme.primaryTabText
        case (.tab, false): .white.opacity(0.45)
        case (.segment, true): .white
        case (.segment, false): .white.opacity(0.6)
        }
    }

    private func background(_ isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return style == .tab ? Theme.primary.opacity(0.22) : Theme.primary
    }
}

private struct FlameDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Theme.flame)
            .frame(width: size, height: size)
            .shadow(color: Color(hex: 0xFFA633).opacity(0.9), radius: 3)
    }
}

private struct HollowDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(0.5), lineWidth: 1.1)
            .frame(width: size, height: size)
    }
}

private struct Divider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}

/// 평소: 반투명 바탕 + 뒤 흐림. 활성: 불투명 바탕
private struct PanelBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let passive: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if passive { BehindWindowBlur() }
                    Theme.background.opacity(passive ? Theme.passiveBackgroundOpacity : 1)
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(passive ? Theme.borderPassive : Theme.border, lineWidth: 1))
    }
}

private extension View {
    func panelBackground<S: InsettableShape>(_ shape: S, passive: Bool) -> some View {
        modifier(PanelBackground(shape: shape, passive: passive))
    }
}

/// 창 뒤의 화면을 흐리게 비춘다
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
