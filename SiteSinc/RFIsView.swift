import SwiftUI

struct RFIsView: View {
    let projectId: Int
    let token: String
    @State private var rfis: [RFI] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .title
    @State private var selectedTile: Int?

    enum SortOption: String, CaseIterable, Identifiable {
        case title = "Title"
        case date = "Date"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                Text("RFIs")
                    .font(.title2)
                    .fontWeight(.regular)
                    .foregroundColor(.black)
                    .padding(.top, 16)

                // Search Bar
                HStack {
                    TextField("Search", text: $searchText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                    .padding(.leading, 8)
                                Spacer()
                            }
                        )
                }

                // Sort Picker
                Picker("Sort by", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 24)

                // Main Content
                if isLoading {
                    ProgressView("Loading RFIs...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                        .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                } else if filteredRFIs.isEmpty {
                    Text("No RFIs available")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRFIs) { rfi in
                                NavigationLink(destination: RFIDetailView(rfi: rfi, token: token)) {
                                    RFIRow(rfi: rfi)
                                        .background(
                                            Color.white
                                                .cornerRadius(8)
                                                .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
                                        )
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 4)
                                        .scaleEffect(selectedTile == rfi.id ? 0.98 : 1.0)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedTile = rfi.id
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollIndicators(.visible)
                    .refreshable {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            fetchRFIs()
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchRFIs()
        }
    }

    private var filteredRFIs: [RFI] {
        var sortedRFIs = rfis
        switch sortOption {
        case .title:
            sortedRFIs.sort(by: { ($0.title ?? "").lowercased() < ($1.title ?? "").lowercased() })
        case .date:
            sortedRFIs.sort(by: { rfi1, rfi2 in
                let date1 = ISO8601DateFormatter().date(from: rfi1.createdAt ?? "") ?? Date.distantPast
                let date2 = ISO8601DateFormatter().date(from: rfi2.createdAt ?? "") ?? Date.distantPast
                return date1 > date2
            })
        }
        if searchText.isEmpty {
            return sortedRFIs
        } else {
            return sortedRFIs.filter {
                ($0.title ?? "").lowercased().contains(searchText.lowercased()) ||
                String($0.number).lowercased().contains(searchText.lowercased())
            }
        }
    }

    private struct RFIRow: View {
        let rfi: RFI

        var body: some View {
            HStack {
                Circle()
                    .fill(rfi.status?.lowercased() == "open" ? Color.green : Color.blue.opacity(0.2))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(rfi.title ?? "Untitled RFI")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    Text("RFI-\(rfi.number)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                .padding(.leading, 8)

                Spacer()

                Text(rfi.status ?? "UNKNOWN")
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private func fetchRFIs() {
        isLoading = true
        errorMessage = nil
        APIClient.fetchRFIs(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let r):
                    rfis = r
                    if r.isEmpty {
                        print("No RFIs returned for projectId: \(projectId)")
                    } else {
                        print("Fetched \(r.count) RFIs for projectId: \(projectId)")
                    }
                case .failure(let error):
                    errorMessage = "Failed to load RFIs: \(error.localizedDescription)"
                    print("Error fetching RFIs: \(error)")
                }
            }
        }
    }
}

struct RFIDetailView: View {
    let rfi: RFI
    let token: String

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(rfi.title ?? "Untitled RFI")
                    .font(.title2)
                    .fontWeight(.regular)
                    .foregroundColor(.black)

                Text("RFI-\(rfi.number)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text("Status: \(rfi.status ?? "UNKNOWN")")
                    .font(.subheadline)
                    .foregroundColor(.blue)

                if let createdAt = rfi.createdAt {
                    Text("Created: \(ISO8601DateFormatter().date(from: createdAt)?.formatted() ?? createdAt)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                if let description = rfi.description {
                    Text("Description: \(description)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                if let query = rfi.query {
                    Text("Query: \(query)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        RFIsView(projectId: 1, token: "sample_token")
    }
}
