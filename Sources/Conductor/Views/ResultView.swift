import SwiftUI

struct ResultView: View {
    let summary: SummaryProduced?
    let papers: [Paper]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let summary {
                    GroupBox("Summary") {
                        Text(summary.summary).font(.body)
                    }
                }
                if !papers.isEmpty {
                    GroupBox("Papers") {
                        ForEach(papers, id: \.identifier) { p in
                            VStack(alignment: .leading) {
                                Text(p.title).font(.headline)
                                if !p.abstract.isEmpty { Text(p.abstract).font(.caption).lineLimit(4) }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
