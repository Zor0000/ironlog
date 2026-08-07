import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var app: AppState
    @State private var chartExercise: String?
    @State private var showAllRecords = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TitleBlock(title: "Your Stats", subtitle: "Keep grinding, \(app.user?.displayName ?? "athlete")")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    StatCard(value: "\(app.sessions.count)", label: "Sessions")
                        .entrance(0)
                    StatCard(value: "\(app.stats.streak)", label: "Day Streak")
                        .entrance(1)
                    StatCard(value: "\(app.stats.sets)", label: "Total Sets")
                        .entrance(2)
                    StatCard(value: volumeText, label: "Volume (\(currentWeightUnit.label))")
                        .entrance(3)
                }
                progressCard
                    .entrance(4)
                weekCard
                    .entrance(5)
                waterCard
                    .entrance(6)
                recordsCard
                    .entrance(7)
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .animation(AppMotion.quick, value: app.sessions)
        .animation(AppMotion.quick, value: app.waterToday)
    }

    private var volumeText: String {
        let volume = displayWeight(app.stats.volume)
        return volume >= 1000 ? String(format: "%.1fk", volume / 1000) : "\(Int(volume.rounded()))"
    }

    // MARK: Per-exercise progress chart
    // Plots top-set weight (not est. 1RM): it's what the user actually lifted,
    // needs no formula caveats, and matches the numbers they see in History.

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress")
                    .cardLabel()
                Spacer()
                if !chartableExercises.isEmpty {
                    Menu {
                        ForEach(chartableExercises, id: \.self) { name in
                            Button(name) {
                                NativeFeedback.selection()
                                chartExercise = name
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(selectedExercise ?? "")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.surface2)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                    }
                    .accessibilityLabel("Choose exercise")
                }
            }

            let points = chartPoints
            if points.count >= 2 {
                Chart(points, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Top set", point.weight))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Date", point.date), y: .value("Top set", point.weight))
                        .foregroundStyle(Theme.accent)
                }
                .chartYAxisLabel("Top set (\(currentWeightUnit.label))", alignment: .trailing)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            } else {
                Text(points.count == 1
                     ? "One session logged — one more and the trend line appears."
                     : "Log weighted sets to see progress over time.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
        .cardStyle()
    }

    /// Exercises that have at least one weighted set in history, most recent first.
    private var chartableExercises: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for session in app.sessions {
            for exercise in session.exercises where exercise.sets.contains(where: { ($0.weight ?? 0) > 0 }) {
                if seen.insert(exercise.name).inserted {
                    names.append(exercise.name)
                }
            }
        }
        return names
    }

    private var selectedExercise: String? {
        if let chartExercise, chartableExercises.contains(chartExercise) {
            return chartExercise
        }
        return chartableExercises.first
    }

    /// (date, top-set weight in the display unit) per session, oldest first.
    private var chartPoints: [(date: Date, weight: Double)] {
        guard let name = selectedExercise else { return [] }
        return app.sessions.reversed().compactMap { session in
            let top = session.exercises
                .filter { $0.name == name }
                .flatMap(\.sets)
                .compactMap(\.weight)
                .max()
            guard let top, top > 0 else { return nil }
            return (session.createdAt, displayWeight(top))
        }
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .cardLabel()
            HStack(spacing: 5) {
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    let completed = app.sessions.contains { $0.createdAt.dayKey == date.dayKey }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(completed ? Theme.accent : Theme.border)
                        .frame(height: 16)
                        .scaleEffect(x: completed ? 1 : 0.96, y: completed ? 1 : 0.92)
                        .shadow(color: Theme.accent.opacity(completed ? 0.16 : 0), radius: 8)
                        .entrance(index, offset: 8)
                }
            }
            HStack {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .cardStyle()
    }

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Water Intake Today")
                .cardLabel()
            HStack {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 5), count: 8), spacing: 5) {
                    ForEach(0..<8, id: \.self) { index in
                        Button {
                            NativeFeedback.selection()
                            withAnimation(AppMotion.quick) {
                                app.setWater(index: index)
                            }
                        } label: {
                            Image(systemName: index < app.waterToday ? "drop.fill" : "drop")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(Theme.blue)
                                .background(index < app.waterToday ? Theme.blue.opacity(0.18) : Theme.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(index < app.waterToday ? Theme.blue : Theme.border, lineWidth: 1.5))
                                .scaleEffect(index < app.waterToday ? 1 : 0.96)
                                .symbolEffect(.bounce, value: index < app.waterToday)
                        }
                        .buttonStyle(TactileButtonStyle())
                        .accessibilityLabel("Glass \(index + 1)")
                        .accessibilityValue(index < app.waterToday ? "Filled" : "Empty")
                    }
                }
                Spacer()
                Text("\(app.waterToday)/8 glasses")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted2)
            }
        }
        .cardStyle()
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Personal Records")
                Image(systemName: "trophy")
            }
            .cardLabel()

            if app.personalRecords.isEmpty {
                Text("Complete workouts to see your PRs.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted2)
            } else {
                let sorted = app.personalRecords.values.sorted { $0.exerciseName < $1.exerciseName }
                let shown = showAllRecords ? sorted : Array(sorted.prefix(recordsLimit))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, record in
                    HStack {
                        Text(record.exerciseName)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(record.weight > 0 ? "\(formatWeight(record.weight)) x \(clean(record.reps)) reps" : "BW x \(clean(record.reps))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 7)
                    .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
                    .entrance(index, offset: 8)
                }
                if sorted.count > recordsLimit {
                    Button {
                        NativeFeedback.selection()
                        withAnimation(AppMotion.quick) { showAllRecords.toggle() }
                    } label: {
                        Text(showAllRecords ? "Show less" : "Show all \(sorted.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .buttonStyle(TactileButtonStyle())
                }
            }
        }
        .cardStyle()
    }

    private var recordsLimit: Int { 5 }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = weekday == 1 ? -6 : 2 - weekday
        let monday = calendar.date(byAdding: .day, value: daysFromMonday, to: today) ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
}

struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 36, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
