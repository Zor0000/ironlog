import SwiftUI

/// What a bundled split *means*, in the words a first-time user needs to pick
/// one: a glyph, a plain-language one-liner and a realistic weekly cadence.
///
/// Keyed by the split's name in `workouts.json`. Anything the catalog adds
/// later that isn't listed here still renders — `describe(_:days:)` falls back
/// to a generic card built from the split's day count — so the picker can
/// never drop a selectable split just because it has no copy yet.
struct SplitProgram: Equatable {
    let name: String
    let systemImage: String
    let summary: String
    let cadence: String

    private static let bundled: [String: SplitProgram] = [
        "Full Body": SplitProgram(
            name: "Full Body",
            systemImage: "figure.strengthtraining.traditional",
            summary: "Every major muscle in one session",
            cadence: "2–3 days / week"
        ),
        "PPL": SplitProgram(
            name: "PPL",
            systemImage: "arrow.triangle.2.circlepath",
            summary: "Push, pull and legs on rotating days",
            cadence: "3–6 days / week"
        ),
        "Upper/Lower": SplitProgram(
            name: "Upper/Lower",
            systemImage: "rectangle.split.1x2",
            summary: "Alternate upper- and lower-body days",
            cadence: "4 days / week"
        ),
        "Single Muscle": SplitProgram(
            name: "Single Muscle",
            systemImage: "scope",
            summary: "Bring up one muscle group at a time",
            cadence: "Any day · add to a split"
        ),
    ]

    static func describe(_ split: String, days: [SplitDay]?) -> SplitProgram {
        if let known = bundled[split] { return known }
        let count = days?.count ?? 0
        return SplitProgram(
            name: split,
            systemImage: "square.grid.2x2",
            summary: count > 0 ? "\(count) training day\(count == 1 ? "" : "s") to rotate through" : "One session covers the whole plan",
            cadence: count > 0 ? "\(count) days / week" : "Flexible"
        )
    }

    /// Stable identifier for tests and evidence capture: `split-ppl`,
    /// `split-upper-lower`, `split-single-muscle`.
    var accessibilityIdentifier: String {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return "split-\(slug)"
    }
}

/// Two-column grid of program cards. Collapses to one column at accessibility
/// text sizes so the summary never wraps into a sliver next to the glyph.
struct SplitProgramGrid: View {
    let splits: [String]
    let days: [String: [SplitDay]]
    let onSelect: (String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(Array(splits.enumerated()), id: \.element) { index, split in
                let program = SplitProgram.describe(split, days: days[split])
                SplitProgramCard(program: program) {
                    onSelect(split)
                }
                .entrance(index + 1)
            }
        }
    }
}

struct SplitProgramCard: View {
    let program: SplitProgram
    let action: () -> Void

    var body: some View {
        Button {
            NativeFeedback.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: program.systemImage)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(program.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Label(program.cadence, systemImage: "calendar")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .labelStyle(.titleAndIcon)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel(program.name)
        .accessibilityValue("\(program.summary). \(program.cadence)")
        .accessibilityHint("Choose a training day")
        .accessibilityIdentifier(program.accessibilityIdentifier)
    }
}

/// The one thing after the split choices: a calm pointer to the Exercise
/// Finder for anyone who doesn't yet know what to train.
struct ExerciseFinderCallout: View {
    let action: () -> Void

    var body: some View {
        Button {
            NativeFeedback.light()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not sure where to start?")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Pick a muscle and let the Exercise Finder choose")
                        .font(.caption)
                        .foregroundStyle(Theme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityLabel("Not sure where to start? Open the Exercise Finder")
        .accessibilityIdentifier("exercise-finder-entry-button")
    }
}
