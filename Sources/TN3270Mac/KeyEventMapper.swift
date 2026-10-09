import AppKit
import TN3270Core

/// Converts AppKit key events into platform independent `KeyStroke`s.
enum KeyEventMapper {
    /// Virtual key codes of non-printable keys (kVK_* from HIToolbox/Events.h).
    private static let namedKeys: [UInt16: String] = {
        typealias N = KeyStroke.Named
        var keys: [UInt16: String] = [
            36: N.return, 76: N.enter, 48: N.tab, 51: N.backspace, 117: N.delete,
            53: N.escape, 115: N.home, 119: N.end, 116: N.pageUp, 121: N.pageDown,
            126: N.up, 125: N.down, 123: N.left, 124: N.right, 114: N.insert, 71: N.clear,
        ]
        let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                      103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        for (index, code) in functionKeys.enumerated() {
            keys[code] = N.function(index + 1)
        }
        return keys
    }()

    static func modifiers(of event: NSEvent) -> KeyModifiers {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    /// The key stroke for a key down event, or nil for unsupported keys.
    static func stroke(for event: NSEvent) -> KeyStroke? {
        let modifiers = modifiers(of: event)
        if let name = namedKeys[event.keyCode] {
            return KeyStroke(name, modifiers)
        }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else {
            return nil
        }
        return KeyStroke(characters, modifiers)
    }

    /// Text typed by an event that should be sent to the host as data.
    static func typedText(for event: NSEvent) -> String? {
        let modifiers = modifiers(of: event)
        guard !modifiers.contains(.command), !modifiers.contains(.control),
              namedKeys[event.keyCode] == nil,
              let characters = event.characters, !characters.isEmpty else { return nil }
        let printable = characters.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
        }
        return printable ? characters : nil
    }
}
