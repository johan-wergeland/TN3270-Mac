/// Functions of the 3270 keyboard that can be bound to client keys.
public enum HostAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case enter, clear
    case pf1, pf2, pf3, pf4, pf5, pf6, pf7, pf8, pf9, pf10, pf11, pf12
    case pf13, pf14, pf15, pf16, pf17, pf18, pf19, pf20, pf21, pf22, pf23, pf24
    case pa1, pa2, pa3
    case attn, sysreq, reset
    case tab, backtab, home, newline
    case cursorUp, cursorDown, cursorLeft, cursorRight
    case backspace, delete, eraseEOF, eraseInput, insert
    case dup, fieldMark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .enter: return "Enter"
        case .clear: return "Clear"
        case .attn: return "Attention (ATTN)"
        case .sysreq: return "System Request"
        case .reset: return "Reset"
        case .tab: return "Field Tab"
        case .backtab: return "Field Backtab"
        case .home: return "Home"
        case .newline: return "New Line"
        case .cursorUp: return "Cursor Up"
        case .cursorDown: return "Cursor Down"
        case .cursorLeft: return "Cursor Left"
        case .cursorRight: return "Cursor Right"
        case .backspace: return "Backspace"
        case .delete: return "Delete Character"
        case .eraseEOF: return "Erase EOF"
        case .eraseInput: return "Erase Input"
        case .insert: return "Insert Mode"
        case .dup: return "Dup"
        case .fieldMark: return "Field Mark"
        default: return rawValue.uppercased()
        }
    }

    /// The program function key number (1-24), if this is a PF key.
    public var pfNumber: Int? {
        guard rawValue.hasPrefix("pf"), let number = Int(rawValue.dropFirst(2)) else { return nil }
        return number
    }

    /// The PF key action for a number (1-24).
    public static func pf(_ number: Int) -> HostAction? { HostAction(rawValue: "pf\(number)") }
}

/// Modifier keys of the client keyboard.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// Symbols in the conventional macOS order (⌃⌥⇧⌘).
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

/// A key on the client keyboard plus modifiers.
///
/// `key` is either a named key (see `KeyStroke.Named`) or a single lowercase
/// character for printable keys.
public struct KeyStroke: Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: KeyModifiers

    public init(_ key: String, _ modifiers: KeyModifiers = []) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    /// Names used for non-printable keys.
    public enum Named {
        public static let `return` = "Return"
        public static let enter = "Enter"
        public static let tab = "Tab"
        public static let backspace = "Backspace"
        public static let delete = "Delete"
        public static let escape = "Escape"
        public static let home = "Home"
        public static let end = "End"
        public static let pageUp = "PageUp"
        public static let pageDown = "PageDown"
        public static let up = "Up"
        public static let down = "Down"
        public static let left = "Left"
        public static let right = "Right"
        public static let insert = "Insert"
        public static let clear = "Clear"
        public static func function(_ number: Int) -> String { "F\(number)" }
    }

    /// Human readable description, e.g. "⌃⇧F1".
    public var displayName: String {
        let name: String
        switch key {
        case Named.return: name = "↩ Return"
        case Named.enter: name = "⌤ Enter"
        case Named.tab: name = "⇥ Tab"
        case Named.backspace: name = "⌫ Backspace"
        case Named.delete: name = "⌦ Delete"
        case Named.escape: name = "⎋ Esc"
        case Named.up: name = "↑"
        case Named.down: name = "↓"
        case Named.left: name = "←"
        case Named.right: name = "→"
        case " ": name = "Space"
        default: name = key.count == 1 ? key.uppercased() : key
        }
        return modifiers.symbols + name
    }
}

/// A single key binding.
public struct KeyBinding: Codable, Hashable, Identifiable, Sendable {
    public var stroke: KeyStroke
    public var action: HostAction

    public var id: KeyStroke { stroke }

    public init(_ stroke: KeyStroke, _ action: HostAction) {
        self.stroke = stroke
        self.action = action
    }
}

/// Maps client key strokes to 3270 host keys.
public struct KeyMap: Codable, Equatable, Sendable {
    public private(set) var bindings: [KeyBinding]

    public init(bindings: [KeyBinding]) {
        self.bindings = []
        for binding in bindings { bind(binding.stroke, to: binding.action) }
    }

    /// The action bound to a key stroke, if any.
    public func action(for stroke: KeyStroke) -> HostAction? {
        bindings.first(where: { $0.stroke == stroke })?.action
    }

    /// All key strokes bound to an action.
    public func strokes(for action: HostAction) -> [KeyStroke] {
        bindings.filter { $0.action == action }.map(\.stroke)
    }

    /// Binds a key stroke to an action, replacing any existing binding for the stroke.
    public mutating func bind(_ stroke: KeyStroke, to action: HostAction) {
        if let index = bindings.firstIndex(where: { $0.stroke == stroke }) {
            bindings[index].action = action
        } else {
            bindings.append(KeyBinding(stroke, action))
        }
    }

    /// Removes the binding for a key stroke.
    public mutating func unbind(_ stroke: KeyStroke) {
        bindings.removeAll { $0.stroke == stroke }
    }

    /// The default keyboard layout.
    public static let `default`: KeyMap = {
        typealias N = KeyStroke.Named
        var list: [KeyBinding] = [
            KeyBinding(KeyStroke(N.return), .enter),
            KeyBinding(KeyStroke(N.enter), .enter),
            KeyBinding(KeyStroke(N.return, .shift), .newline),
            KeyBinding(KeyStroke(N.tab), .tab),
            KeyBinding(KeyStroke(N.tab, .shift), .backtab),
            KeyBinding(KeyStroke(N.escape), .clear),
            KeyBinding(KeyStroke(N.clear), .clear),
            KeyBinding(KeyStroke(N.backspace), .backspace),
            KeyBinding(KeyStroke(N.delete), .delete),
            KeyBinding(KeyStroke(N.home), .home),
            KeyBinding(KeyStroke(N.end), .eraseEOF),
            KeyBinding(KeyStroke(N.insert), .insert),
            KeyBinding(KeyStroke(N.pageUp), .pf7),
            KeyBinding(KeyStroke(N.pageDown), .pf8),
            KeyBinding(KeyStroke(N.up), .cursorUp),
            KeyBinding(KeyStroke(N.down), .cursorDown),
            KeyBinding(KeyStroke(N.left), .cursorLeft),
            KeyBinding(KeyStroke(N.right), .cursorRight),
            KeyBinding(KeyStroke("r", .control), .reset),
            KeyBinding(KeyStroke("c", .control), .attn),
            KeyBinding(KeyStroke("s", .control), .sysreq),
            KeyBinding(KeyStroke("e", .control), .eraseEOF),
            KeyBinding(KeyStroke("i", .control), .insert),
            KeyBinding(KeyStroke("1", .control), .pa1),
            KeyBinding(KeyStroke("2", .control), .pa2),
            KeyBinding(KeyStroke("3", .control), .pa3),
        ]
        for number in 1...12 {
            list.append(KeyBinding(KeyStroke(N.function(number)), HostAction.pf(number)!))
            list.append(KeyBinding(KeyStroke(N.function(number), .shift), HostAction.pf(number + 12)!))
        }
        for number in 13...20 {
            list.append(KeyBinding(KeyStroke(N.function(number)), HostAction.pf(number)!))
        }
        return KeyMap(bindings: list)
    }()
}
