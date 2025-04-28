import SwiftUI

struct TitleSection: View {
    @Binding var title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.subheadline)
                .foregroundColor(.gray)
            TextField("Enter RFI title", text: $title)
                .textFieldStyle(.roundedBorder)
        }
    }
}
