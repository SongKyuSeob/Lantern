import AppKit
import Carbon.HIToolbox

/// 전역 단축키 조합. 키보드 배열과 무관한 키 번호(keyCode)로 저장한다
struct KeyShortcut: Codable, Equatable {
    let keyCode: UInt16
    /// ⌘⌥⌃⇧만 담는다
    let modifiers: NSEvent.ModifierFlags


    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifiers)
    }

    /// ⌃ 또는 ⌥가 꼭 들어가야 한다.
    /// ⌘ 조합(⌘W, ⌘C, ⌘⇧K…)은 대부분 앱이 이미 쓰고 있어서, 전역 단축키로 가져가면 모든 앱에서 그 기능이 막힌다
    var isValid: Bool {
        !modifiers.intersection([.control, .option]).isEmpty
    }

    /// "⌃⌥L"
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + Self.keyName(keyCode)
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    // MARK: - 저장

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: try container.decode(UInt.self, forKey: .modifiers))
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }

    // MARK: - 키 이름

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "Esc",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// 키 번호를 글자로. 한글 입력 중이어도 영문 배열 기준 글자를 보여 준다
    static func keyName(_ keyCode: UInt16) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

/// 전역 단축키로 하는 일
enum ShortcutAction: String, CaseIterable {
    /// 메뉴바 아이콘 왼쪽 클릭과 같음 (평소 ↔ 활성)
    case toggle
    /// 평소 창 숨기기 ↔ 보이기
    case hide

    var title: String {
        switch self {
        case .toggle: "창 열기·닫기"
        case .hide: "창 숨기기·보이기"
        }
    }

    /// ⌃⌥L: 앱들이 잘 쓰지 않는 ⌃⌥ 조합에 Lantern의 L. 숨기기는 같은 키에 ⇧만 더한다
    /// (⌃⌥H는 JetBrains IDE의 호출 계층 보기와 겹쳐서 쓰지 않음)
    var defaultShortcut: KeyShortcut {
        switch self {
        case .toggle: KeyShortcut(keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .option])
        case .hide: KeyShortcut(keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .option, .shift])
        }
    }

    fileprivate var hotKeyNumber: UInt32 {
        switch self {
        case .toggle: 1
        case .hide: 2
        }
    }
}

/// 전역 단축키를 macOS에 등록하고, 눌리면 `onPress`를 부른다.
///
/// Carbon의 `RegisterEventHotKey`를 쓴다. 손쉬운 사용 권한이 필요 없고, 등록한 조합만 받는다.
/// 설정은 UserDefaults에 저장한다. 저장된 값이 없으면 기본값, 사용자가 끄면 "끔"을 저장한다.
@Observable
final class GlobalShortcutController {
    private(set) var shortcuts: [ShortcutAction: KeyShortcut] = [:]
    /// 다른 앱이 이미 같은 조합을 쓰고 있어 등록하지 못한 동작
    private(set) var failedActions: Set<ShortcutAction> = []

    @ObservationIgnored var onPress: ((ShortcutAction) -> Void)?
    @ObservationIgnored private var hotKeys: [ShortcutAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?
    private let defaults: UserDefaults

    private static let signature = OSType(0x4C4E544E) // "LNTN"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in ShortcutAction.allCases where !defaults.bool(forKey: Self.disabledKey(action)) {
            shortcuts[action] = defaults.data(forKey: Self.shortcutKey(action))
                .flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) }
                .flatMap { $0.isValid ? $0 : nil }
                ?? action.defaultShortcut
        }
    }

    private static func shortcutKey(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }
    private static func disabledKey(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)Disabled" }

    func shortcut(for action: ShortcutAction) -> KeyShortcut? {
        shortcuts[action]
    }

    /// 다른 동작이 이미 쓰고 있는 조합이면 그 동작
    func conflict(_ shortcut: KeyShortcut, for action: ShortcutAction) -> ShortcutAction? {
        shortcuts.first { $0.key != action && $0.value == shortcut }?.key
    }

    func start() {
        installHandler()
        registerAll()
    }

    /// 새 조합으로 바꾼다. `nil`이면 끈다
    func update(_ action: ShortcutAction, to newShortcut: KeyShortcut?) {
        shortcuts[action] = newShortcut
        if let newShortcut, let data = try? JSONEncoder().encode(newShortcut) {
            defaults.set(data, forKey: Self.shortcutKey(action))
            defaults.set(false, forKey: Self.disabledKey(action))
        } else {
            defaults.set(true, forKey: Self.disabledKey(action))
        }
        registerAll()
    }

    /// 새 조합을 입력받는 동안에는 지금 조합이 눌려도 동작하지 않게 잠시 내린다
    func suspend() {
        unregisterAll()
    }

    func resume() {
        registerAll()
    }

    // MARK: - 등록

    private func registerAll() {
        unregisterAll()
        var failed: Set<ShortcutAction> = []
        for (action, shortcut) in shortcuts {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.hotKeyNumber)
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                hotKeys[action] = ref
            } else {
                failed.insert(action)
            }
        }
        if failed != failedActions { failedActions = failed }
    }

    private func unregisterAll() {
        for ref in hotKeys.values { UnregisterEventHotKey(ref) }
        hotKeys = [:]
    }

    private func installHandler() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard id.signature == GlobalShortcutController.signature,
                  let action = ShortcutAction.allCases.first(where: { $0.hotKeyNumber == id.id })
            else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<GlobalShortcutController>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { controller.onPress?(action) }
            return noErr
        }, 1, &eventType, context, &handler)
    }
}
