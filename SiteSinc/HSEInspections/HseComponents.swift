import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Shared HSE UI pieces

struct HseInspectionStatusBadge: View {
    let status: HseInspectionStatus

    var body: some View {
        Text(status.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .foregroundColor(status.color)
            .clipShape(Capsule())
    }
}

struct HseObservationStatusBadge: View {
    let status: HseObservationStatus

    var body: some View {
        Text(status.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .foregroundColor(status.color)
            .clipShape(Capsule())
    }
}

// MARK: - Observation input (shared by server + offline save paths)

struct HseObservationInput {
    var sectionId: String
    var description: String = ""
    var categoryId: Int?
    var categoryData: [String: String] = [:]
    var assignedToId: Int?
    var dueDate: Date?
    var locationId: Int?
}

/// A photo captured/selected but not yet uploaded.
struct HsePendingPhoto: Identifiable, Equatable {
    let id: String
    let data: Data
    let capturedAt: Date
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?

    init(data: Data, capturedAt: Date = Date(), latitude: Double? = nil, longitude: Double? = nil, accuracy: Double? = nil) {
        self.id = UUID().uuidString
        self.data = data
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }
}

// MARK: - Photo capture section (camera + library)

struct HsePhotoPickerSection: View {
    @Binding var photos: [HsePendingPhoto]
    var title: String = "Photos"

    @State private var showActionSheet = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    showActionSheet = true
                } label: {
                    Label("Add Photo", systemImage: "camera.fill")
                        .font(.caption)
                }
            }

            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(data: photo.data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Button {
                                    photos.removeAll { $0.id == photo.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .padding(3)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Add Photo", isPresented: $showActionSheet, titleVisibility: .visible) {
            Button("Take Photo") { requestCamera() }
            Button("Choose From Library") { showLibraryPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerWithLocation(
                onImageCaptured: { captured in
                    Task { await appendCameraPhoto(captured) }
                },
                onDismiss: { showCamera = false }
            )
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $pickerItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await processLibraryItems(newItems) }
        }
    }

    private func requestCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            showCamera = true
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true }
                }
            }
        }
    }

    private func appendCameraPhoto(_ captured: PhotoWithLocation) async {
        // Camera delivers immediately with location often nil; grab a
        // best-effort fix so the server can stamp the photo.
        var latitude = captured.location?.coordinate.latitude
        var longitude = captured.location?.coordinate.longitude
        var accuracy = captured.location?.horizontalAccuracy
        if latitude == nil, let fix = await LocationManager.shared.getCurrentLocation() {
            latitude = fix.coordinate.latitude
            longitude = fix.coordinate.longitude
            accuracy = fix.horizontalAccuracy
        }
        photos.append(HsePendingPhoto(
            data: captured.image,
            capturedAt: captured.capturedAt,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy
        ))
    }

    private func processLibraryItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photos.append(HsePendingPhoto(data: data))
            }
        }
        pickerItems = []
    }
}

// MARK: - User select sheet (assignee / accompanied by / key personnel)

struct HseUserSelectSheet: View {
    let users: [HseUser]
    var excludedIds: Set<Int> = []
    var allowClear: Bool = false
    let onSelect: (HseUser?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [HseUser] {
        let available = users.filter { !excludedIds.contains($0.id) }
        guard !searchText.isEmpty else { return available }
        return available.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowClear {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("Unassigned", systemImage: "person.slash")
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(filtered) { user in
                    Button {
                        onSelect(user)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .foregroundColor(.primary)
                            Text(user.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search project members...")
            .navigationTitle("Select Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Remote photo thumbnail with presigned-URL refresh

struct HseRemotePhotoThumb: View {
    let photo: HseObservationPhoto
    let projectId: Int
    let token: String
    var size: CGFloat = 72

    @State private var refreshedUrl: String?
    @State private var failed = false

    private var urlString: String? { refreshedUrl ?? photo.fileUrl }

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString), !failed {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                            .task { await refreshUrl() }
                    default:
                        ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .overlay(Image(systemName: photo.isImage ? "photo" : "doc").foregroundColor(.secondary))
    }

    private func refreshUrl() async {
        guard refreshedUrl == nil, let fileKey = photo.fileKey else {
            failed = true
            return
        }
        do {
            refreshedUrl = try await APIClient.refreshHseFileUrl(fileKey: fileKey, token: token)
        } catch {
            failed = true
        }
    }
}
