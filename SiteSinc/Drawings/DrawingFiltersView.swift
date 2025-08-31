import SwiftUI

struct DrawingFilters: Codable {
    var selectedCompanies: Set<String> = []
    var selectedDisciplines: Set<String> = []
    var selectedTypes: Set<String> = []
    var selectedFolderIds: Set<Int> = []
    var includeArchived: Bool = false
    var showOnlyFavourites: Bool = false

    var hasActiveFilters: Bool {
        !selectedCompanies.isEmpty || !selectedDisciplines.isEmpty || !selectedTypes.isEmpty || !selectedFolderIds.isEmpty || includeArchived || showOnlyFavourites
    }

    func matches(_ drawing: Drawing) -> Bool {
        // Archived filter (default hidden)
        if !includeArchived {
            let drawingArchived = drawing.archived ?? false
            let allRevisionsArchived = drawing.revisions.allSatisfy { $0.archived }
            if drawingArchived || allRevisionsArchived { return false }
        }

        // Company filter
        if !selectedCompanies.isEmpty {
            if let companyName = drawing.company?.name {
                if !selectedCompanies.contains(companyName) {
                    return false
                }
            } else if !selectedCompanies.contains("Unknown Company") {
                return false
            }
        }

        // Discipline filter
        if !selectedDisciplines.isEmpty {
            if let disciplineName = drawing.projectDiscipline?.name {
                if !selectedDisciplines.contains(disciplineName) {
                    return false
                }
            } else if !selectedDisciplines.contains("No Discipline") {
                return false
            }
        }

        // Type filter
        if !selectedTypes.isEmpty {
            if let typeName = drawing.projectDrawingType?.name {
                if !selectedTypes.contains(typeName) {
                    return false
                }
            } else if !selectedTypes.contains("No Type") {
                return false
            }
        }

        // Folder filter with subfolder support
        if !selectedFolderIds.isEmpty {
            if let folderId = drawing.folderId {
                if !selectedFolderIds.contains(folderId) {
                    return false
                }
            } else if !selectedFolderIds.contains(-1) { // -1 represents "No Folder"
                return false
            }
        }

        // Favorites filter
        if showOnlyFavourites {
            let isFavourite = drawing.isFavourite ?? false
            if !isFavourite {
                return false
            }
        }

        return true
    }
}

struct DrawingFiltersView: View {
    @Binding var filters: DrawingFilters
    let drawings: [Drawing]
    let folders: [DrawingFolder]
    @Binding var isPresented: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var availableCompanies: [String] {
        let companies = drawings.compactMap { $0.company?.name }
        let uniqueCompanies = Array(Set(companies)).sorted()
        return uniqueCompanies.isEmpty ? [] : uniqueCompanies
    }
    
    var availableDisciplines: [String] {
        let disciplines = drawings.compactMap { $0.projectDiscipline?.name }
        let uniqueDisciplines = Array(Set(disciplines)).sorted()
        return uniqueDisciplines.isEmpty ? [] : uniqueDisciplines
    }
    
