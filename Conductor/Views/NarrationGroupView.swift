import SwiftUI

struct NarrationGroupView: View {
    let events: [NarrationEvent]

    var body: some View {
        let grouped = Dictionary(grouping: events, by: \.purpose)

        VStack(alignment: .leading, spacing: 6) {
            ForEach(AgentPurpose.allCases, id: \.self) { purpose in
                if let purposeEvents = grouped[purpose] {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(purpose.displayColor)
                            .frame(width: 8, height: 8)

                        Text(purpose.sectionHeading)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(purpose.displayColor)

                        Text(purposeEvents.last?.message ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
