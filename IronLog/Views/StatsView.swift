import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var app: AppState

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
                    StatCard(value: volumeText, label: "Volume (kg)")
                        .entrance(3)
                }
                weekCard
                    .entrance(4)
                waterCard
                    .entrance(5)
                recordsCard
                    .entrance(6)
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .animation(AppMotion.quick, value: app.sessions)
        .animation(AppMotion.quick, value: app.waterToday)
    }

    private var volumeText: String {
        app.stats.volume >= 1000 ? String(format: "%.1fk", app.stats.volume / 1000) : "\(Int(app.stats.volume.rounded()))"
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
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
                        .font(.system(size: 9))
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
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
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
                    }
                }
                Spacer()
                Text("\(app.waterToday)/8 glasses")
                    .font(.system(size: 11))
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
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)

            if app.personalRecords.isEmpty {
                Text("Complete workouts to see your PRs.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted2)
            } else {
                ForEach(Array(app.personalRecords.values.sorted { $0.exerciseName < $1.exerciseName }.enumerated()), id: \.element.id) { index, record in
                    HStack {
                        Text(record.exerciseName)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(record.weight > 0 ? "\(clean(record.weight))kg x \(record.reps) reps" : "BW x \(record.reps)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 7)
                    .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
                    .entrance(index, offset: 8)
                }
            }
        }
        .cardStyle()
    }

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
                .font(.system(size: 10))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
