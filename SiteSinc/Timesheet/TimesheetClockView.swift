import SwiftUI
import CoreLocation
import MapKit

struct TimesheetClockView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @State private var geofence: TimesheetGeofence?
    @State private var signInAreaMode: String?
    @State private var clockLocations: [TimesheetClockLocation] = []
    @State private var activeClocks: [TimesheetActiveClock] = []
    @State private var canClockIntoThisProject = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSigningIn = false
    @State private var isSigningOut = false
    @State private var locationError: String?
    /// When geofence is set: true = inside area, false = outside or unknown; nil = no geofence (sign-in allowed)
    @State private var isWithinSignInArea: Bool? = nil
    /// Distance from user to geofence centre (metres). Set when we have location and geofence.
    @State private var distanceToGeofenceMetres: Double? = nil
    /// Distance to sign-in boundary: 0 = inside, >0 = metres to nearest boundary. Set for both geofence and sign_in_locations.
    @State private var distanceToBoundaryMetres: Double? = nil
    /// Last known user location (for map and distance).
    @State private var lastKnownUserLocation: CLLocation? = nil
    /// Hours logged today for this project (from today's draft timesheet). Fetched when signed in.
    @State private var todayHoursForProject: Double? = nil
    /// Completed sign-in/sign-out sessions for this project (history below map).
    @State private var clockHistory: [ClockHistorySession] = []

    @EnvironmentObject var sessionManager: SessionManager
    private var locationManager: LocationManager { LocationManager.shared }

    /// Haversine distance in metres between two WGS84 points (matches API check)
    private static func distanceMetres(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2)*sin(dLat/2) + cos(lat1 * .pi/180)*cos(lat2 * .pi/180)*sin(dLon/2)*sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// Format distance for display (e.g. "150 m" or "1.2 km")
    private static func formatDistance(metres: Double) -> String {
        if metres >= 1000 {
            let km = metres / 1000
            return String(format: "%.1f km", km)
        }
        return String(format: "%.0f m", max(0, metres))
    }

    /// Format distance outside geofence for display (legacy name)
    private static func formatDistanceOutside(metres: Double) -> String {
        formatDistance(metres: metres)
    }

    /// When we have a computed distance to boundary: return description for the user.
    private var distanceToBoundaryText: String? {
        guard let dist = distanceToBoundaryMetres else { return nil }
        if dist <= 0 {
            return "Within sign-in boundary (0 m away)"
        }
        return "\(Self.formatDistance(metres: dist)) from sign-in boundary"
    }

    private var clockForCurrentProject: TimesheetActiveClock? {
        activeClocks.first { $0.projectId == projectId }
    }

    private var otherActiveClocks: [TimesheetActiveClock] {
        activeClocks.filter { $0.projectId != projectId }
    }

    /// True when the backend requires latitude/longitude for sign-in (site boundary or sign-in locations mode).
    private var requiresLocation: Bool {
        if geofence != nil { return true }
        guard signInAreaMode == "sign_in_locations", !clockLocations.isEmpty else { return false }
        return true
    }

    /// Region that fits both user location and site boundary for the map.
    private var mapRegion: MKCoordinateRegion {
        var minLat = 51.0
        var maxLat = 51.0
        var minLon = -0.1
        var maxLon = -0.1
        if let user = lastKnownUserLocation {
            minLat = min(minLat, user.coordinate.latitude)
            maxLat = max(maxLat, user.coordinate.latitude)
            minLon = min(minLon, user.coordinate.longitude)
            maxLon = max(maxLon, user.coordinate.longitude)
        }
        if let gf = geofence {
            minLat = min(minLat, gf.latitude)
            maxLat = max(maxLat, gf.latitude)
            minLon = min(minLon, gf.longitude)
            maxLon = max(maxLon, gf.longitude)
        }
        for loc in clockLocations {
            guard let la = loc.latitude, let lo = loc.longitude else { continue }
            minLat = min(minLat, la)
            maxLat = max(maxLat, la)
            minLon = min(minLon, lo)
            maxLon = max(maxLon, lo)
        }
        let centre = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.5 + 0.002),
            longitudeDelta: max(0.005, (maxLon - minLon) * 1.5 + 0.002)
        )
        return MKCoordinateRegion(center: centre, span: span)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .short
        return f
    }()

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("Loading…").foregroundColor(.secondary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                currentProjectSection
                if requiresLocation {
                    locationMapSection
                }
                clockHistorySection
                if !otherActiveClocks.isEmpty {
                    alsoSignedInSection
                }
            }
        }
        .brandListChrome()
        .navigationTitle("Sign in & Out")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenMyTimesheets"), object: nil)
                } label: {
                    Label("My Timesheets", systemImage: "list.bullet.clipboard")
                }
            }
        }
        .refreshable { await load() }
        .onAppear { Task { await load() } }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    private var currentProjectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(projectName)
                    .font(.headline)
                if canClockIntoThisProject {
                    if let clock = clockForCurrentProject {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Signed in since \(Self.timeFormatter.string(from: clock.signedInAt))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let hours = todayHoursForProject {
                            HStack {
                                Text("Current hours today")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f h", hours))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        Button {
                            Task { await signOut(projectId: projectId) }
                        } label: {
                            HStack {
                                if isSigningOut { ProgressView().scaleEffect(0.9).tint(.white) }
                                Text("Sign out")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isSigningOut)
                    } else {
                        if !otherActiveClocks.isEmpty {
                            Text("You're signed in to \(otherActiveClocks.count == 1 ? otherActiveClocks[0].project.name : "other projects"). Sign out there before signing in here.")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        if requiresLocation {
                            Text("Sign-in is only allowed within the project area. Your location will be used to verify you're on site.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let boundaryText = distanceToBoundaryText {
                                HStack(spacing: 6) {
                                    Image(systemName: "location.fill")
                                        .font(.subheadline)
                                        .foregroundColor(isWithinSignInArea == true ? .green : (isWithinSignInArea == false ? .orange : .secondary))
                                    Text(boundaryText)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(isWithinSignInArea == true ? .primary : (isWithinSignInArea == false ? .orange : .secondary))
                                }
                                .padding(.vertical, 4)
                            } else if isWithinSignInArea == nil, locationError == nil {
                                Text("Checking your location…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if isWithinSignInArea == false, distanceToBoundaryText == nil {
                                Text("You're outside the sign-in area. Move to the project location to enable sign in.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            if let locErr = locationError {
                                Text(locErr)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        Button {
                            Task { await signIn(projectId: projectId) }
                        } label: {
                            HStack {
                                if isSigningIn { ProgressView().scaleEffect(0.9).tint(.white) }
                                Text("Sign in")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandChrome.accent)
                        .disabled(isSigningIn || !otherActiveClocks.isEmpty || (requiresLocation && isWithinSignInArea != true))
                    }
                } else {
                    Text("You are not assigned to clock in to this project.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("This project")
        }
    }

    private var locationMapSection: some View {
        Section {
            Map(initialPosition: .region(mapRegion), interactionModes: .all) {
                UserAnnotation()
                if let gf = geofence {
                    let coord = CLLocationCoordinate2D(latitude: gf.latitude, longitude: gf.longitude)
                    Marker("Sign-in", coordinate: coord)
                        .tint(.blue)
                    MapCircle(center: coord, radius: CLLocationDistance(gf.radiusMeters ?? 100))
                        .foregroundStyle(.blue.opacity(0.2))
                        .stroke(.blue, lineWidth: 2)
                }
                ForEach(clockLocations.filter { $0.latitude != nil && $0.longitude != nil }, id: \.id) { loc in
                    let coord = CLLocationCoordinate2D(latitude: loc.latitude!, longitude: loc.longitude!)
                    Marker(loc.name.isEmpty ? "Sign-in" : loc.name, coordinate: coord)
                        .tint(.orange)
                    MapCircle(center: coord, radius: CLLocationDistance(loc.radiusMeters ?? 50))
                        .foregroundStyle(.orange.opacity(0.2))
                        .stroke(.orange, lineWidth: 2)
                }
            }
            .mapStyle(.standard)
            .frame(height: 220)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } header: {
            Text("Location")
        } footer: {
            if distanceToBoundaryText != nil {
                Text("Site boundary shown on map. Your position is the blue dot.")
                    .font(.caption)
            }
        }
    }

    private var clockHistorySection: some View {
        Section {
            if clockHistory.isEmpty {
                Text("No sign-in history yet for this project.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(clockHistory) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("In \(Self.timeFormatter.string(from: session.signedInAt))")
                                .font(.subheadline)
                        }
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Out \(Self.timeFormatter.string(from: session.signedOutAt))")
                                .font(.subheadline)
                        }
                        Text(String(format: "%.1f h", session.hours))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Sign in & out history")
        }
    }

    private var alsoSignedInSection: some View {
        Section {
            ForEach(otherActiveClocks, id: \.id) { clock in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clock.project.name)
                            .font(.subheadline.weight(.medium))
                        Text("Since \(Self.timeFormatter.string(from: clock.signedInAt))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Sign out") {
                        Task { await signOut(projectId: clock.projectId) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Also signed in to")
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            locationError = nil
        }
        await loadGeofence()
        await loadStatus()
        await loadEntryProjects()
        await updateWithinSignInArea()
        await loadTodayHours()
        await loadClockHistory()
        await MainActor.run { isLoading = false }
    }

    private func loadTodayHours() async {
        let (clock, pid) = await MainActor.run { (clockForCurrentProject, projectId) }
        guard clock != nil else {
            await MainActor.run { todayHoursForProject = nil }
            return
        }
        do {
            let timesheets = try await APIClient.fetchMyTimesheets(token: token)
            let calendar = Calendar.current
            let today = Date()
            let todayDraft = timesheets.first { ts in
                ts.status == "DRAFT" && calendar.isDate(ts.periodStart, inSameDayAs: today)
            }
            let hours = todayDraft?.entries?
                .filter { $0.projectId == pid }
                .reduce(0) { $0 + $1.hours } ?? 0
            await MainActor.run { todayHoursForProject = hours }
        } catch {
            await MainActor.run { todayHoursForProject = nil }
        }
    }

    private func loadClockHistory() async {
        do {
            let sessions = try await APIClient.fetchClockHistory(projectId: projectId, limit: 30, token: token)
            await MainActor.run { clockHistory = sessions }
        } catch {
            await MainActor.run { clockHistory = [] }
        }
    }

    private func loadGeofence() async {
        do {
            let response = try await APIClient.fetchTimesheetClockGeofence(projectId: projectId, token: token)
            await MainActor.run {
                geofence = response.geofence
                signInAreaMode = response.signInAreaMode ?? "site_boundary"
                clockLocations = response.clockLocations ?? []
                distanceToGeofenceMetres = nil
                distanceToBoundaryMetres = nil
                // Reset until updateWithinSignInArea() runs and checks user location (per-project boundaries)
                isWithinSignInArea = nil
            }
        } catch {
            await MainActor.run {
                geofence = nil
                signInAreaMode = nil
                clockLocations = []
                isWithinSignInArea = nil
                distanceToGeofenceMetres = nil
                distanceToBoundaryMetres = nil
                lastKnownUserLocation = nil
            }
        }
    }

    /// Get user location and set isWithinSignInArea + distanceToBoundaryMetres for geofence or sign_in_locations.
    private func updateWithinSignInArea() async {
        let (gf, mode, locs) = await MainActor.run { (geofence, signInAreaMode, clockLocations) }
        locationManager.requestLocationPermission()
        locationManager.checkAuthorizationStatus()
        guard locationManager.isAuthorized else {
            await MainActor.run {
                isWithinSignInArea = requiresLocation ? false : nil
                distanceToGeofenceMetres = nil
                distanceToBoundaryMetres = nil
                lastKnownUserLocation = nil
                if requiresLocation {
                    locationError = "Location access is required. Enable it in Settings to see if you're in the sign-in area."
                }
            }
            return
        }
        await MainActor.run { locationError = nil }
        guard let location = await locationManager.getCurrentLocation() else {
            await MainActor.run {
                isWithinSignInArea = requiresLocation ? false : nil
                distanceToGeofenceMetres = nil
                distanceToBoundaryMetres = nil
                lastKnownUserLocation = nil
                locationError = locationManager.locationError ?? "Could not get your location."
            }
            return
        }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        if mode == "sign_in_locations", !locs.isEmpty {
            var insideAny = false
            var minDistanceToBoundary = Double.infinity
            for loc in locs {
                guard let locLat = loc.latitude, let locLon = loc.longitude else { continue }
                let distToCentre = Self.distanceMetres(lat1: lat, lon1: lon, lat2: locLat, lon2: locLon)
                let radius = loc.radiusMeters ?? 0
                if radius > 0 {
                    if distToCentre <= radius {
                        insideAny = true
                        minDistanceToBoundary = min(minDistanceToBoundary, 0)
                    } else {
                        minDistanceToBoundary = min(minDistanceToBoundary, distToCentre - radius)
                    }
                } else {
                    minDistanceToBoundary = min(minDistanceToBoundary, distToCentre)
                    if distToCentre < 50 { insideAny = true }
                }
            }
            await MainActor.run {
                lastKnownUserLocation = location
                distanceToGeofenceMetres = minDistanceToBoundary == .infinity ? nil : (insideAny ? 0 : minDistanceToBoundary)
                distanceToBoundaryMetres = minDistanceToBoundary == .infinity ? nil : (insideAny ? 0 : minDistanceToBoundary)
                isWithinSignInArea = insideAny
            }
            return
        }

        guard let gf else {
            await MainActor.run { isWithinSignInArea = nil; distanceToBoundaryMetres = nil; lastKnownUserLocation = location }
            return
        }
        let distance = Self.distanceMetres(lat1: lat, lon1: lon, lat2: gf.latitude, lon2: gf.longitude)
        let radius = gf.radiusMeters ?? 0
        let toBoundary = radius > 0 ? (distance <= radius ? 0 : distance - radius) : 0
        await MainActor.run {
            lastKnownUserLocation = location
            distanceToGeofenceMetres = distance
            distanceToBoundaryMetres = toBoundary
            isWithinSignInArea = radius > 0 ? (distance <= radius) : true
        }
    }

    private func loadStatus() async {
        do {
            let response = try await APIClient.fetchTimesheetClockStatus(token: token)
            await MainActor.run { activeClocks = response.activeClocks }
            AnalyticsService.shared.setSignedIntoProject(!response.activeClocks.isEmpty)
        } catch {
            await MainActor.run { activeClocks = [] }
            AnalyticsService.shared.setSignedIntoProject(false)
        }
    }

    private func loadEntryProjects() async {
        do {
            let response = try await APIClient.fetchTimesheetClockEntryProjects(token: token)
            await MainActor.run {
                canClockIntoThisProject = response.projects.contains { $0.id == projectId }
            }
        } catch {
            await MainActor.run { canClockIntoThisProject = false }
        }
    }

    private func signIn(projectId: Int) async {
        await MainActor.run { isSigningIn = true; locationError = nil }
        var lat: Double?
        var lon: Double?
        if requiresLocation {
            locationManager.requestLocationPermission()
            locationManager.checkAuthorizationStatus()
            guard locationManager.isAuthorized else {
                await MainActor.run {
                    isSigningIn = false
                    locationError = "Location access is required to sign in. Enable it in Settings."
                }
                return
            }
            if let location = await locationManager.getCurrentLocation() {
                lat = location.coordinate.latitude
                lon = location.coordinate.longitude
            } else {
                await MainActor.run {
                    isSigningIn = false
                    locationError = locationManager.locationError ?? "Could not get your location."
                }
                return
            }
        }
        do {
            _ = try await APIClient.timesheetClockSignIn(projectId: projectId, latitude: lat, longitude: lon, clockLocationId: nil, token: token)
            await loadStatus()
            await loadTodayHours()
            await loadClockHistory()
        } catch {
            await MainActor.run {
                if case APIError.badRequest(let message) = error {
                    errorMessage = message
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
        await MainActor.run { isSigningIn = false }
    }

    private func signOut(projectId: Int) async {
        await MainActor.run {
            if projectId == self.projectId { isSigningOut = true }
        }
        var lat: Double?
        var lon: Double?
        if locationManager.isAuthorized, let location = await locationManager.getCurrentLocation() {
            lat = location.coordinate.latitude
            lon = location.coordinate.longitude
        }
        do {
            _ = try await APIClient.timesheetClockSignOut(projectId: projectId, latitude: lat, longitude: lon, token: token)
            await loadStatus()
            if projectId == self.projectId {
                await MainActor.run { todayHoursForProject = nil }
                await loadClockHistory()
            }
        } catch {
            await MainActor.run {
                if case APIError.badRequest(let message) = error {
                    errorMessage = message
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
        await MainActor.run { isSigningOut = false }
    }
}
