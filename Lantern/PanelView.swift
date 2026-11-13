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
    let agentMonitor: AgentMonitor
    let agentAwake: AgentAwakeController
    let todoStore: TodoStore
    let updates: UpdateController
    let openSettings: () -> Void
    let openHistory: () -> Void
    /// 크기 단계. 글자·폭·여백은 `.scaled`로 이 값을 곱하므로, 바뀌면 화면을 새로 그린다
    @AppStorage(PanelSize.key) private var size: PanelSize = .standard
    /// 내용의 실제 높이. 창 높이는 정수로만 정해져서, 143.5처럼 소수점이면 창이 144 ↔ 143을 끝없이 오가다 죽는다
    /// (2026-11-14 "크게"에서 발생). 정수로 올림한 높이를 창에 알린다
    @State private var contentHeight: CGFloat?

    var body: some View {
        Group {
            // 활성 상태는 한 줄 보기여도 전체 창. 한 줄 보기는 평소 상태의 모습만 정한다 (메뉴바 메뉴·설정에서 고름)
            if state.mode == .active {
                ActivePanel(
                    awake: awake, power: power, state: state, lidMode: lidMode, safety: safety,
                    agents: AgentStatusText(monitor: agentMonitor, phase: agentAwake.phase),
                    todoStore: todoStore, updates: updates, openSettings: openSettings, openHistory: openHistory
                )
            } else if state.isCollapsed {
                CollapsedBar(awake: awake, agents: AgentStatusText(monitor: agentMonitor, phase: agentAwake.phase), updates: updates)
            } else {
                PassiveSummary(awake: awake, power: power, agents: AgentStatusText(monitor: agentMonitor, phase: agentAwake.phase), updates: updates)
            }
        }
        // 높이를 재는 부분은 그대로 두고 안쪽만 새로 그려야, 바뀐 높이를 놓치지 않는다
        .id(size)
        .frame(width: 300.scaled)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(height: contentHeight.map { $0.rounded(.up) }, alignment: .top)
        .modelContainer(todoStore.container)
    }
}

// MARK: - 활성

private struct ActivePanel: View {
    let awake: AwakeController
    let power: PowerStateMonitor
    @Bindable var state: PanelState
    let lidMode: LidModeController
    let safety: SafetyController
    let agents: AgentStatusText
    let todoStore: TodoStore
    let updates: UpdateController
    let openSettings: () -> Void
    let openHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10.scaled) {
            header
            switch state.tab {
            case .awake: AwakeTab(awake: awake, power: power, state: state, lidMode: lidMode, safety: safety, agents: agents, openSettings: openSettings)
            case .todo: TodoTab(store: todoStore, state: state, openHistory: openHistory)
            }
        }
        .padding(.horizontal, 12.scaled)
        .padding(.vertical, 10.scaled)
        .panelBackground(RoundedRectangle(cornerRadius: 14.scaled), passive: false)
    }

    private var header: some View {
        HStack {
            SegmentedPicker(
                items: [(PanelState.Tab.todo, String(localized: "할 일")), (.awake, String(localized: "tab.awake", defaultValue: "깨어 있기", comment: "펼친 창의 탭 이름"))],
                selection: state.tab,
                style: .tab
            ) { state.tab = $0 }
            .help(Self.moveHelp)
            // 빈 곳에만 옮기기 설명을 단다. 줄 전체에 달면 업데이트 알약의 설명을 가린다
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 20.scaled)
                .contentShape(Rectangle())
                .help(Self.moveHelp)
            if let version = updates.availableVersion {
                UpdatePill(version: version, waitsForAwake: updates.installsAfterAwake) {
                    // 창은 평소로 돌려 Sparkle 창을 가리지 않게 한다
                    state.mode = .passive
                    updates.checkForUpdates()
                }
            }
        }
        // 탭 줄을 끌면 창을 옮긴다. 놓으면 그 화면의 가장 가까운 모서리에 붙는다
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in state.onHeaderDrag?(.changed) }
                .onEnded { _ in state.onHeaderDrag?(.ended) }
        )
    }

    private static var moveHelp: String { String(localized: "끌어서 다른 모서리나 화면으로 옮길 수 있어요") }
}

