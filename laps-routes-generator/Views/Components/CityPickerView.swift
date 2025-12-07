import SwiftUI

struct CityPickerView: View {
    @Binding var selectedCity: City
    let cities: [City]
    var citiesWithSavedRoutes: Set<String> = []
    
    var body: some View {
        Picker("City", selection: $selectedCity) {
            ForEach(cities) { city in
                HStack {
                    Text(city.name)
                    if citiesWithSavedRoutes.contains(city.name.replacingOccurrences(of: " ", with: "_").lowercased()) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .tag(city)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 220)
    }
}

#Preview {
    CityPickerView(
        selectedCity: .constant(Cities.all[0]),
        cities: Cities.all,
        citiesWithSavedRoutes: ["new_york_city"]
    )
}
