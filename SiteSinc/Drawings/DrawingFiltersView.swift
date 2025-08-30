import SwiftUI

struct DrawingFilters: Codable {
    var searchText: String = ""
    var selectedCompanies: Set<String> = []
    var selectedDisciplines: Set<String> = []
    var selectedTypes: Set<String> = []
    var selectedFolderIds: Set<Int> = []
    var includeArchived: Bool = false

    var hasActiveFilters: Bool {
        !searchText.isEmpty || !selectedCompanies.isEmpty || !selectedDisciplines.isEmpty || !selectedTypes.isEmpty || !selectedFolderIds.isEmpty || includeArchived
    }

    func matches(_ drawing: Drawing) -> Bool {
        // Archived filter (default hidden)
        if !includeArchived {
            let drawingArchived = drawing.archived ?? false
            let allRevisionsArchived = drawing.revisions.allSatisfy { $0.archived }
            if drawingArchived || allRevisionsArchived { return false }
        }
        // Text search
        if !searchText.isEmpty {
            let matchesTitle = drawing.title.lowercased().contains(searchText.lowercased())
            let matchesNumber = drawing.number.lowercased().contains(searchText.lowercased())
            if !matchesTitle && !matchesNumber {
                return false
            }
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

        return true
    }
}

struct DrawingFiltersView: View {
    @Binding var filters: DrawingFilters
    let drawings: [Drawing]
    let folders: [DrawingFolder]
    @Binding var isExpanded: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    // Expand/collapse states for sections (defaults collapsed on iPhone)
    @State private var isCompanyExpanded: Bool = false
    @State private var isDisciplineExpanded: Bool = false
    @State private var isTypeExpanded: Bool = false
    @State private var isFolderExpanded: Bool = false

    var availableCompanies: [String] {
        var companies = Set<String>()
        for drawing in drawings {
            if let companyName = drawing.company?.name {
                companies.insert(companyName)
            } else {
                companies.insert("Unknown Company")
            }
        }
        return companies.sorted()
    }

    var availableDisciplines: [String] {
        var disciplines = Set<String>()
        for drawing in drawings {
            if let disciplineName = drawing.projectDiscipline?.name {
                disciplines.insert(disciplineName)
            } else {
                disciplines.insert("No Discipline")
            }
        }
        return disciplines.sorted()
    }

    var availableTypes: [String] {
        var types = Set<String>()
        for drawing in drawings {
            if let typeName = drawing.projectDrawingType?.name {
                types.insert(typeName)
            } else {
                types.insert("No Type")
            }
        }
        return types.sorted()
    }

    var body: some View {
        VStack(spacing: 14) {
            // Compact Header
            HStack(spacing: 12) {
                Text("Filters")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.9)
                    .foregroundColor(Color(hex: "#1F2A44"))

                Spacer()

                if filters.hasActiveFilters {
                    Button(action: {
                        filters = DrawingFilters()
                    }) {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#3B82F6"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#3B82F6").opacity(0.1))
                            .cornerRadius(6)
                    }
                }

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "#F3F4F6"))
                        .cornerRadius(6)
                }
            }

            if isExpanded {
                VStack(spacing: 16) {
                    // Search and Archived in one row
                    HStack(spacing: 16) {
                        // Search (compact)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Search")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#6B7280"))
                                .textCase(.uppercase)
                                .tracking(0.5)

                            SearchBar(text: $filters.searchText)
                                .frame(height: 36)
                        }
                        .frame(maxWidth: .infinity)

                        // Archived toggle (compact)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Archived")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#6B7280"))
                                .textCase(.uppercase)
                                .tracking(0.5)

                            Toggle("", isOn: $filters.includeArchived)
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#3B82F6")))
                                .scaleEffect(0.9)
                        }
                        .frame(width: 90)
                    }

                    // Compact filter sections in responsive grid (prevents header truncation)
                    if !availableCompanies.isEmpty || !availableDisciplines.isEmpty || !availableTypes.isEmpty {
                        let isCompact = horizontalSizeClass == .compact
                        let columns: [GridItem] = isCompact
                            ? [GridItem(.flexible()), GridItem(.flexible())]
                            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            // Company Filter
                            if !availableCompanies.isEmpty {
                                CompactFilterSection(
                                    title: "Company",
                                    options: availableCompanies,
                                    selectedOptions: $filters.selectedCompanies,
                                    isExpanded: $isCompanyExpanded
                                )
                            }

                            // Discipline Filter
                            if !availableDisciplines.isEmpty {
                                CompactFilterSection(
                                    title: "Discipline",
                                    options: availableDisciplines,
                                    selectedOptions: $filters.selectedDisciplines,
                                    isExpanded: $isDisciplineExpanded
                                )
                            }

                            // Type Filter
                            if !availableTypes.isEmpty {
                                CompactFilterSection(
                                    title: "Type",
                                    options: availableTypes,
                                    selectedOptions: $filters.selectedTypes,
                                    isExpanded: $isTypeExpanded
                                )
                            }
                        }
                    }

                    // Folder Filter (full width for hierarchy)
                    if !folders.isEmpty {
                        CompactFolderFilterSection(
                            title: "Folder",
                            folders: folders,
                            selectedFolderIds: $filters.selectedFolderIds,
                            isExpanded: $isFolderExpanded
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct FilterSection: View {
    let title: String
    let options: [String]
    @Binding var selectedOptions: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#374151"))

            VStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    FilterOptionRow(
                        option: option,
                        isSelected: selectedOptions.contains(option),
                        action: {
                            if selectedOptions.contains(option) {
                                selectedOptions.remove(option)
                            } else {
                                selectedOptions.insert(option)
                            }
                        }
                    )
                }
            }
        }
    }
}