private struct AwakeTab: View {
    let awake: AwakeController
    let power: PowerStateMonitor
    @Bindable var state: PanelState
    let lidMode: LidModeController
    let safety: SafetyController
    let agents: AgentStatusText
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10.scaled) {
            StatusCard(awake: awake, agents: agents)
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
                    Button(String(localized: "화면 끄기")) { awake.turnOffDisplay() }
                        .font(.system(size: 12.scaled))
                        .foregroundStyle(Theme.ink.opacity(0.6))
                    Spacer()
                    Button(String(localized: "깨어 있기 끄기")) { awake.stop() }
                        .font(.system(size: 12.scaled, weight: .semibold))
                        .foregroundStyle(Theme.primaryLight)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2.scaled)
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
        // 다섯 칸이 라벨과 한 줄에 들어가지 않아 라벨을 위로 올린다
        return VStack(alignment: .leading, spacing: 6.scaled) {
            Text(String(localized: "언제까지"))
                .font(.system(size: 12.scaled))
                .foregroundStyle(Theme.ink.opacity(0.5))
            SegmentedPicker(
                items: [
                    (Choice.option(.indefinite), String(localized: "계속")),
                    (.option(.hours(1)), String(localized: "1시간")),
                    (.option(.hours(2)), String(localized: "2시간")),
                    (.pickTime, String(localized: "시각")),
                    (.option(.untilAgentsFinish), String(localized: "에이전트")),
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
        .padding(.leading, 2.scaled)
    }

    private func lidRows(_ lid: (staysAwake: Bool, value: String, detail: String)) -> some View {
        let color = lid.staysAwake ? Theme.good : Theme.bad
        return VStack(alignment: .leading, spacing: 10.scaled) {
            HStack {
                Text(String(localized: "지금 뚜껑을 닫으면"))
                    .font(.system(size: 12.5.scaled))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                Spacer()
                HStack(spacing: 5.scaled) {
                    Circle().fill(lid.staysAwake ? Theme.goodDot : Theme.bad).frame(width: 5.scaled, height: 5.scaled)
                    Text(lid.value)
                        .font(.system(size: 12.scaled, weight: .medium))
                        .foregroundStyle(color)
                }
            }
            Text(lid.detail)
                .font(.system(size: 11.5.scaled))
                .foregroundStyle(Theme.ink.opacity(0.4))
        }
        .padding(.horizontal, 2.scaled)
    }
}

/// "뚜껑 닫아도 유지" 스위치. 권한이 없으면 자물쇠를 눌러 설정 창으로 간다
private struct LidModeRow: View {
    let awake: AwakeController
    let lidMode: LidModeController
    let safety: SafetyController
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8.scaled) {
            VStack(alignment: .leading, spacing: 2.scaled) {
                Text(String(localized: "뚜껑 닫아도 유지"))
                    .font(.system(size: 12.5.scaled))
                    .foregroundStyle(Theme.ink.opacity(canToggle ? 0.85 : 0.45))
                if let note {
                    Text(note.text)
                        .font(.system(size: 11.scaled))
                        .foregroundStyle(note.isError ? Theme.bad : Theme.ink.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if lidMode.setup.status == .notInstalled {
                Button(action: openSettings) {
                    Label(String(localized: "설정"), systemImage: "lock.fill")
                        .font(.system(size: 11.scaled, weight: .medium))
                        .foregroundStyle(Theme.primaryLight)
                }
                .buttonStyle(.plain)
                .help(String(localized: "권한 설치는 설정 창에서 해요"))
            } else {
                Toggle("", isOn: Binding(
                    get: { lidMode.isOn },
                    set: { isOn in if isOn { lidMode.enable() } else { lidMode.disable(interactive: true) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(Theme.primary)
                .disabled(!canToggle)
            }
        }
        .padding(.horizontal, 2.scaled)
    }

    /// 켜져 있으면 언제든 끌 수 있고, 꺼져 있으면 조건이 맞을 때만 켤 수 있다
    private var canToggle: Bool {
        lidMode.isOn || (lidMode.setup.status == .installed && awake.isAwake && safety.lidModeBlock == nil)
    }

    private var note: (text: String, isError: Bool)? {
        if let error = lidMode.lastError { return (error, true) }
        if lidMode.isOn { return nil }
        if lidMode.setup.status == .notInstalled { return (String(localized: "처음 한 번 권한 설치가 필요해요"), false) }
        if !awake.isAwake { return (String(localized: "깨어 있는 동안만 켤 수 있어요"), false) }
        switch safety.lidModeBlock {
        case .lowBattery(let threshold): return (String(localized: "배터리가 \(threshold)% 이하라 켤 수 없어요"), false)
        case .tooHot: return (String(localized: "맥이 뜨거워서 지금은 켤 수 없어요"), false)
        case nil: return nil
        }
    }
}

/// 남은 시간 카드
private struct StatusCard: View {
    let awake: AwakeController
    let agents: AgentStatusText

    var body: some View {
        HStack {
            if let session = awake.current, session.option == .untilAgentsFinish {
                VStack(alignment: .leading, spacing: 2.scaled) {
                    HStack(spacing: 6.scaled) {
                        FlameDot(size: 6.scaled)
                        Text(String(localized: "깨어 있는 중 · 에이전트가 끝날 때까지"))
                            .font(.system(size: 11.scaled, weight: .medium))
                            .foregroundStyle(Theme.flameText)
                    }
                    Text(agents.headline)
                        .font(.system(size: 15.scaled, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if let detail = agents.detail {
                        Text(detail)
                            .font(.system(size: 11.scaled))
                            .foregroundStyle(Theme.ink.opacity(0.5))
                    }
                }
                .help(AgentStatusText.rulesHelp)
                Spacer()
            } else if let session = awake.current {
                VStack(alignment: .leading, spacing: 2.scaled) {
                    HStack(spacing: 6.scaled) {
                        FlameDot(size: 6.scaled)
                        Text(String(localized: "깨어 있는 중") + " · " + (AwakeText.until(session) ?? AwakeText.label(for: session.option)))
                            .font(.system(size: 11.scaled, weight: .medium))
                            .foregroundStyle(Theme.flameText)
                    }
                    if let remaining = awake.remaining {
                        Text("\(Text(RemainingTimeFormat.string(from: remaining)).font(.system(size: 20.scaled, weight: .semibold)).foregroundStyle(Theme.ink))\(Text(String(localized: " 남음")).font(.system(size: 13.scaled, weight: .medium)).foregroundStyle(Theme.ink.opacity(0.5)))")
                            .tracking(-0.3)
                            .monospacedDigit()
                    } else {
                        Text(String(localized: "끌 때까지 깨어 있음"))
                            .font(.system(size: 15.scaled, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                Spacer()
                if awake.remaining != nil {
                    // 세션을 끊지 않고 끝 시각만 미룬다
                    Menu {
                        ForEach(AwakeText.extensions, id: \.label) { item in
                            Button(item.label) { awake.extend(by: item.interval) }
                        }
                    } label: {
                        Text(String(localized: "연장 ›"))
                            .font(.system(size: 12.scaled, weight: .medium))
                            .foregroundStyle(Theme.primaryLight)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(String(localized: "지금 끝 시각에 시간을 더해요"))
                }
            } else {
                VStack(alignment: .leading, spacing: 4.scaled) {
                    HStack(spacing: 6.scaled) {
                        HollowDot(size: 6.scaled)
                        Text(String(localized: "깨어 있기 꺼짐"))
                            .font(.system(size: 11.scaled, weight: .medium))
                            .foregroundStyle(Theme.ink.opacity(0.6))
                    }
                    Text(String(localized: "맥이 평소처럼 잠들어요"))
                        .font(.system(size: 13.scaled, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.5))
                }
                Spacer()
                Button(String(localized: "\(AwakeText.shortLabel(for: awake.lastOption)) 시작 ›")) { awake.startWithLastOption() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.scaled, weight: .medium))
                    .foregroundStyle(Theme.primaryLight)
            }
        }
        .padding(.horizontal, 11.scaled)
        .padding(.vertical, 9.scaled)
        .background(RoundedRectangle(cornerRadius: 10.scaled).fill(Theme.fillCard))
    }
}

/// "시각" 세그먼트를 눌렀을 때 나오는 시각 고르기
private struct TimePickerRow: View {
    let awake: AwakeController
    @Bindable var state: PanelState
    /// 처음에는 지금부터 두 시간 뒤 정각
    @State private var hour = (Calendar.current.component(.hour, from: Date()) + 2) % 24
    @State private var minute = 0

    /// 깨어 있기 끝 시각을 1분 단위로 정할 일은 드물어 5분 단위로 고른다
    private static let minutes = Array(stride(from: 0, to: 60, by: 5))

    var body: some View {
        HStack(spacing: 6.scaled) {
            // macOS 기본 시각 칸은 글자에 비해 칸이 빠듯해서, 시·분을 각각 목록에서 고르는 칸으로 만든다
            ChipMenu(title: AwakeText.hourLabel(hour)) {
                ForEach(0..<24, id: \.self) { value in
                    Button(AwakeText.hourLabel(value)) { hour = value }
                }
            }
            ChipMenu(title: Self.minuteLabel(minute)) {
                ForEach(Self.minutes, id: \.self) { value in
                    Button(Self.minuteLabel(value)) { minute = value }
                }
            }
            Text(preview)
                .font(.system(size: 11.5.scaled))
                .foregroundStyle(Theme.ink.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 0.scaled)
            Button(String(localized: "시작")) {
                state.isPickingTime = false
                awake.start(option)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12.scaled, weight: .semibold))
            .foregroundStyle(Theme.primaryLight)
        }
        .padding(.horizontal, 2.scaled)
    }

    private var option: AwakeOption {
        .timeOfDay(hour: hour, minute: minute)
    }

    /// 이미 지난 시각이면 "내일까지" ("tomorrow")
    private var preview: String {
        let now = Date()
        guard let end = option.endDate(startingAt: now) else { return "" }
        return Calendar.current.isDate(end, inSameDayAs: now) ? String(localized: "까지") : String(localized: "내일까지")
    }

    /// "05분" / ":05"
    private static func minuteLabel(_ minute: Int) -> String {
        String(format: String(localized: "%02d분", comment: "시각 고르기의 분 칸"), minute)
    }
}

/// 누르면 목록이 펼쳐지는 작은 칸 ("오후 6시 ⌃⌄")
private struct ChipMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            HStack(spacing: 4.scaled) {
                Text(title)
                    .font(.system(size: 12.5.scaled, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.scaled, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(0.5))
            }
            .padding(.horizontal, 9.scaled)
            .padding(.vertical, 5.scaled)
            .background(RoundedRectangle(cornerRadius: 6.scaled).fill(Theme.ink.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - 평소

/// 평소 상태: 상태 한 줄 + 설명 한 줄. 클릭은 뒤로 통과한다
private struct PassiveSummary: View {
    let awake: AwakeController
    let power: PowerStateMonitor
    let agents: AgentStatusText
    let updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 8.scaled) {
            if let session = awake.current {
                HStack {
                    HStack(spacing: 7.scaled) {
                        FlameDot(size: 7.scaled)
                        Text(String(localized: "깨어 있는 중"))
                            .font(.system(size: 12.5.scaled, weight: .semibold))
                            .foregroundStyle(Theme.flameTextPassive)
                    }
                    Spacer()
                    if let remaining = awake.remaining {
                        Text("\(Text(RemainingTimeFormat.string(from: remaining)).font(.system(size: 14.scaled, weight: .semibold)).foregroundStyle(Theme.ink))\(Text(String(localized: " 남음")).font(.system(size: 11.scaled, weight: .medium)).foregroundStyle(Theme.ink.opacity(0.6)))")
                            .monospacedDigit()
                    } else if session.option == .untilAgentsFinish {
                        Text(agents.short)
                            .font(.system(size: 12.scaled, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                // 새 버전 표시는 위쪽 줄 오른편이 남은 시간으로 차 있어서 설명 줄 오른편에 둔다
                HStack(alignment: .firstTextBaseline) {
                    detailLine(session)
                    Spacer(minLength: 8.scaled)
                    updateNote
                }
            } else {
                HStack {
                    HStack(spacing: 7.scaled) {
                        HollowDot(size: 7.scaled)
                        Text(String(localized: "깨어 있기 꺼짐"))
                            .font(.system(size: 12.scaled, weight: .medium))
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    }
                    Spacer(minLength: 8.scaled)
                    updateNote
                }
            }
            PassiveTodoList()
        }
        .shadow(color: Theme.textShadow, radius: 1.5, y: 1)
        .padding(.horizontal, 12.scaled)
        .padding(.top, 10.scaled)
        .padding(.bottom, 12.scaled)
        // "깨어 있기 꺼짐" 한 줄일 때도 글자 길이만큼 줄어들지 않고 창 폭을 가득 채운다
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(RoundedRectangle(cornerRadius: 14.scaled), passive: true)
    }

    /// 새 버전이 있으면 "● 새 버전 0.3.0". 평소 창은 클릭이 통과하므로 알리기만 하고, 설치는 펼친 창의 알약에서 한다
    @ViewBuilder private var updateNote: some View {
        if let version = updates.availableVersion {
            HStack(spacing: 5.scaled) {
                Circle().fill(Theme.primary).frame(width: 5.scaled, height: 5.scaled)
                Text(updates.installsAfterAwake ? String(localized: "끝나면 \(version) 설치") : String(localized: "새 버전 \(version)"))
                    .font(.system(size: 11.scaled, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// "오후 4:30까지 · 지금 닫아도 유지됨"
    private func detailLine(_ session: AwakeSession) -> some View {
        let until = AwakeText.until(session) ?? AwakeText.label(for: session.option)
        let base = Text(until).foregroundStyle(Theme.ink.opacity(0.65))
        let line: Text
        if let lid = AwakeText.lidClose(LidClosePrediction.outcome(for: power.snapshot)) {
            let lead = lid.staysAwake ? String(localized: " · 지금 닫아도 ") : String(localized: " · 지금 닫으면 ")
            let value = Text(lid.value)
                .fontWeight(.medium)
                .foregroundStyle(lid.staysAwake ? Theme.goodPassive : Theme.bad)
            line = Text("\(base)\(Text(lead).foregroundStyle(Theme.ink.opacity(0.65)))\(value)")
        } else {
            line = base
        }
        return line.font(.system(size: 11.scaled))
    }
}

// MARK: - 접힘

/// 한 줄로 접어 둔 평소 모습. 클릭은 뒤로 통과한다
private struct CollapsedBar: View {
    let awake: AwakeController
    let agents: AgentStatusText
    let updates: UpdateController

    var body: some View {
        HStack {
            if awake.isAwake {
                HStack(spacing: 7.scaled) {
                    FlameDot(size: 7.scaled)
                    Text("\(Text(String(localized: "깨어 있는 중")).foregroundStyle(Theme.flameTextPassive))\(Text(" · \(shortStatus)").foregroundStyle(Theme.ink))")
                        .font(.system(size: 12.scaled, weight: .semibold))
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: 7.scaled) {
                    HollowDot(size: 7.scaled)
                    Text(String(localized: "깨어 있기 꺼짐"))
                        .font(.system(size: 12.scaled, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
            }
            Spacer()
            CollapsedTodoCount()
            // 새 버전이 있으면 작은 파란 점만 둔다. 펼치면 헤더 알약에서 설치한다
            if updates.availableVersion != nil {
                Circle().fill(Theme.primary).frame(width: 6.scaled, height: 6.scaled)
            }
        }
        .shadow(color: Theme.textShadow, radius: 1.5, y: 1)
        .padding(.leading, 12.scaled)
        .padding(.trailing, 12.scaled)
        .padding(.vertical, 7.scaled)
        // 글자 길이만큼 줄어들지 않고 창 폭을 가득 채운다 (Figma 접힘 시안)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(Capsule(), passive: true)
    }

    private var shortStatus: String {
        if let remaining = awake.remaining { return RemainingTimeFormat.string(from: remaining) }
        if awake.current?.option == .untilAgentsFinish { return agents.short }
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
        HStack(spacing: (style == .tab ? 2 : 1).scaled) {
            ForEach(items, id: \.0) { value, title in
                let isSelected = value == selection
                Button { onSelect(value) } label: {
                    Text(title)
                        .font(.system(size: 11.5.scaled, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(foreground(isSelected))
                        .padding(.horizontal, (style == .tab ? 9 : 6).scaled)
                        .padding(.vertical, 3.scaled)
                        .frame(maxWidth: style == .segment ? .infinity : nil)
                        .background(RoundedRectangle(cornerRadius: 5.scaled).fill(background(isSelected)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.scaled)
        .background(RoundedRectangle(cornerRadius: 7.scaled).fill(Theme.fillTrack))
    }

    private func foreground(_ isSelected: Bool) -> Color {
        switch (style, isSelected) {
        case (.tab, true): Theme.primaryTabText
        case (.tab, false): Theme.ink.opacity(0.45)
        case (.segment, true): Theme.ink
        case (.segment, false): Theme.ink.opacity(0.6)
        }
    }

    private func background(_ isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return style == .tab ? Theme.tabSelectedFill : Theme.segmentSelectedFill
    }
}

/// 펼친 창 머리의 "● 0.3.0 업데이트". 누르면 Sparkle 창에서 바뀐 내용을 보고 설치한다
private struct UpdatePill: View {
    let version: String
    /// 깨어 있기가 끝나면 설치하려고 기다리는 중
    let waitsForAwake: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5.scaled) {
                Circle().fill(Theme.primary).frame(width: 5.scaled, height: 5.scaled)
                Text(waitsForAwake ? String(localized: "update.pill.pending", defaultValue: "끝나면 \(version) 설치", comment: "펼친 창 업데이트 알약: 깨어 있기가 끝나길 기다리는 중") : String(localized: "\(version) 업데이트"))
                    .font(.system(size: 11.scaled, weight: .semibold))
                    .foregroundStyle(Theme.primaryLight)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8.scaled)
            .padding(.vertical, 3.scaled)
            .background(Capsule().fill(Theme.primary.opacity(0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(String(localized: "새 버전에서 바뀐 내용을 보고 설치해요"))
    }
}

private struct FlameDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Theme.flame)
            .frame(width: size, height: size)
            .shadow(color: Theme.flame.opacity(0.9), radius: 3)
    }
}

private struct HollowDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .strokeBorder(Theme.ink.opacity(0.5), lineWidth: 1.1)
            .frame(width: size, height: size)
    }
}

private struct Divider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1.scaled)
    }
}

/// 평소·활성 모두 Liquid Glass. 활성 창은 버튼·작은 글씨가 많아 어두운 색을 더 진하게 섞어 읽기 쉽게 한다
private struct PanelBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let passive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let tint = passive ? Theme.passiveTintOpacity : Theme.activeTintOpacity
        #if DEBUG
        // 그림 저장 모드: 유리 효과는 화면에 합성될 때 그려져 그림에 잡히지 않으므로 단색 바탕으로 그린다
        if DemoData.rendersFlatBackground {
            content.background(shape.fill(Color(light: Color(white: 0.96), dark: Color(white: 0.13))))
        } else {
            content.glassEffect(.regular.tint(Theme.background.opacity(tint)), in: shape)
        }
        #else
        content.glassEffect(.regular.tint(Theme.background.opacity(tint)), in: shape)
        #endif
    }
}

private extension View {
    func panelBackground<S: InsettableShape>(_ shape: S, passive: Bool) -> some View {
        modifier(PanelBackground(shape: shape, passive: passive))
    }
}

// MARK: - 에이전트 문구

/// "에이전트가 끝날 때까지" 옵션에서 보여 줄 문구
struct AgentStatusText {
    let monitor: AgentMonitor
    let phase: AgentAwakeController.Phase

    /// 판단 기준. 상태 카드에 마우스를 올리면 보인다
    static var rulesHelp: String {
        String(localized: """
        Claude Code·Codex가 보내는 신호로 판단해요.
        · 일하는 에이전트가 모두 끝나면 1분 뒤 깨어 있기를 꺼요
        · 명령이 실행 중이면 신호가 없어도 최대 3시간 기다려요
        · 그 밖에 30분 동안 신호가 없으면 끝난 것으로 봐요 (Esc로 중단한 경우 등)
        · 에이전트 프로그램을 닫으면 바로 끝난 것으로 봐요
        """)
    }

    /// "Claude Code 2개 작업 중"
    var headline: String {
        switch phase {
        case .waitingForAgents: return String(localized: "에이전트를 기다리는 중")
        case .finishing: return String(localized: "모두 끝남 · 곧 꺼져요")
        case .working, .inactive:
            let parts = AgentKind.allCases.compactMap { agent -> String? in
                let count = monitor.count(of: agent)
                return count > 0 ? String(localized: "\(agent.displayName) \(count)개") : nil
            }
            if parts.isEmpty { return String(localized: "에이전트를 기다리는 중") }
            return String(localized: "\(parts.joined(separator: " · ")) 작업 중")
        }
    }

    /// "명령 실행 중", "허락을 기다리는 중"
    var detail: String? {
        switch phase {
        case .waitingForAgents: return String(localized: "일을 시작하면 끝날 때까지 깨어 있어요")
        case .finishing: return String(localized: "1분 안에 다시 일하면 이어져요")
        case .working, .inactive:
            let statuses = monitor.activeSessions.map(\.status)
            if statuses.contains(.awaitingPermission) { return String(localized: "허락을 기다리는 에이전트가 있어요") }
            if statuses.contains(.runningCommand) { return String(localized: "명령 실행 중") }
            return nil
        }
    }

    /// 한 줄 요약용: "작업 중 3", "기다리는 중", "곧 꺼짐"
    var short: String {
        switch phase {
        case .waitingForAgents: return String(localized: "기다리는 중")
        case .finishing: return String(localized: "곧 꺼짐")
        case .working, .inactive:
            let count = monitor.activeSessions.count
            return count > 0 ? String(localized: "작업 중 \(count)") : String(localized: "기다리는 중")
        }
    }
}
