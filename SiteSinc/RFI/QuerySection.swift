import SwiftUI

struct QuerySection: View {
    @Binding var query: String
    var error: String?
    @FocusState private var isQueryFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Query")
                    .font(.headline)
                    .foregroundColor(.primary)
                if error != nil {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
            
            TextEditor(text: $query)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(error != nil ? Color.red : Color.clear, lineWidth: 1)
                )
                .focused($isQueryFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isQueryFocused = false }
                    }
                }
            
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
