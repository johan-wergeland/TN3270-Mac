import SwiftUI
import TN3270Core

/// Connection options page: host, port, EBCDIC code page, terminal model and TLS.
struct ConnectionOptionsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ConnectionSettings()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section("Host") {
                    TextField("Host name or IP address", text: $draft.host)
                    TextField("Port", value: $draft.port, format: .number.grouping(.never))
                    TextField("LU name (optional)", text: $draft.luName)
                }

                Section("Terminal") {
                    Picker("EBCDIC code page", selection: $draft.codePageID) {
                        ForEach(CodePage.all) { page in
                            Text("\(page.id) – \(page.name)").tag(page.id)
                        }
                    }
                    Picker("Terminal model", selection: $draft.model) {
                        ForEach(TerminalModel.allCases) { terminalModel in
                            Text(terminalModel.displayName).tag(terminalModel)
                        }
                    }
                    Toggle("Negotiate TN3270E", isOn: $draft.useTN3270E)
                }

                Section("Security") {
                    Toggle("Use SSL/TLS", isOn: $draft.useTLS)
                    Picker("Minimum TLS version", selection: $draft.minimumTLSVersion) {
                        ForEach(TLSVersion.allCases) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                    .disabled(!draft.useTLS)
                    Toggle("Verify server certificate", isOn: $draft.verifyCertificate)
                        .disabled(!draft.useTLS)
                }
            }
            .formStyle(.grouped)

            if !draft.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(draft.validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Button("Revert") { draft = model.settings }
                    .disabled(draft == model.settings)
                Spacer()
                Button("Save") { save() }
                    .disabled(!draft.isValid)
                Button("Save & Connect") {
                    save()
                    model.disconnect()
                    model.connect()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 460, minHeight: 520)
        .onAppear {
            if !loaded {
                draft = model.settings
                loaded = true
            }
        }
        .onChange(of: draft.useTLS) { useTLS in
            // Suggest the conventional ports when toggling TLS.
            if useTLS && draft.port == 23 { draft.port = 992 }
            if !useTLS && draft.port == 992 { draft.port = 23 }
        }
    }

    private func save() {
        draft.host = draft.host.trimmingCharacters(in: .whitespaces)
        draft.luName = draft.luName.trimmingCharacters(in: .whitespaces).uppercased()
        model.settings = draft
    }
}
