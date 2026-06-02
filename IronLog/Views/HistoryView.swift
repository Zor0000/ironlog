import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @State private var deleteTarget: WorkoutSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TitleBlock(title: "History", subtitle: "All your past sessions")
                HStack(spacing: 10) {
                    Text(app.syncMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted2)
                    Spacer()
                    Button {
                        NativeFeedback.selection()
                        Task { await app.syncNow() }
                    } label: {
                        Label(app.user?.isLocal == true ? "Set Up Sync" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(Theme.text)
                            .background(Theme.surface2)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                    .buttonStyle(TactileButtonStyle())
                }

                if app.sessions.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(app.sessions.enumerated()), id: \.element.id) { index, session in
                        HistoryCard(session: session, deleteTarget: $deleteTarget)
                            .entrance(index)
                    }
                }
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .animation(AppMotion.quick, value: app.sessions)
        .confirmationDialog("Delete this workout session?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Delete Session", role: .destructive) {
                NativeFeedback.light()
                if let deleteTarget {
                    Task { await app.deleteSession(deleteTarget.id) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(Theme.muted)
            Text("No sessions yet.\nComplete your first workout.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

struct HistoryCard: View {
    @EnvironmentObject private var app: AppState
    let session: WorkoutSession
    @Binding var deleteTarget: WorkoutSession?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.createdAt.displayDay)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(setCount) sets · \(session.split ?? "Workout") · \(syncText)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted2)
                }
                Spacer()
                if let muscle = app.library.muscle(session.muscle) {
                    Pill(text: muscle.label)
                }
                Button {
                    NativeFeedback.selection()
                    withAnimation(AppMotion.quick) {
                        deleteTarget = session
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Theme.muted2)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(14)
            .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)

            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                HStack(alignment: .top) {
                    Text(exercise.name)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(exercise.sets.map(setLabel).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted2)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
                .entrance(index, offset: 8)
            }

            if let note = session.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text")
                    Text(note)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var setCount: Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }

    private var syncText: String {
        switch session.syncState {
        case .synced: "synced"
        case .failed: "local"
        case .pending: "pending"
        case .localOnly: "local"
        }
    }

    private func setLabel(_ set: LoggedSet) -> String {
        if let weight = set.weight, weight > 0 {
            return "\(clean(weight))kg x \(set.reps)"
        }
        return "BW x \(set.reps)"
    }
}
