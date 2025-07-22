import SwiftUI

struct PhotoDetailView: View {
    let photos: [PhotoItem]
    let initialPhoto: PhotoItem?
    let initialIndex: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var downloadingPhotoId: String?
    @State private var imageLoadFailed = false
    @State private var retryCount = 0
    @State private var manuallyLoadedImage: UIImage?
    
    // New initializer accepting initialPhoto
    init(photos: [PhotoItem], initialPhoto: PhotoItem) {
        self.photos = photos
        self.initialPhoto = initialPhoto
        self.initialIndex = nil
        let idx = photos.firstIndex(where: { $0.id == initialPhoto.id }) ?? 0
        self._currentIndex = State(initialValue: idx)
        print("PhotoDetailView: init(initialPhoto:) idx=\(idx) id=\(initialPhoto.id)")
    }
    // Existing initializer (kept for backward compatibility)
    init(photos: [PhotoItem], initialIndex: Int) {
        self.photos = photos
        self.initialPhoto = nil
        self.initialIndex = initialIndex
        let idx = min(max(initialIndex,0), photos.count-1)
        self._currentIndex = State(initialValue: idx)
        print("PhotoDetailView: init(initialIndex:) idx=\(idx)")
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Photo viewer
                photoViewerView
                
                // Footer with details
                footerView
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .onTapGesture {
            // Toggle header/footer visibility
        }
        .onAppear {
            print("PhotoDetailView: onAppear called")
            print("PhotoDetailView: photos count = \(photos.count)")
            print("PhotoDetailView: currentIndex = \(currentIndex)")
            print("PhotoDetailView: currentPhoto ID = \(currentPhoto.id)")
            print("PhotoDetailView: currentPhoto URL = \(currentPhoto.url)")
            print("PhotoDetailView: currentPhoto filename = \(currentPhoto.fileName)")
            
            // Force a refresh of the image
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("PhotoDetailView: Triggering image refresh")
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            if photos.count > 1 {
                Text("\(currentIndex + 1) of \(photos.count)")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
            }
            
            Spacer()
            
            Button(action: { handleDownload(currentPhoto) }) {
                Image(systemName: downloadingPhotoId == currentPhoto.id ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .disabled(downloadingPhotoId == currentPhoto.id)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private func imageFromDataURL(_ dataURLString: String) -> UIImage? {
        print("PhotoDetailView: imageFromDataURL called with: \(String(dataURLString.prefix(50)))...")
        guard dataURLString.starts(with: "data:image") else {
            print("PhotoDetailView: Not a data URL")
            return nil
        }
        
        // Extract the base64 data from the data URL
        let components = dataURLString.components(separatedBy: ",")
        guard components.count == 2 else {
            print("PhotoDetailView: Invalid data URL format")
            return nil
        }
        
        let base64String = components[1]
        print("PhotoDetailView: Base64 string length: \(base64String.count)")
        
        guard let data = Data(base64Encoded: base64String) else {
            print("PhotoDetailView: Failed to decode base64 data")
            return nil
        }
        
        print("PhotoDetailView: Data size: \(data.count) bytes")
        
        guard let image = UIImage(data: data) else {
            print("PhotoDetailView: Failed to create UIImage from data")
            return nil
        }
        
        print("PhotoDetailView: Successfully created UIImage from data URL, size: \(image.size)")
        return image
    }
    
    private var photoViewerView: some View {
        GeometryReader { geometry in
            ZStack {
                // Main photo
                let dataImage = imageFromDataURL(currentPhoto.url)
                if let uiImage = dataImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .onAppear {
                            print("PhotoDetailView: Displaying data URL image")
                        }
                } else if let url = URL(string: currentPhoto.url) {
                    if let manualImage = manuallyLoadedImage {
                        Image(uiImage: manualImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                            .onAppear {
                                print("PhotoDetailView: Displaying manually loaded image")
                            }
                    } else {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                VStack {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .foregroundColor(.white)
                                    Text("Loading image...")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                }
                                .onAppear {
                                    print("PhotoDetailView: AsyncImage phase - empty for URL: \(url)")
                                }
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                    .animation(.easeInOut(duration: 0.3), value: url)
                                    .onAppear {
                                        print("PhotoDetailView: AsyncImage phase - success for URL: \(url)")
                                    }
                            case .failure(let error):
                                VStack(spacing: 12) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                    Text("Failed to load image")
                                        .foregroundColor(.gray)
                                        .font(.headline)
                                    Text("URL: \(currentPhoto.url)")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                    Text("Error: \(error.localizedDescription)")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                    
                                    Button("Retry") {
                                        print("PhotoDetailView: Retrying image load")
                                        imageLoadFailed = false
                                        retryCount += 1
                                        // Try manual loading as fallback
                                        Task {
                                            if let image = await loadImageManually(from: currentPhoto.url) {
                                                await MainActor.run {
                                                    manuallyLoadedImage = image
                                                }
                                            }
                                        }
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.top, 8)
                                }
                                .padding()
                                .onAppear {
                                    print("PhotoDetailView: AsyncImage phase - failure: \(error) for URL: \(url)")
                                    // Try manual loading as fallback
                                    Task {
                                        if let image = await loadImageManually(from: currentPhoto.url) {
                                            await MainActor.run {
                                                manuallyLoadedImage = image
                                            }
                                        }
                                    }
                                }
                            @unknown default:
                                VStack {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .foregroundColor(.white)
                                    Text("Unknown state")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                }
                                .onAppear {
                                    print("PhotoDetailView: AsyncImage phase - unknown")
                                }
                            }
                        }
                        .onAppear {
                            print("PhotoDetailView: AsyncImage onAppear for URL: \(currentPhoto.url)")
                            print("PhotoDetailView: Attempting to load URL: \(url)")
                        }
                        .onChange(of: currentPhoto.url) { _, newUrl in
                            print("PhotoDetailView: URL changed to: \(newUrl)")
                            manuallyLoadedImage = nil
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("Invalid URL")
                            .foregroundColor(.gray)
                            .font(.headline)
                        Text("URL: \(currentPhoto.url)")
                            .foregroundColor(.gray)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .onAppear {
                        print("PhotoDetailView: Invalid URL - \(currentPhoto.url)")
                    }
                }
                
                // Navigation arrows
                if photos.count > 1 {
                    HStack {
                        Button(action: previousPhoto) {
                            Image(systemName: "chevron.left")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding(16)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .disabled(currentIndex == 0)
                        
                        Spacer()
                        
                        Button(action: nextPhoto) {
                            Image(systemName: "chevron.right")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding(16)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .disabled(currentIndex == photos.count - 1)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width > threshold && currentIndex > 0 {
                        previousPhoto()
                    } else if value.translation.width < -threshold && currentIndex < photos.count - 1 {
                        nextPhoto()
                    }
                }
        )
    }
    
    private var footerView: some View {
        VStack(spacing: 12) {
            // Source and user info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentPhoto.fileName)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(currentPhoto.uploadedBy.firstName) \(currentPhoto.uploadedBy.lastName)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: sourceIcon)
                            .font(.caption)
                        Text(currentPhoto.source.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(sourceColor)
                    .cornerRadius(4)
                    
                    Text(formatDate(currentPhoto.uploadedAt))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Location info if available
            if let location = currentPhoto.location {
                HStack {
                    Image(systemName: "location")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("\(location.latitude, specifier: "%.6f"), \(location.longitude, specifier: "%.6f")")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Button("View on Map") {
                        openInMaps(latitude: location.latitude, longitude: location.longitude)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var currentPhoto: PhotoItem {
        print("PhotoDetailView: currentPhoto computed property called")
        print("PhotoDetailView: currentIndex = \(currentIndex)")
        print("PhotoDetailView: photos count = \(photos.count)")
        
        guard currentIndex >= 0 && currentIndex < photos.count else {
            print("PhotoDetailView: Index out of bounds, returning first photo or empty")
            return photos.first ?? PhotoItem(
                id: "",
                url: "",
                fileName: "",
                fileType: "",
                uploadedAt: "",
                uploadedBy: PhotoItem.PhotoUser(id: 0, firstName: "", lastName: "", email: ""),
                source: "",
                sourceId: nil,
                sourceTitle: nil,
                location: nil
            )
        }
        
        let photo = photos[currentIndex]
        print("PhotoDetailView: Returning photo at index \(currentIndex): \(photo.id)")
        return photo
    }
    
    private var sourceIcon: String {
        switch currentPhoto.source {
        case "form": return "doc.text"
        case "rfi": return "message.square"
        case "direct": return "camera"
        default: return "photo"
        }
    }
    
    private var sourceColor: Color {
        switch currentPhoto.source {
        case "form": return .blue
        case "rfi": return .orange
        case "direct": return .green
        default: return .gray
        }
    }
    
    private func nextPhoto() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex = min(currentIndex + 1, photos.count - 1)
        }
    }
    
    private func previousPhoto() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex = max(currentIndex - 1, 0)
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
    
    private func loadImageManually(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("PhotoDetailView: Manual image loading failed: \(error)")
            return nil
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
    
    private func openInMaps(latitude: Double, longitude: Double) {
        let url = URL(string: "maps://?q=\(latitude),\(longitude)")!
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Photo Detail Sheet

struct PhotoDetailSheet: View {
    let photos: [PhotoItem]
    let initialPhoto: PhotoItem
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            if let index = photos.firstIndex(where: { $0.id == initialPhoto.id }) {
                PhotoDetailView(photos: photos, initialIndex: index)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
} 