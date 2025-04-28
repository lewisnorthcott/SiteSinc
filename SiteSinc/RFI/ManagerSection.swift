import SwiftUI

struct ManagerSection: View {
    @Binding var managerId: Int?
    let users: [User]
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RFI Manager")
                .font(.subheadline)
                .foregroundColor(.gray)
            Picker("Select RFI Manager", selection: $managerId) {
                Text("Select a manager").tag(nil as Int?)
                ForEach(users, id: \.id) { user in
                    Text("\(user.firstName ?? "") \(user.lastName ?? "")").tag(user.id as Int?)
                }
            }
            .pickerStyle(.menu)
            .disabled(isLoading || users.isEmpty)
        }
    }
}
