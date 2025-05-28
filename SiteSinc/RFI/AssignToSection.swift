import SwiftUI

struct AssignToSection: View {
    @Binding var assignedUserIds: [Int]
    let users: [User]
    let isLoading: Bool
    var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assign To")
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
                NavigationLink {
                    UserSelectionView(
                        users: users,
                        selectedUserIds: $assignedUserIds,
                        title: "Select Users"
                    )
                } label: {
                    HStack {
                        if assignedUserIds.isEmpty {
                            Text("Select Users")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(assignedUserIds.count) user\(assignedUserIds.count == 1 ? "" : "s") selected")
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
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
                
                if !assignedUserIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(assignedUserIds.compactMap { id in
                                users.first { $0.id == id }
                            }) { user in
                                HStack(spacing: 4) {
                                    Text("\(user.firstName ?? "") \(user.lastName ?? "")")
                                        .font(.subheadline)
                                    Button(action: {
                                        if let index = assignedUserIds.firstIndex(of: user.id) {
                                            assignedUserIds.remove(at: index)
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .cornerRadius(16)
                            }
                        }
                        .padding(.vertical, 4)
                    }
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

struct UserSelectionView: View {
    let users: [User]
    @Binding var selectedUserIds: [Int]
    let title: String
    
    var body: some View {
        List {
            ForEach(users) { user in
                Button(action: {
                    if let index = selectedUserIds.firstIndex(of: user.id) {
                        selectedUserIds.remove(at: index)
                    } else {
                        selectedUserIds.append(user.id)
                    }
                }) {
                    HStack {
                        Text("\(user.firstName ?? "") \(user.lastName ?? "")")
                        Spacer()
                        if selectedUserIds.contains(user.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
