import SwiftUI

struct PipelineView: View {
    let steps: [Step]
    let statuses: [StepStatus]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(zip(steps, statuses)), id: \.0.id) { step, status in
                StepRowView(step: step, status: status)
            }
        }
        .padding(.horizontal)
    }
}
