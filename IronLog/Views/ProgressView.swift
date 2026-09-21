import SwiftUI

struct ProgressView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TitleBlock(title: "Progress", subtitle: "Your training story, in one place")
                Picker("Progress view", selection: $app.progressSection) {
                    ForEach(ProgressSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("progress-section-picker")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 4)

            Group {
                switch app.progressSection {
                case .stats:
                    StatsView(showTitle: false)
                        .accessibilityIdentifier("progress-stats-view")
                case .history:
                    HistoryView(showTitle: false)
                        .accessibilityIdentifier("progress-history-view")
                }
            }
            .id(app.progressSection)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .animation(AppMotion.quick, value: app.progressSection)
    }
}
