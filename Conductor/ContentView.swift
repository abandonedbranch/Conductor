import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            ProseInputView(prose: $model.prose, isRunning: model.isRunning) {
                Task { await model.run() }
            }
            Divider()
            PipelineView(
                steps: model.steps,
                statuses: Projections.pipelineStatus(log: model.log.events, steps: model.steps)
            )
            Divider()
            ResultView(
                summary: Projections.articleSummary(log: model.log.events),
                papers: Projections.searchResults(log: model.log.events)?.papers ?? []
            )
        }
        .frame(minWidth: 640, minHeight: 540)
        .sheet(item: askBinding) { ask in
            AskView(role: ask.role, kind: ask.kind) { value in
                model.submitAsk(value)
            }
            .padding()
        }
    }

    private var askBinding: Binding<PendingAsk?> {
        Binding(
            get: { model.pendingAsk },
            set: { _ in }
        )
    }
}