    var availableTypes: [String] {
        let types = drawings.compactMap { $0.projectDrawingType?.name }
        let uniqueTypes = Array(Set(types)).sorted()
        return uniqueTypes.isEmpty ? [] : uniqueTypes
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filters List
                List {
                    // Archived Toggle Section

                    
                    // Company Filter Section
                    if !availableCompanies.isEmpty {
                        Section("Company") {
                            ForEach(availableCompanies, id: \.self) { company in
                                Button(action: {
                                    if filters.selectedCompanies.contains(company) {
                                        filters.selectedCompanies.remove(company)
                                    } else {
                                        filters.selectedCompanies.insert(company)
                                    }
                                }) {
                                    HStack {
                                        Text(company)
                                        Spacer()
                                        if filters.selectedCompanies.contains(company) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Color(hex: "#3B82F6"))
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                    
                    // Discipline Filter Section
                    if !availableDisciplines.isEmpty {
                        Section("Discipline") {
                            ForEach(availableDisciplines, id: \.self) { discipline in
                                Button(action: {
                                    if filters.selectedDisciplines.contains(discipline) {
                                        filters.selectedDisciplines.remove(discipline)
                                    } else {
                                        filters.selectedDisciplines.insert(discipline)
                                    }
                                }) {
                                    HStack {
                                        Text(discipline)
                                        Spacer()
                                        if filters.selectedDisciplines.contains(discipline) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Color(hex: "#3B82F6"))
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                    
                    // Type Filter Section
                    if !availableTypes.isEmpty {
                        Section("Drawing Type") {
                            ForEach(availableTypes, id: \.self) { type in
                                Button(action: {
                                    if filters.selectedTypes.contains(type) {
                                        filters.selectedTypes.remove(type)
                                    } else {
                                        filters.selectedTypes.insert(type)
                                    }
                                }) {
                                    HStack {
                                        Text(type)
                                        Spacer()
                                        if filters.selectedTypes.contains(type) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Color(hex: "#3B82F6"))
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                    
                    // Folder Filter Section
                    if !folders.isEmpty {
                        Section("Folder") {
                            // No Folder option
                            Button(action: {
                                if filters.selectedFolderIds.contains(-1) {
                                    filters.selectedFolderIds.remove(-1)
                                } else {
                                    filters.selectedFolderIds.insert(-1)
                                }
                            }) {
                                HStack {
                                    Text("No Folder")
                                    Spacer()
                                    if filters.selectedFolderIds.contains(-1) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Color(hex: "#3B82F6"))
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                            
                            // Folder options with hierarchy
                            ForEach(folders, id: \.id) { folder in
                                FolderFilterRow(
                                    folder: folder,
                                    level: 0,
                                    selectedFolderIds: $filters.selectedFolderIds
                                )
                            }
                        }
                    } else {
                        Section("Folder") {
                            Text("No folders available")
                                .foregroundColor(.gray)
                        }
                    }

                    // Archived Drawings Section
                    Section("Archived Drawings") {
                        HStack {
                            Text("Show Archived")
                            Spacer()
                            Toggle("", isOn: $filters.includeArchived)
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#3B82F6")))
                        }
                    }

                    // Favorites Section
                    Section("Favorites") {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(Color(hex: "#F59E0B"))
                                .font(.system(size: 16))
                            Text("Show Only Favorites")
                            Spacer()
                            Toggle("", isOn: $filters.showOnlyFavourites)
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#3B82F6")))
                        }
                    }

                    // Clear Filters Section
                    if filters.hasActiveFilters {
                        Section {
                            Button(action: {
                                filters = DrawingFilters()
                            }) {
                                HStack {
                                    Image(systemName: "clear")
                                    Text("Clear All Filters")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }


                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct FolderFilterRow: View {
    let folder: DrawingFolder
    let level: Int
    @Binding var selectedFolderIds: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main folder row
            HStack(spacing: 8) {
                ForEach(0..<level, id: \.self) { _ in
                    Spacer().frame(width: 20)
                }

                Button(action: {
                    toggleFolderSelection(folder)
                }) {
                    HStack(spacing: 8) {
                        Text(folder.name)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if selectedFolderIds.contains(folder.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color(hex: "#3B82F6"))
                        }
                    }
                    .frame(minHeight: 44) // Ensure minimum touch target
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Subfolders - render each as a separate row
            if let subfolders = folder.subfolders {
                ForEach(subfolders, id: \.id) { subfolder in
                    HStack(spacing: 8) {
                        ForEach(0..<(level + 1), id: \.self) { _ in
                            Spacer().frame(width: 20)
                        }

                        Button(action: {
                            toggleFolderSelection(subfolder)
                        }) {
                            HStack(spacing: 8) {
                                Text(subfolder.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if selectedFolderIds.contains(subfolder.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color(hex: "#3B82F6"))
                                }
                            }
                            .frame(minHeight: 44) // Ensure minimum touch target
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

        private func toggleFolderSelection(_ folder: DrawingFolder) {
        if selectedFolderIds.contains(folder.id) {
            // Remove this folder and all its subfolders
            selectedFolderIds.remove(folder.id)
            removeSubfolders(folder)
        } else {
            // Add this folder and all its subfolders
            selectedFolderIds.insert(folder.id)
            addSubfolders(folder)
        }
    }

    private func addSubfolders(_ folder: DrawingFolder) {
        if let subfolders = folder.subfolders {
            for subfolder in subfolders {
                selectedFolderIds.insert(subfolder.id)
                addSubfolders(subfolder)
            }
        }
    }

    private func removeSubfolders(_ folder: DrawingFolder) {
        if let subfolders = folder.subfolders {
            for subfolder in subfolders {
                selectedFolderIds.remove(subfolder.id)
                removeSubfolders(subfolder)
            }
        }
    }
}
