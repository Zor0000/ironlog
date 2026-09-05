import SwiftUI
import MapKit

/// The Run tab: log a run or walk by hand — a treadmill session, a trail, or
/// anything done without the phone. Time is required; distance and elevation
/// sharpen the calorie estimate (ACSM metabolic equations, `estimateCalories`).
/// Everything lands in the same History timeline as a lifting session.
struct RunView: View {
    @EnvironmentObject private var app: AppState
    @State private var kind: CardioKind = .run
    @State private var minutes = ""
    @State private var distance = ""
    @State private var elevation = ""
    @State private var terrain: CardioTerrain?
    @State private var calorieOverride = ""
    @State private var date = Date()
    @State private var distanceUnit = currentDistanceUnit
    @FocusState private var focused: Bool

    /// The session as typed, before any calorie override — the auto estimate
    /// stays visible next to the override field.
    private var baseActivity: CardioActivity? {
        manualCardio(kind: kind, minutes: minutes, distance: distance, elevation: elevation, terrain: terrain)
    }

    private var overriddenCalories: Int? {
        guard let value = decimalEntry(calorieOverride), value >= 0, value <= 1_000_000 else { return nil }
        return Int(value.rounded())
    }

    private var activity: CardioActivity? {
        guard var base = baseActivity, calorieOverride.isEmpty || overriddenCalories != nil else { return nil }
        base.calories = overriddenCalories ?? base.calories
        return base
    }

    private var validationMessage: String? {
        guard let duration = decimalEntry(minutes), duration >= 1.0 / 60, duration <= 10_080 else {
            return minutes.isEmpty ? "Enter a time to save this activity." : "Enter a duration between 1 second and 7 days."
        }
        if !distance.isEmpty && decimalEntry(distance).map({ $0 >= 0 && $0 <= 100_000 }) != true {
            return "Enter a distance from 0 to 100,000 \(currentDistanceUnit.label), or leave it blank."
        }
        if !elevation.isEmpty && decimalEntry(elevation).map({ $0 >= 0 && $0 <= 100_000 }) != true {
            return "Enter an elevation gain from 0 to 100,000 metres, or leave it blank."
        }
        if !calorieOverride.isEmpty && overriddenCalories == nil {
            return "Enter calories from 0 to 1,000,000, or clear the override to use the estimate."
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TitleBlock(title: "Log It", subtitle: "Treadmill, trail, or one you already finished")

                VStack(spacing: 10) {
                    ForEach(Array(CardioKind.allCases.enumerated()), id: \.element) { index, candidate in
                        kindTile(candidate)
                            .entrance(index)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    field("Time", unit: "minutes", text: $minutes, placeholder: "30", identifier: "run-minutes-field")
                    field("Distance (optional)", unit: currentDistanceUnit.label, text: $distance, placeholder: "5.0", identifier: "run-distance-field")
                    field("Elevation Gain (optional)", unit: "m", text: $elevation, placeholder: "45", identifier: "run-elevation-field")
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Terrain").cardLabel()
                    LazyVGrid(columns: [GridItem(), GridItem()], spacing: 8) {
                        ForEach(CardioTerrain.allCases, id: \.self) { candidate in
                            terrainChip(candidate)
                        }
                    }
                }
                .cardStyle()

                caloriesCard

                DatePicker("When", selection: $date, in: ...Date(), displayedComponents: .date)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted2)

                previewCard

                if let message = validationMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted2)
                }

                Button {
                    NativeFeedback.success()
                    guard let activity else { return }
                    app.saveRun(activity, at: date)
                    minutes = ""
                    distance = ""
                    elevation = ""
                    terrain = nil
                    calorieOverride = ""
                    date = Date()
                } label: {
                    Label("Save \(kind.label)", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(activity == nil)
                .opacity(activity == nil ? 0.5 : 1)
                .accessibilityIdentifier("save-manual-cardio-button")

                lastActivityLine
            }
            .padding(18)
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .foregroundStyle(Theme.text)
        .animation(AppMotion.quick, value: kind)
        .onChange(of: app.unitPreference) { _, _ in
            if let value = decimalEntry(distance) {
                distance = clean(value * distanceUnit.metres / currentDistanceUnit.metres)
            }
            distanceUnit = currentDistanceUnit
        }

    }

