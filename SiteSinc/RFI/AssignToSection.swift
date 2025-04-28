import SwiftUI

struct AssignToSection: View {
    @Binding var assignedUserIds: [Int]
    let users: [User]
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assign To")
                .font(.subheadline)
                .foregroundColor(.gray)
            MultiSelectPicker(items: users, selectedIds: $assignedUserIds)
                .disabled(isLoading || users.isEmpty)
        }
    }
}
