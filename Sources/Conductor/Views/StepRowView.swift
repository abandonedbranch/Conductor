import SwiftUI

struct StepRowView: View {
    let step: Step
    let status: StepStatus

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading) {
                Text(step.verb.rawValue).font(.headline)
                if case let .failed(msg) = status { Text(msg).font(.caption).foregroundStyle(.red) }
                if case let .awaitingInput(role, _) = status { Text("waiting: \(role)").font(.caption) }
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.05)))
    }

    private var icon: String {
        switch status {
        case .idle: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .awaitingInput: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .awaitingInput: .orange
        default: .secondary
        }
    }
}
