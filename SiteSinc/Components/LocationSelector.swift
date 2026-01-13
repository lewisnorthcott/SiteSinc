import SwiftUI

struct LocationSelector: View {
    let projectId: Int
    let token: String
    @Binding var selectedLocationId: Int?
    let placeholder: String
    
    @State private var locations: [ProjectLocation] = []
    @State private var isLoading = false
    @State private var showLocationPicker = false
    
    init(projectId: Int, token: String, selectedLocationId: Binding<Int?>, placeholder: String = "Select location...") {
        self.projectId = projectId
        self.token = token
        self._selectedLocationId = selectedLocationId
        self.placeholder = placeholder
    }
    
    var body: some View {
        HStack {
            Text("Location")
            Spacer()
            Button(action: {
                showLocationPicker = true
            }) {
                Text(selectedLocationName ?? placeholder)
            }
            .foregroundColor(selectedLocationId == nil ? .secondary : .accentColor)
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(
                projectId: projectId,
                token: token,
                selectedLocationId: $selectedLocationId,
                onDismiss: { showLocationPicker = false }
            )
        }
        .onAppear {
            loadLocationsForDisplay()
        }
    }
    
    private var selectedLocationName: String? {
        guard let locationId = selectedLocationId else { return nil }
        return findLocationName(id: locationId, in: locations)
    }
    
    private func findLocationName(id: Int, in locations: [ProjectLocation]) -> String? {
        for location in locations {
            if location.id == id {
                return location.code != nil ? "\(location.name) (\(location.code!))" : location.name
            }
            if let children = location.children, let found = findLocationName(id: id, in: children) {
                return found
            }
        }
        return nil
    }
    
    // Load locations just for displaying the selected location name
    private func loadLocationsForDisplay() {
        guard locations.isEmpty && !isLoading else { return }
        
        Task {
            isLoading = true
            do {
                let fetchedLocations = try await APIClient.fetchProjectLocations(projectId: projectId, token: token)
                await MainActor.run {
                    self.locations = fetchedLocations
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

struct LocationPickerView: View {
    let projectId: Int
    let token: String
    @Binding var selectedLocationId: Int?
    let onDismiss: () -> Void
    
    @State private var locations: [ProjectLocation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading locations...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: loadLocations) {
                        Text("Retry")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if locations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No locations available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Locations can be created in the web app")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(locations) { location in
                            LocationRow(
                                location: location,
                                selectedLocationId: $selectedLocationId,
                                level: 0,
                                onLocationSelected: {
                                    // Auto-dismiss only for leaf nodes (handled in LocationRow)
                                    dismiss()
                                    onDismiss()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Select Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                    onDismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if selectedLocationId != nil {
                        Button {
                            selectedLocationId = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                        }
                    }
                    
                    Button {
                        dismiss()
                        onDismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .onAppear {
            loadLocations()
        }
    }
    
    private func loadLocations() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                print("🔍 [LocationPickerView] Fetching locations for project \(projectId)")
                let fetchedLocations = try await APIClient.fetchProjectLocations(projectId: projectId, token: token)
                print("🔍 [LocationPickerView] ✅ Fetched \(fetchedLocations.count) top-level locations")
                for loc in fetchedLocations {
                    print("🔍 [LocationPickerView]   - \(loc.name) (id: \(loc.id), children: \(loc.children?.count ?? 0))")
                }
                await MainActor.run {
                    self.locations = fetchedLocations
                    self.isLoading = false
                }
            } catch {
                print("🔍 [LocationPickerView] Error: \(error)")
                await MainActor.run {
                    self.isLoading = false
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .invalidResponse(let statusCode):
                            if statusCode == 404 {
                                // No error message - just show "no locations"
                                self.locations = []
                            } else {
                                self.errorMessage = "Failed to load locations (status: \(statusCode))"
                            }
                        case .decodingError:
                            self.errorMessage = "Failed to parse locations data"
                        case .networkError:
                            self.errorMessage = "Network error. Check your connection."
                        default:
                            self.errorMessage = "Failed to load locations"
                        }
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

struct LocationRow: View {
    let location: ProjectLocation
    @Binding var selectedLocationId: Int?
    let level: Int
    let onLocationSelected: () -> Void
    
    @State private var isExpanded = true // Start expanded by default
    
    private var hasChildren: Bool {
        guard let children = location.children else { return false }
        return !children.isEmpty
    }
    
    private var isSelected: Bool {
        selectedLocationId == location.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 0) {
                // Selection button - can select any location
                Button(action: {
                    selectedLocationId = location.id
                    // Auto-dismiss only for leaf nodes (no children)
                    if !hasChildren {
                        onLocationSelected()
                    }
                }) {
                    HStack(spacing: 12) {
                        // Indentation spacer
                        if level > 0 {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: CGFloat(level) * 24)
                        }
                        
                        // Expand/collapse indicator or location icon
                        ZStack {
                            if hasChildren {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.6))
                            }
                        }
                        .frame(width: 20)
                        
                        // Location info
                        VStack(alignment: .leading, spacing: 3) {
                            Text(location.name)
                                .font(.system(size: 16, weight: hasChildren ? .medium : .regular))
                                .foregroundColor(.primary)
                            
                            if let code = location.code, !code.isEmpty {
                                Text(code)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Selection checkmark
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                // Expand/collapse button for locations with children
                if hasChildren {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            
            // Children
            if isExpanded, let children = location.children, !children.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children) { child in
                        LocationRow(
                            location: child,
                            selectedLocationId: $selectedLocationId,
                            level: level + 1,
                            onLocationSelected: onLocationSelected
                        )
                    }
                }
            }
        }
    }
}
