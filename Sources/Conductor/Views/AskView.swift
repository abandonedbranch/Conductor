import SwiftUI

struct AskView: View {
    let role: String
    let kind: AtomKind
    let onSubmit: (AtomValue) -> Void

    @State private var text = ""
    @State private var number: Double = 0
    @State private var date = Date()
    @State private var choice: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt)
                .font(.headline)
            field
            Button("Continue") { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
        }
        .padding()
        .frame(minWidth: 320)
    }

    private var prompt: String {
        switch kind {
        case .url:           "Enter URL for \(role)"
        case .number:        "Enter number for \(role)"
        case .date:          "Pick a date for \(role)"
        case .text:          "Enter text for \(role)"
        case .choice:        "Choose a value for \(role)"
        }
    }

    @ViewBuilder
    private var field: some View {
        switch kind {
        case .url:
            TextField("https://…", text: $text)
                .textFieldStyle(.roundedBorder)
        case .number:
            Stepper(value: $number, in: 0...1000) { Text("\(Int(number))") }
        case .date:
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
        case .text:
            TextField("", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
        case let .choice(_, cases):
            Picker("", selection: $choice) {
                ForEach(cases, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .onAppear { if choice.isEmpty { choice = cases.first ?? "" } }
        }
    }

    private var canSubmit: Bool {
        switch kind {
        case .url:    URL(string: text)?.scheme != nil
        case .text:   !text.isEmpty
        case .choice: !choice.isEmpty
        default:      true
        }
    }

    private func submit() {
        switch kind {
        case .url:           if let u = URL(string: text) { onSubmit(.url(u)) }
        case .number:        onSubmit(.number(number))
        case .date:          onSubmit(.date(date))
        case .text:          onSubmit(.text(text))
        case let .choice(ns, _): onSubmit(.choice(namespace: ns, value: choice))
        }
    }
}
