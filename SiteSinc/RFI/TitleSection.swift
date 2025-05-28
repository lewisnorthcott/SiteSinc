import SwiftUI

struct TitleSection: View {
    @Binding var title: String
    var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title")
                    .font(.headline)
                    .foregroundColor(.primary)
                if error != nil {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
            
            TextField("Enter RFI title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(error != nil ? Color.red : Color.clear, lineWidth: 1)
                )
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}
