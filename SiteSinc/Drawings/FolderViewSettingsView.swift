import SwiftUI

// Folder View Settings Modal
struct FolderViewSettingsView: View {
    @Binding var settings: FolderViewSettings
    @Binding var isPresented: Bool
    let projectId: Int
    @State private var tempSettings: FolderViewSettings
    
    init(settings: Binding<FolderViewSettings>, isPresented: Binding<Bool>, projectId: Int) {
        self._settings = settings
        self._isPresented = isPresented
        self.projectId = projectId
        self._tempSettings = State(initialValue: settings.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "#3B82F6"))
                        Text("Folder View Settings")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#1F2A44"))
                        Spacer()
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "#6B7280"))
                        }
                    }
                    
                    Text("Customize the hierarchy and order of how drawings are organized in folder view. Drag and drop to reorder, or use the arrows.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Spacer()
                        Button(action: {
                            tempSettings = FolderViewSettings() // Reset to default
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("Reset to Default")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(Color(hex: "#6B7280"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#F3F4F6"))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color(hex: "#FFFFFF"))
                
                // Levels list
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(tempSettings.enabledLevels.count) of \(FolderViewSettings.FolderLevel.allCases.count) levels enabled")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    
                    ForEach(Array(tempSettings.enabledLevels.enumerated()), id: \.offset) { index, level in
                        LevelRow(
                            level: level,
                            index: index,
                            totalCount: tempSettings.enabledLevels.count,
                            onMoveUp: {
                                if index > 0 {
                                    tempSettings.enabledLevels.swapAt(index, index - 1)
                                }
                            },
                            onMoveDown: {
                                if index < tempSettings.enabledLevels.count - 1 {
                                    tempSettings.enabledLevels.swapAt(index, index + 1)
                                }
                            },
                            onToggle: {
                                // Remove from enabled levels
                                tempSettings.enabledLevels.removeAll { $0 == level }
                            },
                            isEnabled: true
                        )
                    }
                    
                    // Show disabled levels
                    ForEach(Array(FolderViewSettings.FolderLevel.allCases.filter { !tempSettings.enabledLevels.contains($0) }), id: \.self) { level in
                        LevelRow(
                            level: level,
                            index: -1,
                            totalCount: 0,
                            onMoveUp: {},
                            onMoveDown: {},
                            onToggle: {
                                // Add to enabled levels
                                tempSettings.enabledLevels.append(level)
                            },
                            isEnabled: false
                        )
                    }
                }
                .background(Color(hex: "#F7F9FC"))
                
                // Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview hierarchy:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "#1F2A44"))
                    
                    Text(tempSettings.enabledLevels.map { $0.rawValue }.joined(separator: " → ") + " → Drawings")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#FFFFFF"))
                
                Spacer()
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(Color(hex: "#6B7280"))
                    
                    Button("Save Settings") {
                        settings = tempSettings
                        settings.save(for: projectId)
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#3B82F6"))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color(hex: "#FFFFFF"))
            }
        }
    }
}

// Level row component
struct LevelRow: View {
    let level: FolderViewSettings.FolderLevel
    let index: Int
    let totalCount: Int
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onToggle: () -> Void
    let isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#9CA3AF"))
            
            // Order number (only for enabled levels)
            if isEnabled && index >= 0 {
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .frame(width: 24)
            } else {
                Text("-")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#D1D5DB"))
                    .frame(width: 24)
            }
            
            // Level name
            Text(level.rawValue)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "#1F2A44"))
            
            Spacer()
            
            // Reorder arrows (only show for enabled levels)
            if isEnabled && index >= 0 {
                HStack(spacing: 8) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12))
                            .foregroundColor(index > 0 ? Color(hex: "#3B82F6") : Color(hex: "#D1D5DB"))
                    }
                    .disabled(index == 0)
                    
                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(index < totalCount - 1 ? Color(hex: "#3B82F6") : Color(hex: "#D1D5DB"))
                    }
                    .disabled(index == totalCount - 1)
                }
            } else {
                Spacer()
                    .frame(width: 40)
            }
            
            // Enabled toggle
            Button(action: onToggle) {
                Text(isEnabled ? "Enabled" : "Disabled")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isEnabled ? .white : Color(hex: "#6B7280"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isEnabled ? Color(hex: "#3B82F6") : Color(hex: "#E5E7EB"))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(hex: "#E5E7EB")),
            alignment: .bottom
        )
    }
}