struct CompactFilterSection: View {
    let title: String
    let options: [String]
    @Binding var selectedOptions: Set<String>
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isExpanded) {
                // Chips style grid for options
                FlexibleChips(options: options,
                               selected: $selectedOptions)
                    .padding(.top, 4)
            } label: {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FolderFilterSection: View {
    let title: String
    let folders: [DrawingFolder]
    @Binding var selectedFolderIds: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#374151"))

            VStack(spacing: 4) {
                // No Folder option
                FilterOptionRow(
                    option: "No Folder",
                    isSelected: selectedFolderIds.contains(-1),
                    action: {
                        if selectedFolderIds.contains(-1) {
                            selectedFolderIds.remove(-1)
                        } else {
                            selectedFolderIds.insert(-1)
                        }
                    }
                )

                // Folder hierarchy
                ForEach(folders, id: \.id) { folder in
                    FolderRow(
                        folder: folder,
                        level: 0,
                        selectedFolderIds: $selectedFolderIds
                    )
                }
            }
        }
    }
}

struct CompactFolderFilterSection: View {
    let title: String
    let folders: [DrawingFolder]
    @Binding var selectedFolderIds: Set<Int>
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 6) {
                    // No Folder option
                    CompactFilterOptionRow(
                        option: "No Folder",
                        isSelected: selectedFolderIds.contains(-1),
                        action: {
                            if selectedFolderIds.contains(-1) {
                                selectedFolderIds.remove(-1)
                            } else {
                                selectedFolderIds.insert(-1)
                            }
                        }
                    )
                    // Folder hierarchy (compact)
                    ForEach(folders, id: \.id) { folder in
                        CompactFolderRow(
                            folder: folder,
                            level: 0,
                            selectedFolderIds: $selectedFolderIds
                        )
                    }
                }
                .padding(.top, 4)
            } label: {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
    }
}

struct FolderRow: View {
    let folder: DrawingFolder
    let level: Int
    @Binding var selectedFolderIds: Set<Int>

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Indentation
                ForEach(0..<level, id: \.self) { _ in
                    Spacer().frame(width: 16)
                }

                FilterOptionRow(
                    option: folder.name,
                    isSelected: selectedFolderIds.contains(folder.id),
                    action: {
                        if selectedFolderIds.contains(folder.id) {
                            selectedFolderIds.remove(folder.id)
                            // Also remove all subfolders
                            removeSubfolders(folder)
                        } else {
                            selectedFolderIds.insert(folder.id)
                            // Also select all subfolders
                            addSubfolders(folder)
                        }
                    }
                )
            }

            // Subfolders
            if let subfolders = folder.subfolders {
                ForEach(subfolders, id: \.id) { subfolder in
                    FolderRow(
                        folder: subfolder,
                        level: level + 1,
                        selectedFolderIds: $selectedFolderIds
                    )
                }
            }
        }
    }

    private func addSubfolders(_ folder: DrawingFolder) {
        if let subfolders = folder.subfolders {
            for subfolder in subfolders {
                selectedFolderIds.insert(subfolder.id)
                addSubfolders(subfolder) // Recursive for nested subfolders
            }
        }
    }

    private func removeSubfolders(_ folder: DrawingFolder) {
        if let subfolders = folder.subfolders {
            for subfolder in subfolders {
                selectedFolderIds.remove(subfolder.id)
                removeSubfolders(subfolder) // Recursive for nested subfolders
            }
        }
    }
}

struct FilterOptionRow: View {
    let option: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(option)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#1F2A44"))
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(Color(hex: "#3B82F6"))
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color(hex: "#3B82F6").opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CompactFilterOptionRow: View {
    let option: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Color(hex: "#3B82F6") : Color(hex: "#D1D5DB"))

                Text(option)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "#374151"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color(hex: "#3B82F6").opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

struct CompactFolderRow: View {
    let folder: DrawingFolder
    let level: Int
    @Binding var selectedFolderIds: Set<Int>

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Indentation (compact)
                ForEach(0..<level, id: \.self) { _ in
                    Spacer().frame(width: 12)
                }

                CompactFilterOptionRow(
                    option: folder.name,
                    isSelected: selectedFolderIds.contains(folder.id),
                    action: {
                        if selectedFolderIds.contains(folder.id) {
                            selectedFolderIds.remove(folder.id)
                            removeSubfolders(folder)
                        } else {
                            selectedFolderIds.insert(folder.id)
                            addSubfolders(folder)
                        }
                    }
                )
            }

            // Subfolders (compact)
            if let subfolders = folder.subfolders {
                ForEach(subfolders, id: \.id) { subfolder in
                    CompactFolderRow(
                        folder: subfolder,
                        level: level + 1,
                        selectedFolderIds: $selectedFolderIds
                    )
                }
            }
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

// MARK: - Chips grid for multi-select options
struct FlexibleChips: View {
    let options: [String]
    @Binding var selected: Set<String>

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.contains(option)
                Button(action: {
                    if isOn { selected.remove(option) } else { selected.insert(option) }
                }) {
                    HStack(spacing: 6) {
                        Text(option)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(isOn ? Color(hex: "#1F2A44") : Color(hex: "#374151"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isOn ? Color(hex: "#3B82F6").opacity(0.15) : Color.gray.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(isOn ? Color(hex: "#3B82F6") : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isOn ? "Remove" : "Add") filter \(option)")
            }
        }
    }
}