    // MARK: Kind

    private func kindTile(_ candidate: CardioKind) -> some View {
        let isSelected = kind == candidate
        return Button {
            NativeFeedback.selection()
            kind = candidate
        } label: {
            HStack(spacing: 16) {
                Image(systemName: candidate.icon)
                    .font(.title.weight(.medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.muted2)
                    .frame(width: 56)
                    .symbolEffect(.bounce, value: isSelected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.label)
                        .font(.title3.weight(.black))
                        .fontWidth(.condensed)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.text)
                    Text(candidate.blurb)
                        .font(.caption)
                        .foregroundStyle(Theme.muted2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accentDim : Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityIdentifier("run-kind-\(candidate.rawValue)")
        .accessibilityLabel(candidate.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Terrain

    private func terrainChip(_ candidate: CardioTerrain) -> some View {
        let isSelected = terrain == candidate
        return Button {
            NativeFeedback.selection()
            // Terrain is optional context — tapping the active chip clears it.
            terrain = isSelected ? nil : candidate
        } label: {
            Label(candidate.label, systemImage: candidate.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.accent : Theme.muted2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(isSelected ? Theme.accentDim : Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.border))
        }
        .buttonStyle(TactileButtonStyle())
        .accessibilityIdentifier("run-terrain-\(candidate.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Calories

    private var caloriesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calories").cardLabel()
            HStack(alignment: .firstTextBaseline) {
                if let calories = activity?.calories {
                    Text("~\(calories) kcal")
                        .font(.title.weight(.bold))
                        .fontWidth(.condensed)
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("run-calorie-estimate")
                } else {
                    Text("Add your body weight in Settings to estimate calories.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted2)
                }
                Spacer()
            }
            if baseActivity != nil {
                HStack(spacing: 8) {
                    Text("Override")
                        .font(.caption)
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.muted2)
                    TextField("kcal", text: $calorieOverride)
                        .keyboardType(.decimalPad)
                        .font(.subheadline.weight(.bold))
                        .fontWidth(.condensed)
                        .frame(width: 70)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                        .accessibilityIdentifier("run-calorie-override")
                        .accessibilityLabel("Calories override in kilocalories")
                        .focused($focused)
                        .frame(minHeight: 44)
                    if overriddenCalories != nil {
                        Button {
                            NativeFeedback.selection()
                            calorieOverride = ""
                        } label: {
                            Text("Use estimate")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(TactileButtonStyle())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .cardStyle()
    }

    // MARK: Preview

    @ViewBuilder
    private var previewCard: some View {
        if let activity, activity.duration > 0 {
            HStack {
                cardioMetric(formatPace(seconds: activity.duration, metres: activity.distance), "pace /\(currentDistanceUnit.label)")
                Spacer()
                cardioMetric(activity.distance > 20 ? formatSpeed(seconds: activity.duration, metres: activity.distance) : "--", speedUnitLabel)
                Spacer()
                cardioMetric(activity.calories.map { "~\($0)" } ?? "--", "kcal")
            }
            .cardStyle()
        }
    }

    private func cardioMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .fontWidth(.condensed)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted2)
        }
    }

    private var lastActivityLine: some View {
        Group {
            if let session = app.sessions.first(where: \.isCardio), let activity = session.activity {
                let measured = activity.distance > 0
                    ? "\(formatDistance(activity.distance)) \(currentDistanceUnit.label) · "
                    : ""
                Text("Last \(activity.kind.label.lowercased()): \(measured)\(formatElapsed(activity.duration)) · \(session.createdAt.displayDay)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func field(_ label: String, unit: String, text: Binding<String>, placeholder: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).cardLabel()
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.bold))
                    .fontWidth(.condensed)
                    .focused($focused)
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel("\(label), \(unit)")
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.muted2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        }
    }
}

/// Route line for a saved activity, shown in History. Auto-frames the whole route.
struct RouteMap: View {
    let route: [RoutePoint]

    var body: some View {
        let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        Map(initialPosition: .region(region(for: coordinates)), interactionModes: []) {
            MapPolyline(coordinates: coordinates)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .allowsHitTesting(false)
    }

    /// Bounding box of the route plus a margin, so the line never touches the edge.
    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(center: .init(), span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in coordinates {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.002),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.002)
            )
        )
    }
}
