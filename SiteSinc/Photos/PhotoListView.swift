import SwiftUI
import PhotosUI

struct PhotoIndex: Identifiable {
    let id: Int
}

struct PhotoListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @State private var photos: [PhotoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchQuery = ""
    @State private var sourceFilter = "all"
    @State private var dateFilter = "all"
    @State private var showUploadModal = false
    @State private var selectedPhoto: PhotoItem? = nil
    @State private var currentPhotoIndex = 0
    @State private var downloadingPhotoId: String?
    @State private var photoCount = 0
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Filters
                filterView
                
                // Photos Grid
                photosGridView
            }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showUploadModal) {
            PhotoUploadModal(
                isOpen: $showUploadModal,
                projectId: projectId,
                onUploadSuccess: {
                    Task {
                        await fetchPhotos()
                    }
                }
            )
            .environmentObject(sessionManager)
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            if let index = filteredPhotos.firstIndex(where: { $0.id == photo.id }) {
                PhotoDetailView(photos: filteredPhotos, initialIndex: index)
            }
        }
        .interactiveDismissDisabled(false)
        .onAppear {
            print("PhotoListView: onAppear called")
            print("PhotoListView: projectId = \(projectId)")
            print("PhotoListView: token = \(token)")
            Task {
                await fetchPhotos()
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Photos")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    let photoCountText = "\(filteredPhotos.count) photo\(filteredPhotos.count != 1 ? "s" : "")"
                    let totalCountText = photos.count != filteredPhotos.count ? " (filtered from \(photos.count) total)" : ""
                    Text(photoCountText + totalCountText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if hasUploadPermission {
                    Button(action: { showUploadModal = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Upload")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
    
    private var filterView: some View {
        VStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search photos...", text: $searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal, 16)
            
            // Filter buttons
            HStack(spacing: 12) {
                FilterButton(
                    title: "All",
                    isSelected: sourceFilter == "all",
                    action: { sourceFilter = "all" }
                )
                
                FilterButton(
                    title: "Direct",
                    isSelected: sourceFilter == "direct",
                    action: { sourceFilter = "direct" }
                )
                
                FilterButton(
                    title: "Forms",
                    isSelected: sourceFilter == "form",
                    action: { sourceFilter = "form" }
                )
                
                FilterButton(
                    title: "RFI",
                    isSelected: sourceFilter == "rfi",
                    action: { sourceFilter = "rfi" }
                )
                
                Spacer()
                
                Button("Clear") {
                    searchQuery = ""
                    sourceFilter = "all"
                    dateFilter = "all"
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var photosGridView: some View {
        Group {
            if isLoading {
                loadingView
            } else if filteredPhotos.isEmpty {
                emptyStateView
            } else {
                photoGrid
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading photos...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No photos found")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(photos.isEmpty ? "No photos have been uploaded to this project yet." : "No photos match your current filters.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if photos.isEmpty && hasUploadPermission {
                Button(action: { showUploadModal = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Upload First Photo")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(filteredPhotos.enumerated()), id: \.element.id) { index, photo in
                    PhotoThumbnail(
                        photo: photo,
                        onTap: { 
                            print("PhotoListView: Tapped photo at index: \(index), ID: \(photo.id)")
                            print("PhotoListView: Photo URL: \(photo.url)")
                            print("PhotoListView: Photo filename: \(photo.fileName)")
                            print("PhotoListView: filteredPhotos count: \(filteredPhotos.count)")
                            selectedPhoto = photo
                        },
                        onDownload: { handleDownload(photo) },
                        isDownloading: downloadingPhotoId == photo.id
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .refreshable {
            await fetchPhotos()
        }
    }
    
    private var filteredPhotos: [PhotoItem] {
        photos.filter { photo in
            let searchLower = searchQuery.lowercased()
            let fileNameLower = photo.fileName.lowercased()
            let firstNameLower = photo.uploadedBy.firstName.lowercased()
            let lastNameLower = photo.uploadedBy.lastName.lowercased()
            
            let matchesSearch = searchQuery.isEmpty ||
                fileNameLower.contains(searchLower) ||
                firstNameLower.contains(searchLower) ||
                lastNameLower.contains(searchLower)
            
            let matchesSource = sourceFilter == "all" || photo.source == sourceFilter
            
            return matchesSearch && matchesSource
        }
    }
    
    private var hasUploadPermission: Bool {
        // Only show upload if user has the upload_photos permission
        return sessionManager.hasPermission("upload_photos")
    }
    
    private func fetchPhotos() async {
        print("PhotoListView: fetchPhotos() called")
        isLoading = true
        errorMessage = nil
        
        do {
            print("PhotoListView: Starting to fetch photos from different sources")
            // Fetch photos from different sources
            let results = try await withThrowingTaskGroup(of: [PhotoItem].self) { group in
                print("PhotoListView: Adding task for project photos")
                group.addTask {
                    print("PhotoListView: Fetching project photos...")
                    let photos = try await APIClient.fetchProjectPhotos(projectId: projectId, token: token)
                    print("PhotoListView: Fetched \(photos.count) project photos")
                    return photos
                }
                
                print("PhotoListView: Adding task for form photos")
                group.addTask {
                    print("PhotoListView: Fetching form photos...")
                    let photos = try await APIClient.fetchFormPhotos(projectId: projectId, token: token)
                    print("PhotoListView: Fetched \(photos.count) form photos")
                    return photos
                }
                
                print("PhotoListView: Adding task for RFI photos")
                group.addTask {
                    print("PhotoListView: Fetching RFI photos...")
                    let photos = try await APIClient.fetchRFIPhotos(projectId: projectId, token: token)
                    print("PhotoListView: Fetched \(photos.count) RFI photos")
                    return photos
                }
                
                var allResults: [[PhotoItem]] = []
                for try await result in group {
                    allResults.append(result)
                }
                return allResults
            }
            
            let allPhotos = results.flatMap { $0 }
            let sortedPhotos = allPhotos.sorted { $0.uploadedAt > $1.uploadedAt }
            
            print("PhotoListView: Total photos fetched: \(sortedPhotos.count)")
            
            await MainActor.run {
                print("PhotoListView: Updating UI with \(sortedPhotos.count) photos")
                for (index, photo) in sortedPhotos.enumerated() {
                    print("PhotoListView: Photo \(index): ID=\(photo.id), URL=\(photo.url), Filename=\(photo.fileName)")
                }
                self.photos = sortedPhotos
                self.photoCount = sortedPhotos.count
                self.isLoading = false
                print("PhotoListView: UI updated successfully")
            }
        } catch {
            print("PhotoListView: Error fetching photos: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to load photos: \(error.localizedDescription)"
                self.isLoading = false
                print("PhotoListView: Error state set in UI")
            }
        }
    }
    
    private func handleDownload(_ photo: PhotoItem) {
        downloadingPhotoId = photo.id
        
        // Implement download logic here
        // This would typically involve downloading the file and saving it to the device
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            downloadingPhotoId = nil
        }
    }
}

// MARK: - Supporting Views

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .cornerRadius(6)
        }
    }
}

struct PhotoThumbnail: View {
    let photo: PhotoItem
    let onTap: () -> Void
    let onDownload: () -> Void
    let isDownloading: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let uiImage = imageFromDataURL(photo.url) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipped()
                }
                else if let url = URL(string: photo.url) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(width: 100, height: 100)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.gray)
                        )
                }

                
                // Source badge
                HStack(spacing: 2) {
                    Image(systemName: sourceIcon)
                        .font(.system(size: 8))
                    Text(photo.source.uppercased())
                        .font(.system(size: 6, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(sourceColor)
                .cornerRadius(4)
                .padding(4)
                
                // Download button
                Button(action: onDownload) {
                    Image(systemName: isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .disabled(isDownloading)
                .padding(4)
                .offset(x: -4, y: 4)
            }
            
            VStack(spacing: 2) {
                Text(photo.fileName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text("\(photo.uploadedBy.firstName) \(photo.uploadedBy.lastName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 100)
        }
        .onTapGesture(perform: onTap)
    }
    
    private var sourceIcon: String {
        switch photo.source {
        case "form": return "doc.text"
        case "rfi": return "message.square"
        case "direct": return "camera"
        default: return "photo"
        }
    }
    
    private var sourceColor: Color {
        switch photo.source {
        case "form": return .blue
        case "rfi": return .orange
        case "direct": return .green
        default: return .gray
        }
    }
    
    private func imageFromDataURL(_ dataURLString: String) -> UIImage? {
        guard dataURLString.starts(with: "data:image") else {
            return nil
        }
        
        // Extract the base64 data from the data URL
        let components = dataURLString.components(separatedBy: ",")
        guard components.count == 2 else {
            print("PhotoListView: Invalid data URL format")
            return nil
        }
        
        let base64String = components[1]
        
        guard let data = Data(base64Encoded: base64String) else {
            print("PhotoListView: Failed to decode base64 data")
            return nil
        }
        
        guard let image = UIImage(data: data) else {
            print("PhotoListView: Failed to create UIImage from data")
            return nil
        }
        
        print("PhotoListView: Successfully created UIImage from data URL")
        return image
    }
}

// MARK: - Photo Upload Modal

struct PhotoUploadModal: View {
    @Binding var isOpen: Bool
    let projectId: Int
    let onUploadSuccess: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var description = ""
    @State private var selectedImages: [UIImage] = []
    @State private var capturedPhotos: [PhotoWithLocation] = []
    @State private var showCamera = false
    @State private var showSuccessMessage = false
    @State private var showErrorMessage = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Buttons for selecting or taking photos
                photoSelectionButtons
                
                // Preview of selected/taken images
                if !selectedImages.isEmpty {
                    imagePreviewSection
                }
                
                // Description field
                descriptionSection
                
                Spacer()
                
                // Upload button
                uploadButton
            }
            .padding()
            .navigationTitle("Upload Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isOpen = false
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CustomCameraView(capturedImages: $capturedPhotos)
            }
            .onChange(of: capturedPhotos) { _, newPhotos in
                for photo in newPhotos {
                    if let image = UIImage(data: photo.image) {
                        selectedImages.append(image)
                    }
                }
                // Clear the captured photos array after processing
                capturedPhotos = []
            }
            .onChange(of: selectedPhotos) { _, newItems in
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                selectedImages.append(image)
                            }
                        }
                    }
                    // Clear the selection to allow re-selection of the same items
                    await MainActor.run {
                        selectedPhotos = []
                    }
                }
            }
            .alert("Upload Successful", isPresented: $showSuccessMessage) {
                Button("OK") { }
            } message: {
                Text("Your photos have been uploaded successfully!")
            }
            .alert("Upload Failed", isPresented: $showErrorMessage) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var photoSelectionButtons: some View {
        HStack(spacing: 16) {
            cameraButton
            photoLibraryButton
        }
    }
    
    private var cameraButton: some View {
        Button(action: { showCamera = true }) {
            VStack(spacing: 8) {
                Image(systemName: "camera")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                Text("Take Photo")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var photoLibraryButton: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: 10,
            matching: .images
        ) {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                Text("Select from Library")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var imagePreviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(selectedImages.indices, id: \.self) { index in
                    imagePreviewItem(for: index)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 100)
    }
    
    private func imagePreviewItem(for index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: selectedImages[index])
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipped()
                .cornerRadius(8)
            
            Button(action: { selectedImages.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 20))
            }
            .offset(x: 8, y: -8)
        }
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description (Optional)")
                .font(.subheadline)
                .fontWeight(.medium)
            
            TextField("Add a description...", text: $description, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)
        }
    }
    
    private var uploadButton: some View {
        Button(action: uploadPhotos) {
            HStack(spacing: 8) {
                if isUploading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                }
                Text(isUploading ? "Uploading..." : "Upload Photos")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(buttonBackgroundColor)
            .cornerRadius(8)
        }
        .disabled(isUploading || (selectedImages.isEmpty && selectedPhotos.isEmpty))
    }
    
    private var buttonBackgroundColor: Color {
        return (selectedImages.isEmpty && selectedPhotos.isEmpty) ? Color.gray : Color.blue
    }
    
    private func uploadPhotos() {
        isUploading = true
        
        Task {
            do {
                let url = URL(string: "\(APIClient.baseURL)/photos/upload")!
                let boundary = "Boundary-\(UUID().uuidString)"
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(sessionManager.token ?? "")", forHTTPHeaderField: "Authorization")
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                var body = Data()

                // Add projectId
                body.append("--\(boundary)\r\n")
                body.append("Content-Disposition: form-data; name=\"projectId\"\r\n\r\n")
                body.append("\(projectId)\r\n")

                // Add description only if not empty
                if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    body.append("--\(boundary)\r\n")
                    body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n")
                    body.append("\(description)\r\n")
                }

                // Add files
                if selectedImages.isEmpty {
                    throw APIError.invalidResponse(statusCode: 400)
                }
                for (_, image) in selectedImages.enumerated() {
                    let fileName = "photo_\(UUID().uuidString).jpg"
                    guard let jpegData = image.jpegData(compressionQuality: 0.8) else { continue }
                    body.append("--\(boundary)\r\n")
                    body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n")
                    body.append("Content-Type: image/jpeg\r\n\r\n")
                    body.append(jpegData)
                    body.append("\r\n")
                }

                body.append("--\(boundary)--\r\n")
                request.httpBody = body

                // Optional: print body size for debugging
                print("Upload body size: \(body.count) bytes")

                let (responseData, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
                    throw APIError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
                }

                do {
                    let responseDict = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                    print("Upload response: \(responseDict ?? [:])")
                } catch {
                    print("Could not parse upload response: \(error)")
                }

                await MainActor.run {
                    isUploading = false
                    showSuccessMessage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isOpen = false
                        onUploadSuccess()
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    errorMessage = "Failed to upload photos: \(error.localizedDescription)"
                    showErrorMessage = true
                    print("Upload error: \(error)")
                }
            }
        }
    }
}

// MARK: - Photo Item Model

struct PhotoItem: Identifiable, Codable, Equatable {
    let id: String
    let url: String
    let fileName: String
    let fileType: String
    let uploadedAt: String
    let uploadedBy: PhotoUser
    let source: String // "form", "rfi", "direct"
    let sourceId: Int?
    let sourceTitle: String?
    let location: PhotoLocation?
    
    struct PhotoUser: Codable, Equatable {
        let id: Int
        let firstName: String
        let lastName: String
        let email: String
    }
    
    struct PhotoLocation: Codable, Equatable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
    }
}

 