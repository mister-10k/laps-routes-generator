import SwiftUI
import MapKit

struct ContentView: View {
    @State private var selectedCity: City = Cities.all[0]
    @State private var selectedStartingPoint: StartingPoint = Cities.all[0].startingPoints[0]
    @State private var selectedDirection: DirectionPreference = .noPreference
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: Cities.all[0].coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    @State private var routes: [Route] = []
    @State private var selectedRouteId: Route.ID?
    @State private var isGenerating = false
    @State private var generationStatus: String = ""
    @State private var citiesWithSavedRoutes: Set<String> = []
    @State private var groupingMode: GroupingMode = .byDistance
    @State private var skippedThresholds: [Int] = []
    @State private var showSkippedAlert = false
    @State private var blacklistCount = 0
    @State private var searchText: String = ""
    @State private var showExportPreview = false
    @State private var currentToast: Toast?
    @State private var showClearRoutesAlert = false
    @State private var showClearBlacklistAlert = false
    
    enum GroupingMode: String, CaseIterable {
        case byDistance = "Distance"
        case byTime = "Time"
    }
    
    // All time slots (5, 10, 15, ... 120 minutes)
    private let allTimeSlots: [Int] = Array(stride(from: 5, through: 120, by: 5))
    
    // Computed property to get selected route object
    var selectedRoute: Route? {
        routes.first { $0.id == selectedRouteId }
    }
    
    // Filter routes by search text (searches route name and turnaround point name)
    var filteredRoutes: [Route] {
        guard !searchText.isEmpty else { return routes }
        let searchLower = searchText.lowercased()
        return routes.filter { route in
            route.name.lowercased().contains(searchLower) ||
            route.turnaroundPoint.name.lowercased().contains(searchLower) ||
            route.startingPoint.name.lowercased().contains(searchLower)
        }
    }
    
    // Group routes by distance band
    var routesByDistance: [DistanceGroup] {
        let bands: [Double] = [1.0, 2.0, 4.0, 7.5, 9.5, 13.0, 16.0]
        return bands.compactMap { band in
            let bandRoutes = filteredRoutes.filter { $0.distanceBandMiles == band }
            guard !bandRoutes.isEmpty else { return nil }
            return DistanceGroup(band: band, routes: bandRoutes)
        }
    }
    
    // Group routes by time slot
    var routesByTime: [TimeGroup] {
        allTimeSlots.compactMap { duration in
            let matchingRoutes = filteredRoutes.filter { $0.validSessionTimes.contains(duration) }
            return TimeGroup(duration: duration, routes: matchingRoutes)
        }
    }
    
