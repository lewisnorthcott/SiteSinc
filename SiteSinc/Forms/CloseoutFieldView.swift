import SwiftUI
import PhotosUI

struct CloseoutResponse: Codable {
    var status: String
    var notes: String?
    var signature: String?
    var photos: [String]?
    var submittedBy: String?
    var submittedAt: String?
    var approvedBy: String?
    var approvedAt: String?
    var completedAt: String?
}

extension CloseoutResponse: Equatable {
    static func == (lhs: CloseoutResponse, rhs: CloseoutResponse) -> Bool {
        return lhs.status == rhs.status &&
            lhs.notes == rhs.notes &&
            lhs.signature == rhs.signature &&
            lhs.photos == rhs.photos &&
            lhs.submittedBy == rhs.submittedBy &&
            lhs.submittedAt == rhs.submittedAt &&
            lhs.approvedBy == rhs.approvedBy &&
            lhs.approvedAt == rhs.approvedAt &&
            lhs.completedAt == rhs.completedAt
    }
}

struct CloseoutFieldView: View {
    let field: FormField
    @Binding var response: String?
    let formStatus: String?
    let canApprove: Bool
    let submitAction: () -> Void
    let approveAction: () -> Void

    @State private var closeoutData: CloseoutResponse
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var photoPreviews: [UIImage] = []
    @State private var showingSignaturePad = false
    @State private var signatureImage: UIImage?
    
    init(field: FormField, response: Binding<String?>, formStatus: String?, canApprove: Bool, submitAction: @escaping () -> Void, approveAction: @escaping () -> Void) {
        self.field = field
        self._response = response
        self.formStatus = formStatus
        self.canApprove = canApprove
        self.submitAction = submitAction
        self.approveAction = approveAction
        
        if let data = response.wrappedValue?.data(using: .utf8),
           let decodedData = try? JSONDecoder().decode(CloseoutResponse.self, from: data) {
            self._closeoutData = State(initialValue: decodedData)
            // Load existing signature if present
            if let signature = decodedData.signature,
               let data = Data(base64Encoded: signature),
               let image = UIImage(data: data) {
                self._signatureImage = State(initialValue: image)
            } else {
                self._signatureImage = State(initialValue: nil)
            }
        } else {
            self._closeoutData = State(initialValue: CloseoutResponse(status: "pending"))
            self._signatureImage = State(initialValue: nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Removed the duplicate label - parent view already displays it
            
            // Awaiting Submission State
            if !isReadyForCloseout() {
                VStack {
                    Image(systemName: "hourglass")
                        .font(.largeTitle)
                        .padding()
                    Text("Closeout Not Yet Available")
                        .font(.title3)
                    Text("This section will be available after the main form has been submitted and processed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            } else {
                // Active Closeout Form
                VStack(alignment: .leading, spacing: 12) {
                    if field.closeoutSettings?.requiresNotes == true {
                        Text("Close-out Notes")
                            .font(.subheadline).bold()
                        TextEditor(text: Binding(
                            get: { closeoutData.notes ?? "" },
                            set: { closeoutData.notes = $0 }
                        ))
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))
                    }
                    
                    if field.closeoutSettings?.requiresPhotos == true {
                        PhotoUploadView(
                            pickerItems: $photoPickerItems,
                            previews: $photoPreviews,
                            minPhotos: field.closeoutSettings?.minimumPhotos
                        )
                    }
                    
                    if field.closeoutSettings?.requiresSignature == true {
                        SignaturePadContainerView(
                            signatureData: $closeoutData.signature,
                            signatureImage: $signatureImage,
                            showingSignaturePad: $showingSignaturePad
                        )
                    }
                    
                    // Action Buttons
                    actionButtons
                }
            }
        }
        .onChange(of: closeoutData) { _, newData in
            if let encodedData = try? JSONEncoder().encode(newData),
               let jsonString = String(data: encodedData, encoding: .utf8) {
                response = jsonString
            }
        }
        .onChange(of: signatureImage) { _, newImage in
            if let image = newImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                let base64String = imageData.base64EncodedString()
                closeoutData.signature = base64String
            } else {
                closeoutData.signature = nil
            }
        }
        .sheet(isPresented: $showingSignaturePad) {
            SignaturePadView(
                signatureImage: $signatureImage,
                onDismiss: {
                    showingSignaturePad = false
                }
            )
        }
    }

    private func isReadyForCloseout() -> Bool {
        guard let status = formStatus?.lowercased() else { return false }
        let readyStatuses = ["awaiting_closeout", "closeout_pending", "closeout_submitted", "completed"]
        return readyStatuses.contains(status)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if formStatus == "awaiting_closeout" {
                Button(action: submitAction) {
                    Text("Submit Closeout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            
            if formStatus == "closeout_submitted" && canApprove {
                Button(action: approveAction) {
                    Text("Approve Closeout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }
}

// MARK: - Subviews for Photo and Signature
private struct PhotoUploadView: View {
    @Binding var pickerItems: [PhotosPickerItem]
    @Binding var previews: [UIImage]
    let minPhotos: Int?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Completion Photos")
                .font(.subheadline).bold()
            if let min = minPhotos, min > 0 {
                Text("Minimum \(min) photo(s) required")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images) {
                Label("Add Photos", systemImage: "photo")
            }
            .onChange(of: pickerItems) { _, _ in
                Task {
                    previews.removeAll()
                    for item in pickerItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            previews.append(image)
                        }
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(previews, id: \.self) { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                            .clipped()
                    }
                }
            }
        }
    }
}

private struct SignaturePadContainerView: View {
    @Binding var signatureData: String?
    @Binding var signatureImage: UIImage?
    @Binding var showingSignaturePad: Bool

    var body: some View {
        VStack(alignment: .leading) {
            Text("Completion Signature")
                .font(.subheadline).bold()
            
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 150)
                    .cornerRadius(8)
                
                if let image = signatureImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                } else {
                    Text("Tap to sign")
                        .foregroundColor(.secondary)
                }
            }
            .onTapGesture {
                showingSignaturePad = true
            }
            
            if signatureImage != nil {
                Button("Clear Signature") {
                    signatureImage = nil
                    signatureData = nil
                }
                .font(.caption)
                .foregroundColor(.red)
            }
        }
    }
} 

 