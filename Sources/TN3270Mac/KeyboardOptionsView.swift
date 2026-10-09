import AppKit
import SwiftUI
import TN3270Core

/// Keyboard options: configure the mapping between Mac keys and 3270 host keys.
struct KeyboardOptionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: Set<KeyStroke> = []
    @State private var filter = ""
    @State private var recordedStroke: KeyStroke?
    @State private var newAction: HostAction = .enter
    @State private var isRecording = false
    @State private var monitor: Any?

    private static let actionOrder: [HostAction: Int] = Dictionary(
        uniqueKeysWithValues: HostAction.allCases.enumerated().map { ($0.element, $0.offset) })

    private var rows: [KeyBinding] {
        model.keyMap.bindings
            .filter { binding in
                filter.isEmpty
                    || binding.action.displayName.localizedCaseInsensitiveContains(filter)
                    || binding.stroke.displayName.localizedCaseInsensitiveContains(filter)
            }
            .sorted { lhs, rhs in
                let left = Self.actionOrder[lhs.action] ?? 0
                let right = Self.actionOrder[rhs.action] ?? 0
                return left == right ? lhs.stroke.displayName < rhs.stroke.displayName : left < right
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Map keys on this Mac to 3270 keys on the z/OS host.")
                .font(.headline)
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)

            Table(rows, selection: $selection) {
                TableColumn("Mac Key") { binding in
                    Text(binding.stroke.displayName)
                        .font(.system(.body, design: .monospaced))
                }
                TableColumn("3270 Function") { binding in
                    Picker("3270 Function", selection: actionBinding(for: binding.stroke)) {
                        ForEach(HostAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .labelsHidden()
                }
            }

            GroupBox("Add Key Binding") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(isRecording ? "Press a key…" : (recordedStroke?.displayName ?? "Record Key")) {
                            startRecording()
                        }
                        .frame(minWidth: 140)
                        Image(systemName: "arrow.right")
                        Picker("3270 Function", selection: $newAction) {
                            ForEach(HostAction.allCases) { action in
                                Text(action.displayName).tag(action)
                            }
                        }
                        .labelsHidden()
                        Button("Assign") {
                            if let stroke = recordedStroke {
                                model.keyMap.bind(stroke, to: newAction)
                                selection = [stroke]
                                recordedStroke = nil
                            }
                        }
                        .disabled(recordedStroke == nil)
                    }
                    if let stroke = recordedStroke, let existing = model.keyMap.action(for: stroke) {
                        Text("\(stroke.displayName) is currently mapped to \(existing.displayName). Assigning will replace it.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(4)
            }

            HStack {
                Button("Remove Selected") {
                    for stroke in selection { model.keyMap.unbind(stroke) }
                    selection = []
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button("Restore Defaults") {
                    model.keyMap = .default
                    selection = []
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 520)
        .onDisappear { stopRecording() }
    }

    private func actionBinding(for stroke: KeyStroke) -> Binding<HostAction> {
        Binding(
            get: { model.keyMap.action(for: stroke) ?? .enter },
            set: { model.keyMap.bind(stroke, to: $0) }
        )
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let stroke = KeyEventMapper.stroke(for: event) {
                recordedStroke = stroke
                if let existing = model.keyMap.action(for: stroke) { newAction = existing }
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
