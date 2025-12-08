import SwiftUI

struct StartingPointPickerView: View {
    @Binding var selectedStartingPoint: StartingPoint
    let startingPoints: [StartingPoint]
    
    var body: some View {
        Picker("Starting Point", selection: $selectedStartingPoint) {
            ForEach(startingPoints) { point in
                Text(point.name)
                    .tag(point)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 220)
        .disabled(startingPoints.count <= 1)
    }
}

#Preview {
    StartingPointPickerView(
        selectedStartingPoint: .constant(
            StartingPoint(name: "Empire State Building", coordinate: .init(latitude: 40.748817, longitude: -73.985428))
        ),
        startingPoints: [
            StartingPoint(name: "Empire State Building", coordinate: .init(latitude: 40.748817, longitude: -73.985428)),
            StartingPoint(name: "Barclays Center", coordinate: .init(latitude: 40.683, longitude: -73.976))
        ]
    )
}

