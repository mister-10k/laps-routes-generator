import SwiftUI

struct DirectionPickerView: View {
    @Binding var selectedDirection: DirectionPreference
    
    var body: some View {
        Picker("Direction", selection: $selectedDirection) {
            ForEach(DirectionPreference.allCases, id: \.self) { direction in
                HStack {
                    Image(systemName: direction.icon)
                    Text(direction.rawValue)
                }
                .tag(direction)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 180)
    }
}

#Preview {
    DirectionPickerView(selectedDirection: .constant(.noPreference))
}

