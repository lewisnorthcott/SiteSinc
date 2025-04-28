import SwiftUI

struct ResponseDateSection: View {
    @Binding var returnDate: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response By Date")
                .font(.subheadline)
                .foregroundColor(.gray)
            DatePicker(
                "Select date",
                selection: Binding(
                    get: { returnDate ?? Date() },
                    set: { returnDate = $0 }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            HStack(spacing: 8) {
                Button("Today") { returnDate = Date() }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                Button("Tomorrow") { returnDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
                    .buttonStyle(.bordered)
                    .tint(.gray)
                Button("Next Week") { returnDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }
                    .buttonStyle(.bordered)
                    .tint(.gray)
            }
        }
    }
}
