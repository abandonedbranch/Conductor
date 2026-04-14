import SwiftUI

@available(iOS 19.0, macOS 26.0, *)
struct ActionGroupView: View {
    let actions: [ActionNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(groups, id: \.status) { group in
                Text(group.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(group.actions) { action in
                    HStack(spacing: 8) {
                        statusIcon(action.status)
                        Text(actionSummary(action))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private struct Group { let status: ActionStatus; let actions: [ActionNode] }

    private var groups: [Group] {
        let order: [ActionStatus] = [.running, .pending, .completed, .failed, .awaitingUser]
        return order.compactMap { status in
            let bucket = actions.filter { $0.status == status }
            return bucket.isEmpty ? nil : Group(status: status, actions: bucket)
        }
    }

    private func actionSummary(_ action: ActionNode) -> String {
        let tools = action.assignedToolNames.joined(separator: ", ")
        if tools.isEmpty { return action.goal }
        return "\(action.goal) — \(tools)"
    }

    @ViewBuilder
    private func statusIcon(_ status: ActionStatus) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .awaitingUser: Image(systemName: "questionmark.circle").foregroundStyle(.orange)
        }
    }
}

private extension ActionStatus {
    var label: String {
        switch self {
        case .running: return "Running"
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .awaitingUser: return "Awaiting your reply"
        }
    }
}
