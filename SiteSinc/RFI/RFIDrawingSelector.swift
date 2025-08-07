import SwiftUI

struct RFIDrawingSelector: View {
    let projectId: Int
    let rfiId: Int
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var drawings: [Drawing] = []
    @State private var selectedDrawings: [Drawing] = []
    @State private var loading = true
    @State private var linking = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if loading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading drawings...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else if let errorMessage = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            fetchDrawings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select drawings to link")
                            .font(.headline)
                        
                        Text("\(selectedDrawings.count) drawing\(selectedDrawings.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(drawings, id: \.id) { drawing in
                                    DrawingSelectionRow(
                                        drawing: drawing,
                                        isSelected: selectedDrawings.contains { $0.id == drawing.id },
                                        onToggle: { toggleDrawing(drawing) }
                                    )
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                if !selectedDrawings.isEmpty {
                    Button("Link Selected Drawings (\(selectedDrawings.count))") {
                        linkDrawings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(linking)
                }
            }
            .padding()
            .navigationTitle("Link Drawings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            fetchDrawings()
        }
    }
    
    private func fetchDrawings() {
        loading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedDrawings = try await APIClient.fetchDrawings(projectId: projectId, token: "")
                await MainActor.run {
                    drawings = fetchedDrawings
                    loading = false
                }
            } catch {
                await MainActor.run {
                    loading = false
                    errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func toggleDrawing(_ drawing: Drawing) {
        if selectedDrawings.contains(where: { $0.id == drawing.id }) {
            selectedDrawings.removeAll { $0.id == drawing.id }
        } else {
            selectedDrawings.append(drawing)
        }
    }
    
    private func linkDrawings() {
        guard !selectedDrawings.isEmpty else { return }
        
        linking = true
        
        Task {
            do {
                let url = URL(string: "\(APIClient.baseURL)/rfis/\(rfiId)/drawings")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let drawingIds = selectedDrawings.map { $0.id }
                let body = ["drawingIds": drawingIds]
                request.httpBody = try JSONEncoder().encode(body)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    linking = false
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        onSuccess()
                        dismiss()
                    } else {
                        errorMessage = "Failed to link drawings"
                    }
                }
            } catch {
                await MainActor.run {
                    linking = false
                    errorMessage = "Failed to link drawings: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct DrawingSelectionRow: View {
    let drawing: Drawing
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(drawing.number)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(drawing.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    Text("Rev \(latestRevision.revisionNumber ?? String(latestRevision.versionNumber))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
} 