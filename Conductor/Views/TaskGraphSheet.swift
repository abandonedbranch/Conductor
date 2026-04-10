import SwiftUI

struct TaskGraphSheet: View {
    let narrationEvents: [NarrationEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let grouped = Dictionary(grouping: narrationEvents, by: \.purpose)

                ForEach(AgentPurpose.allCases, id: \.self) { purpose in
                    if let events = grouped[purpose] {
                        Section {
                            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                                HStack {
                                    Circle()
                                        .fill(purpose.displayColor)
                                        .frame(width: 8, height: 8)

                                    Text(event.message)
                                        .font(.subheadline)

                                    Spacer()

                                    Text(event.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } header: {
                            Label(purpose.sectionHeading, systemImage: purposeIcon(purpose))
                                .foregroundStyle(purpose.displayColor)
                        }
                    }
                }
            }
            .navigationTitle("Task Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func purposeIcon(_ purpose: AgentPurpose) -> String {
        switch purpose {
        case .overview: return "book"
        case .research: return "magnifyingglass"
        case .web: return "globe"
        case .build: return "gearshape.2"
        }
    }
}
