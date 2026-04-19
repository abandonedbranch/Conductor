import SwiftUI

struct ProseInputView: View {
    @Binding var prose: String
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Describe a workflow…", text: $prose, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .disabled(isRunning)
            HStack {
                Spacer()
                Button(isRunning ? "Running…" : "Run") { onRun() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isRunning || prose.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}
