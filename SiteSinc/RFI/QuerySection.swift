import SwiftUI

struct QuerySection: View {
    @Binding var query: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query")
                .font(.subheadline)
                .foregroundColor(.gray)
            TextEditor(text: $query)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
}
