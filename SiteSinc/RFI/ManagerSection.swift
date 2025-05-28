import SwiftUI

struct ManagerSection: View {
    @Binding var managerId: Int?
    let users: [User]
    let isLoading: Bool
    var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Manager")
                    .font(.headline)
                    .foregroundColor(.primary)
                if error != nil {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
            
            if isLoading {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Loading users...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                HStack {
                    if let selectedManager = users.first(where: { $0.id == managerId }) {
                        Text("\(selectedManager.firstName ?? "") \(selectedManager.lastName ?? "")")
                            .foregroundColor(.primary)
                    } else {
                        Text("No manager found")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(error != nil ? Color.red : Color.clear, lineWidth: 1)
                )
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
