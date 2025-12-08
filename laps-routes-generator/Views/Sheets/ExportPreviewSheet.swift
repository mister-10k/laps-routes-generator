import SwiftUI

struct ExportPreviewSheet: View {
    let city: City
    let routes: [Route]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    // Computed properties for export summary
    // Loop through all routes and get unique starting point names
    private var uniqueStartingPointNames: Set<String> {
        Set(routes.map { $0.startingPoint.name })
    }
    
    private var uniqueTurnaroundPointNames: Set<String> {
        Set(routes.map { $0.turnaroundPoint.name })
    }
    
    private var totalUniquePOIs: Int {
        // Combine both sets to handle any overlap
        var allNames = uniqueStartingPointNames
        allNames.formUnion(uniqueTurnaroundPointNames)
        return allNames.count
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("Export to Supabase")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Review what will be exported")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)
            
            Divider()
            
            // Export Summary
            VStack(alignment: .leading, spacing: 16) {
                Text("Export Summary for \(city.name)")
                    .font(.headline)
                
                // POIs Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Points of Interest")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(totalUniquePOIs) total")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("• Starting Points:")
                                .font(.caption)
                            Spacer()
                            Text("\(uniqueStartingPointNames.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("• Turnaround Points:")
                                .font(.caption)
                            Spacer()
                            Text("\(uniqueTurnaroundPointNames.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 20)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                // Routes Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.green)
                        Text("Routes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(routes.count) routes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("• Total Distance Range:")
                                .font(.caption)
                            Spacer()
                            Text(distanceRange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("• Time Coverage:")
                                .font(.caption)
                            Spacer()
                            Text(timeCoverage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 20)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                // Warning/Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("POIs will be upserted (insert or update)")
                            .font(.caption)
                        Text("Routes will be inserted as new records")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                
                Button("Confirm Export") {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom)
        }
        .frame(width: 500, height: 600)
    }
    
    // MARK: - Computed Properties
    
    private var distanceRange: String {
        guard let minDist = routes.map({ $0.totalDistanceMiles }).min(),
              let maxDist = routes.map({ $0.totalDistanceMiles }).max() else {
            return "N/A"
        }
        return String(format: "%.1f - %.1f mi", minDist, maxDist)
    }
    
    private var timeCoverage: String {
        let allTimes = Set(routes.flatMap { $0.validSessionTimes })
        guard let minTime = allTimes.min(), let maxTime = allTimes.max() else {
            return "N/A"
        }
        return "\(minTime)-\(maxTime) min"
    }
}

#Preview {
    ExportPreviewSheet(
        city: Cities.all[0],
        routes: [],
        onConfirm: {},
        onCancel: {}
    )
}

