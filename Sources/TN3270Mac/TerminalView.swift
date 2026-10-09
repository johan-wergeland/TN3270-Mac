import AppKit
import SwiftUI
import TN3270Core

/// SwiftUI wrapper around the AppKit terminal view.
struct TerminalScreenView: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        nsView.model = model
        nsView.needsDisplay = true
    }
}

/// Draws the 3270 presentation space and forwards keyboard / mouse input to the session.
final class TerminalNSView: NSView {
    weak var model: AppModel?

    private let backgroundColor = NSColor.black

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Geometry

    private struct Metrics {
        let font: NSFont
        let boldFont: NSFont
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let origin: CGPoint
    }

    private func computeMetrics(rows: Int, columns: Int) -> Metrics {
        let referenceSize: CGFloat = 100
        let reference = NSFont.monospacedSystemFont(ofSize: referenceSize, weight: .regular)
        let referenceWidth = ("W" as NSString).size(withAttributes: [.font: reference]).width
        let referenceHeight = reference.ascender - reference.descender + reference.leading

        let available = bounds.insetBy(dx: 4, dy: 4)
        let byWidth = available.width / (CGFloat(columns) * referenceWidth / referenceSize)
        let byHeight = available.height / (CGFloat(rows) * referenceHeight * 1.1 / referenceSize)
        let size = max(6, min(byWidth, byHeight).rounded(.down))

        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let cellWidth = ("W" as NSString).size(withAttributes: [.font: font]).width
        let cellHeight = ((font.ascender - font.descender + font.leading) * 1.1).rounded(.up)
        let origin = CGPoint(x: (bounds.width - cellWidth * CGFloat(columns)) / 2,
                             y: (bounds.height - cellHeight * CGFloat(rows)) / 2)
        return Metrics(font: font, boldFont: boldFont, cellWidth: cellWidth, cellHeight: cellHeight, origin: origin)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        guard let model else { return }

        let session = model.session
        let screen = session.screen
        let codePage = session.codePage
        let metrics = computeMetrics(rows: screen.rows, columns: screen.columns)
        let appearances = screen.appearances()

        for row in 0..<screen.rows {
            for column in 0..<screen.columns {
                let address = row * screen.columns + column
                let appearance = appearances[address]
                let rect = CGRect(x: metrics.origin.x + CGFloat(column) * metrics.cellWidth,
                                  y: metrics.origin.y + CGFloat(row) * metrics.cellHeight,
                                  width: metrics.cellWidth, height: metrics.cellHeight)

                var foreground = Self.color(appearance.foreground)
                var background: NSColor? = appearance.background == .default ? nil : Self.color(appearance.background)
                if appearance.reverse {
                    let previousForeground = foreground
                    foreground = background ?? backgroundColor
                    background = previousForeground
                }
                if let background {
                    background.setFill()
                    rect.fill()
                }

                let character = appearance.hidden ? " " : screen.displayCharacter(at: address, codePage: codePage)
                if character != " " {
                    let font = appearance.intensified ? metrics.boldFont : metrics.font
                    let string = String(character) as NSString
                    string.draw(at: CGPoint(x: rect.minX, y: rect.minY),
                                withAttributes: [.font: font, .foregroundColor: foreground])
                }
                if appearance.underscore {
                    foreground.setFill()
                    CGRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 1).fill()
                }
            }
        }

        // Cursor: block in insert mode, underline otherwise.
        if session.is3270Connected {
            let cursorRow = screen.row(of: screen.cursor)
            let cursorColumn = screen.column(of: screen.cursor)
            let rect = CGRect(x: metrics.origin.x + CGFloat(cursorColumn) * metrics.cellWidth,
                              y: metrics.origin.y + CGFloat(cursorRow) * metrics.cellHeight,
                              width: metrics.cellWidth, height: metrics.cellHeight)
            NSColor.white.withAlphaComponent(0.6).setFill()
            if session.insertMode {
                rect.fill(using: .sourceOver)
            } else {
                CGRect(x: rect.minX, y: rect.maxY - 3, width: rect.width, height: 3).fill(using: .sourceOver)
            }
        } else if !session.nvtText.isEmpty {
            (session.nvtText as NSString).draw(
                in: bounds.insetBy(dx: 8, dy: 8),
                withAttributes: [.font: metrics.font, .foregroundColor: NSColor.systemGreen])
        }
    }

    static func color(_ color: HostColor) -> NSColor {
        switch color {
        case .default, .green: return NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.35, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.45, green: 0.6, blue: 1.0, alpha: 1)
        case .red: return NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 1)
        case .pink: return NSColor(calibratedRed: 1.0, green: 0.45, blue: 1.0, alpha: 1)
        case .turquoise: return NSColor(calibratedRed: 0.3, green: 0.95, blue: 0.95, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.35, alpha: 1)
        case .white: return NSColor.white
        }
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        guard let model else { return }
        if let stroke = KeyEventMapper.stroke(for: event), let action = model.keyMap.action(for: stroke) {
            model.perform(action)
            return
        }
        if let text = KeyEventMapper.typedText(for: event) {
            model.type(text)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Allow user-defined bindings that use ⌃ or ⌘ to take priority over menus,
        // but only while the terminal has keyboard focus.
        guard window?.firstResponder === self, let model,
              let stroke = KeyEventMapper.stroke(for: event),
              let action = model.keyMap.action(for: stroke) else {
            return super.performKeyEquivalent(with: event)
        }
        model.perform(action)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model else { return }
        let screen = model.session.screen
        let metrics = computeMetrics(rows: screen.rows, columns: screen.columns)
        let point = convert(event.locationInWindow, from: nil)
        let column = Int(((point.x - metrics.origin.x) / metrics.cellWidth).rounded(.down))
        let row = Int(((point.y - metrics.origin.y) / metrics.cellHeight).rounded(.down))
        model.moveCursor(row: row, column: column)
    }

    @objc func copy(_ sender: Any?) {
        guard let model else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.screenText, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let model, let text = NSPasteboard.general.string(forType: .string) else { return }
        model.paste(text)
    }
}