    // Coverage summary
    var coverageSummary: (covered: Int, total: Int) {
        let covered = allTimeSlots.filter { duration in
            routes.filter { $0.validSessionTimes.contains(duration) }.count >= 10
        }.count
        return (covered, allTimeSlots.count)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack {
                CityPickerView(
                    selectedCity: $selectedCity,
                    cities: Cities.all,
                    citiesWithSavedRoutes: citiesWithSavedRoutes
                )
                .onChange(of: selectedCity) { newCity in
                    // Update starting point to first available for new city
                    selectedStartingPoint = newCity.startingPoints[0]
                    updateRegion(for: selectedStartingPoint)
                    loadRoutesForCity(newCity)
                    refreshBlacklistCount()
                }
                
                StartingPointPickerView(
                    selectedStartingPoint: $selectedStartingPoint,
                    startingPoints: selectedCity.startingPoints
                )
                .onChange(of: selectedStartingPoint) { newStartingPoint in
                    updateRegion(for: newStartingPoint)
                }
                
                DirectionPickerView(selectedDirection: $selectedDirection)
                
                Spacer()
                
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                    Text(generationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button("Clear Blacklist (\(blacklistCount))") {
                    showClearBlacklistAlert = true
                }
                .foregroundStyle(.orange)
                .disabled(blacklistCount == 0)
                
                if !routes.isEmpty {
                    Button("Clear Routes") {
                        showClearRoutesAlert = true
                    }
                    .foregroundStyle(.red)
                }
                
                Button("Generate All Routes") {
                    generateRoutes()
                }
                .disabled(isGenerating)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            // Main Content
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Map View (Left)
                    MapView(region: region, selectedRoute: selectedRoute)
                        .frame(width: geometry.size.width * 0.65)
                    
                    Divider()
                    
                    // Routes List (Right)
                    VStack(alignment: .leading, spacing: 0) {
                        // Header with grouping toggle
                        VStack(spacing: 8) {
                            HStack {
                                Text("Routes (\(routes.count))")
                                    .font(.headline)
                                
                                if PersistenceService.shared.hasSavedRoutes(for: selectedCity.name) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                                
                                Spacer()
                                
                                // Coverage indicator
                                let coverage = coverageSummary
                                Text("\(coverage.covered)/\(coverage.total) times covered")
                                    .font(.caption)
                                    .foregroundStyle(coverage.covered == coverage.total ? .green : .orange)
                            }
                            
                            // Search field for filtering routes by location name
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search by location name...", text: $searchText)
                                    .textFieldStyle(.plain)
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            
                            // Show filtered count if searching
                            if !searchText.isEmpty {
                                Text("Showing \(filteredRoutes.count) of \(routes.count) routes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Picker("Group By", selection: $groupingMode) {
                                ForEach(GroupingMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding()
                        
                        Divider()
                        
                        // Routes list based on grouping mode
                        if groupingMode == .byDistance {
                            List(selection: $selectedRouteId) {
                                ForEach(routesByDistance, id: \.band) { group in
                                    Section {
                                        ForEach(group.routes) { route in
                                            RouteRow(route: route, showTime: true) {
                                                regenerate(route: route)
                                            } onBlacklist: {
                                                blacklistRoute(route)
                                            }
                                            .tag(route.id)
                                        }
                                    } header: {
                                        DistanceBandHeader(band: group.band, count: group.routes.count)
                                    }
                                }
                            }
                            .listStyle(.sidebar)
                        } else {
                            List(selection: $selectedRouteId) {
                                ForEach(routesByTime, id: \.duration) { group in
                                    Section {
                                        ForEach(group.routes) { route in
                                            RouteRow(route: route, showTime: false) {
                                                regenerate(route: route)
                                            } onBlacklist: {
                                                blacklistRoute(route)
                                            }
                                            .tag(route.id)
                                        }
                                    } header: {
                                        TimeSlotHeader(duration: group.duration, count: group.routes.count)
                                    }
                                }
                            }
                            .listStyle(.sidebar)
                        }
                    }
                    .frame(width: geometry.size.width * 0.35)
                }
            }
            
            Divider()
            
            // Bottom Bar
            HStack {
                VStack(alignment: .leading) {
                    Text("Coverage:")
                        .font(.caption)
                        .fontWeight(.bold)
                    
                    // Simple coverage display
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(stride(from: 5, through: 120, by: 5).map { $0 }, id: \.self) { duration in
                                CoverageBadge(duration: duration, routes: routes)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button("Export to Supabase") {
                    showExportPreview = true
                }
                .disabled(routes.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toast($currentToast)
        .onAppear {
            updateRegion(for: selectedStartingPoint)
            refreshSavedCitiesList()
            loadRoutesForCity(selectedCity)
            refreshBlacklistCount()
        }
        .onChange(of: selectedRouteId) { newRouteId in
            if let routeId = newRouteId,
               let route = routes.first(where: { $0.id == routeId }) {
                updateRegion(for: route)
            }
        }
        .alert("Some Thresholds Not Fully Covered", isPresented: $showSkippedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            let skippedText = skippedThresholds.map { "\($0) min" }.joined(separator: ", ")
            Text("The following time thresholds could not get 10 routes due to lack of available POIs:\n\n\(skippedText)")
        }
        .alert("Clear All Routes?", isPresented: $showClearRoutesAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearRoutes()
            }
        } message: {
            Text("This will delete all \(routes.count) routes for \(selectedCity.name). This action cannot be undone.")
        }
        .alert("Clear Blacklist?", isPresented: $showClearBlacklistAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearBlacklist()
            }
        } message: {
            Text("This will remove all \(blacklistCount) blacklisted POIs for \(selectedCity.name). Previously blacklisted locations may appear again when generating routes.")
        }
        .sheet(isPresented: $showExportPreview) {
            ExportPreviewSheet(
                city: selectedCity,
                routes: routes,
                onConfirm: {
                    showExportPreview = false
                    exportToSupabase()
                },
                onCancel: {
                    showExportPreview = false
                }
            )
        }
    }
    
    // MARK: - Actions
    
    private func updateRegion(for startingPoint: StartingPoint) {
        region = MKCoordinateRegion(
            center: startingPoint.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    
    private func updateRegion(for route: Route) {
        // Combine all coordinates from the route
        let allCoordinates = route.outboundPath + route.returnPath
        
        guard !allCoordinates.isEmpty else { return }
        
        // Calculate the bounding box
        var minLat = allCoordinates[0].latitude
        var maxLat = allCoordinates[0].latitude
        var minLon = allCoordinates[0].longitude
        var maxLon = allCoordinates[0].longitude
        
        for coordinate in allCoordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        // Calculate center and span
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.3 // Add 30% padding
        let spanLon = (maxLon - minLon) * 1.3 // Add 30% padding
        
        // Update the region
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: max(spanLat, 0.01), longitudeDelta: max(spanLon, 0.01))
        )
    }
    
    private func loadRoutesForCity(_ city: City) {
        selectedRouteId = nil
        if let savedRoutes = PersistenceService.shared.loadRoutes(for: city.name) {
            routes = savedRoutes
            generationStatus = "Loaded \(savedRoutes.count) saved routes"
        } else {
            routes = []
            generationStatus = ""
        }
    }
    
    private func saveRoutes() {
        PersistenceService.shared.saveRoutes(routes, for: selectedCity.name)
        refreshSavedCitiesList()
    }
    
    private func refreshSavedCitiesList() {
        citiesWithSavedRoutes = Set(PersistenceService.shared.citiesWithSavedRoutes())
    }
    
    private func clearRoutes() {
        routes = []
        selectedRouteId = nil
        PersistenceService.shared.deleteRoutes(for: selectedCity.name)
        refreshSavedCitiesList()
        generationStatus = "Routes cleared"
    }
    
    private func clearBlacklist() {
        // Clear both manual blacklist and per-threshold blacklist
        PersistenceService.shared.clearAllBlacklists(for: selectedCity.name)
        refreshBlacklistCount()
        generationStatus = "All blacklists cleared (manual + per-threshold)"
    }
    
    private func refreshBlacklistCount() {
        // Show combined count of manual blacklist + per-threshold blacklist
        blacklistCount = PersistenceService.shared.totalBlacklistCount(for: selectedCity.name)
    }
    
    private func generateRoutes() {
        isGenerating = true
        generationStatus = "Starting..."
        skippedThresholds = []
        
        // Keep track of existing routes to pass to generator
        let existingRoutes = self.routes
        
        // Set up progress callback
        RouteGenerator.shared.onProgressUpdate = { message in
            Task { @MainActor in
                self.generationStatus = message
            }
        }
        
        // Set up incremental route callback - routes appear in UI as they're generated
        RouteGenerator.shared.onRouteGenerated = { newRoute in
            Task { @MainActor in
                // Only add if not already in our list (existing routes are passed to generator)
                if !self.routes.contains(where: { $0.id == newRoute.id }) {
                    self.routes.append(newRoute)
                }
            }
        }
        
        // Set up incremental save callback - routes are saved as they're generated
        // This ensures progress is preserved even if app is closed mid-generation
        let cityName = selectedCity.name
        RouteGenerator.shared.onSaveRoutes = { routes in
            Task { @MainActor in
                PersistenceService.shared.saveRoutes(routes, for: cityName)
            }
        }
        
        Task {
            // Get blacklisted POI names for this city
            let blacklistedNames = PersistenceService.shared.getBlacklistedNames(for: selectedCity.name)
            
            // Pass existing routes and blacklist so generator doesn't regenerate what we already have
            let result = await RouteGenerator.shared.generateRoutes(for: selectedCity, startingPoint: selectedStartingPoint, directionPreference: selectedDirection, existingRoutes: existingRoutes, blacklistedPOINames: blacklistedNames)
            
            await MainActor.run {
                // Final sync - ensure we have all routes (in case callback missed any)
                self.routes = result.routes
                self.skippedThresholds = result.skippedThresholds
                self.isGenerating = false
                
                // Create status message
                let coverageCount = result.coverageByThreshold.values.filter { $0 >= 10 }.count
                let totalThresholds = result.coverageByThreshold.count
                let newRoutesCount = result.routes.count - existingRoutes.count
                if existingRoutes.isEmpty {
                    self.generationStatus = "Generated \(result.routes.count) routes (\(coverageCount)/\(totalThresholds) thresholds covered)"
                } else {
                    self.generationStatus = "Added \(newRoutesCount) new routes (total: \(result.routes.count), \(coverageCount)/\(totalThresholds) covered)"
                }
                
                // Show alert if any thresholds were skipped
                if !result.skippedThresholds.isEmpty {
                    showSkippedAlert = true
                }
                
                // Auto-save after generation
                saveRoutes()
            }
        }
    }
    
    private func exportToSupabase() {
        guard !routes.isEmpty else { return }
        isGenerating = true
        generationStatus = "Exporting..."
        
        Task {
            do {
                try await SupabaseService.shared.export(city: selectedCity, routes: routes)
                await MainActor.run {
                    isGenerating = false
                    generationStatus = "Exported successfully!"
                    
                    // Show success toast
                    currentToast = Toast(message: "Exported \(routes.count) routes to Supabase!", type: .success)
                    
                    // Auto-dismiss after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        currentToast = nil
                    }
                }
            } catch {
                print("❌ Export to Supabase failed: \(error)")
                
                await MainActor.run {
                    isGenerating = false
                    generationStatus = "Export failed: \(error.localizedDescription)"
                    
                    // Show error toast
                    currentToast = Toast(message: "Export failed: \(error.localizedDescription)", type: .error)
                    
                    // Auto-dismiss after 5 seconds (longer for errors so user can read)
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        currentToast = nil
                    }
                }
            }
        }
    }
    
    private func regenerate(route: Route) {
        guard !isGenerating else { return }
        isGenerating = true
        generationStatus = "Regenerating \(route.name)..."
        
        Task {
            if let newRoute = await RouteGenerator.shared.regenerateRoute(oldRoute: route, city: selectedCity, startingPoint: selectedStartingPoint, directionPreference: selectedDirection) {
                await MainActor.run {
                    if let index = routes.firstIndex(where: { $0.id == route.id }) {
                        routes[index] = newRoute
                        if selectedRouteId == route.id {
                            selectedRouteId = newRoute.id
                        }
                    }
                    isGenerating = false
                    generationStatus = "Regenerated"
                    
                    // Auto-save after regeneration
                    saveRoutes()
                }
            } else {
                await MainActor.run {
                    isGenerating = false
                    generationStatus = "Regeneration failed"
                }
            }
        }
    }
    
    private func blacklistRoute(_ route: Route) {
        // Add to blacklist (returns false if already blacklisted)
        let wasAdded = PersistenceService.shared.addToBlacklist(poi: route.turnaroundPoint, for: selectedCity.name)
        
        // Remove from current routes
        routes.removeAll { $0.id == route.id }
        
        // Clear selection if this was selected
        if selectedRouteId == route.id {
            selectedRouteId = nil
        }
        
        // Save updated routes
        saveRoutes()
        
        // Refresh blacklist count
        refreshBlacklistCount()
        
        if wasAdded {
            generationStatus = "Blacklisted \(route.name) (\(blacklistCount) total blacklisted)"
        } else {
            generationStatus = "Removed \(route.name) (already blacklisted)"
        }
    }
    
}

struct RouteRow: View {
    let route: Route
    var showTime: Bool = true
    let onRegenerate: () -> Void
    let onBlacklist: () -> Void
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 8) {
                    Text(String(format: "%.1f mi", route.totalDistanceMiles))
                    
                    if showTime {
                        Text("•")
                        if let min = route.validSessionTimes.min(), let max = route.validSessionTimes.max() {
                            if min == max {
                                Text("\(min) min")
                            } else {
                                Text("\(min)-\(max) min")
                            }
                        } else {
                            Text("N/A min")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Button("Regenerate") {
                    onRegenerate()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .padding(.top, 2)
            }
            
            Spacer()
            
            // Blacklist button
            Button {
                onBlacklist()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("Remove and blacklist this route")
        }
        .padding(.vertical, 4)
    }
}

struct CoverageBadge: View {
    let duration: Int
    let routes: [Route]
    
    var isCovered: Bool {
        // "Green checkmark = 10+ routes cover this duration"
        let count = routes.filter { $0.validSessionTimes.contains(duration) }.count
        return count >= 10
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text("\(duration)m")
            Image(systemName: isCovered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isCovered ? .green : .orange)
        }
        .font(.caption2)
    }
}

// MARK: - Grouping Models

struct DistanceGroup {
    let band: Double
    let routes: [Route]
}

struct TimeGroup {
    let duration: Int
    let routes: [Route]
    
    var isCovered: Bool {
        routes.count >= 10
    }
}

// MARK: - Section Headers

struct DistanceBandHeader: View {
    let band: Double
    let count: Int
    
    var body: some View {
        HStack {
            Text(formatBand(band))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text("\(count) route\(count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatBand(_ miles: Double) -> String {
        if miles.truncatingRemainder(dividingBy: 1) == 0 {
            return "~\(Int(miles)) mi"
        } else {
            return String(format: "~%.1f mi", miles)
        }
    }
}

struct TimeSlotHeader: View {
    let duration: Int
    let count: Int
    
    private var isCovered: Bool { count >= 10 }
    
    var body: some View {
        HStack {
            Text("\(duration) min")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            
            Image(systemName: isCovered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isCovered ? .green : .orange)
                .font(.system(size: 10))
            
            Spacer()
            
            Text("\(count) route\(count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(isCovered ? .secondary : .orange)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
