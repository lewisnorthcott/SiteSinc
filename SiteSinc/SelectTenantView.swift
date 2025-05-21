import SwiftUI

struct SelectTenantView: View {
    @State private var tenants: [Tenant] = []
    @State private var filteredTenants: [Tenant] = []
    @State private var searchQuery = ""
    @State private var selectedTenant: Int?
    @State private var currentPage = 1
    @State private var error = ""
    @State private var isLoading = false
    @Binding var isPresented: Bool
    let tenantsPerPage = 5
    let token: String
    let initialTenants: [User.UserTenant]?
    let onSelectTenant: (String, User) -> Void
    let onLogout: () -> Void

    var totalPages: Int {
        Int(ceil(Double(filteredTenants.count) / Double(tenantsPerPage)))
    }

    var paginatedTenants: [Tenant] {
        let start = (currentPage - 1) * tenantsPerPage
        let end = min(start + tenantsPerPage, filteredTenants.count)
        return Array(filteredTenants[start..<end])
    }

    var body: some View {
        ZStack {
            Color.gray.opacity(0.05).ignoresSafeArea()
            mainContent
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            if let initial = initialTenants {
                tenants = initial.compactMap { $0.tenant }
                filterTenants()
            } else {
                fetchTenants()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 24) {
            headerView
            titleView
            errorView
            searchBarView
            tenantListView
            paginationView
            selectButtonView
            backToLoginView
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: 400)
    }

    private var headerView: some View {
        HStack(spacing: 0) {
            Text("Site")
                .font(.title)
                .fontWeight(.regular)
            Text("Sinc")
                .font(.title)
                .fontWeight(.regular)
                .foregroundColor(Color(hex: "#635bff"))
        }
    }

    private var titleView: some View {
        VStack(spacing: 8) {
            Text("Select Organization")
                .font(.title3)
                .fontWeight(.regular)
            Text("Choose the organization you want to access")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }

    private var errorView: some View {
        Group {
            if !error.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var searchBarView: some View {
        TextField("Search by organization name", text: $searchQuery)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .foregroundColor(.black)
            .autocapitalization(.none)
            .disabled(isLoading)
            .onChange(of: searchQuery) { oldValue, newValue in
                filterTenants()
                currentPage = 1
                selectedTenant = nil
            }
    }

    private var tenantListView: some View {
        ScrollView {
            VStack(spacing: 8) {
                if paginatedTenants.isEmpty {
                    Text("No organizations found")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(paginatedTenants) { tenant in
                        tenantRowView(tenant: tenant)
                    }
                }
            }
        }
    }

    private func tenantRowView(tenant: Tenant) -> some View {
        Button(action: {
            selectedTenant = tenant.id
        }) {
            HStack {
                Image(systemName: selectedTenant == tenant.id ? "circle.fill" : "circle")
                    .foregroundColor(selectedTenant == tenant.id ? Color(hex: "#635bff") : .gray)
                Text(tenant.name)
                    .foregroundColor(.black)
                Spacer()
            }
            .padding()
            .background(selectedTenant == tenant.id ? Color(hex: "#635bff").opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .disabled(isLoading)
    }

    private var paginationView: some View {
        Group {
            if filteredTenants.count > tenantsPerPage {
                HStack {
                    Button(action: { if currentPage > 1 { currentPage -= 1 } }) {
                        Text("Previous")
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .disabled(currentPage == 1 || isLoading)

                    Spacer()

                    Text("Page \(currentPage) of \(totalPages)")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()

                    Button(action: { if currentPage < totalPages { currentPage += 1 } }) {
                        Text("Next")
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .disabled(currentPage == totalPages || isLoading)
                }
            }
        }
    }

    private var selectButtonView: some View {
        Button(action: {
            guard let tenantId = selectedTenant else {
                error = "Please select an organization"
                return
            }
            selectTenant(tenantId: tenantId)
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.5)
                }
                Text(isLoading ? "Selecting..." : "Select \(selectedTenant.map { id in filteredTenants.first(where: { $0.id == id })?.name ?? "Organization" } ?? "Organization")")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .tracking(1)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(hex: "#635bff"))
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(isLoading ? 0.98 : 1.0)
        }
        .disabled(isLoading || selectedTenant == nil)
    }

    private var backToLoginView: some View {
        Button(action: {
            onLogout()
        }) {
            HStack {
                Image(systemName: "arrow.left")
                Text("Back to Login")
            }
            .font(.caption)
            .foregroundColor(Color(hex: "#635bff"))
        }
        .disabled(isLoading)
    }

    private func fetchTenants() {
            isLoading = true
            APIClient.fetchTenants(token: token) { result in
                switch result {
                case .success(let fetchedTenants):
                    tenants = fetchedTenants
                    filterTenants()
                    isLoading = false
                case .failure(let err):
                    error = err.localizedDescription
                    isLoading = false
                }
            }
        }

        private func selectTenant(tenantId: Int) {
            isLoading = true
            error = ""
            APIClient.selectTenant(token: token, tenantId: tenantId) { result in
                switch result {
                case .success(let (newToken, user)):
                    onSelectTenant(newToken, user)
                case .failure(let err):
                    error = err.localizedDescription
                }
                isLoading = false
            }
        }

        private func filterTenants() {
            filteredTenants = tenants.filter { tenant in
                searchQuery.isEmpty || tenant.name.lowercased().contains(searchQuery.lowercased())
            }
            if !filteredTenants.contains(where: { tenant in selectedTenant != nil && tenant.id == selectedTenant! }) {
                selectedTenant = nil
            }
        }

    private func autoSelectTenant(tenantId: Int) {
        selectedTenant = tenantId
        selectTenant(tenantId: tenantId)
    }


}

#Preview {
    SelectTenantView(isPresented: .constant(true), token: "sample-token", initialTenants: nil, onSelectTenant: { token, user in
        print("Selected tenant with token: \(token), user: \(user)")
    }, onLogout: {
        print("Logged out")
    })
}
