import SwiftUI
import PhotosUI
import CoreImage.CIFilterBuiltins

struct ToolboxTalkDeliverView: View {
    let projectId: Int
    let talkId: Int
    let sessionId: Int
    let token: String

    @EnvironmentObject var sessionManager: SessionManager
    @State private var session: ToolboxTalkSession?
    @State private var content: ToolboxTalkContent = .empty
    @State private var notes: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isStarting = false
    @State private var isCompleting = false
    @State private var isSavingNotes = false
    @State private var walkInName = ""
    @State private var walkInCompany = ""
    @State private var signatureImage: UIImage?
    @State private var showSignaturePad = false
    @State private var isSigning = false
    @State private var selfSignMode = false
    @State private var qrURLString: String?
    @State private var isGeneratingQR = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingAttachment = false
    @State private var showCompleteConfirm = false

    private var canDeliver: Bool { ToolboxTalkPermissions.canDeliver(user: sessionManager.user) }
    private var canManageAttendees: Bool { ToolboxTalkPermissions.canManageAttendees(user: sessionManager.user) }
    private var canProxySign: Bool { ToolboxTalkPermissions.canProxySign(user: sessionManager.user) }
    private var canView: Bool { ToolboxTalkPermissions.canView(user: sessionManager.user) }

    private var isTerminal: Bool {
        let status = session?.status ?? ""
        return status == "COMPLETED" || status == "CANCELLED"
    }

    private var unsignedAttendees: [ToolboxTalkAttendee] {
        (session?.attendees ?? []).filter { !$0.hasSigned }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading session...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, session == nil {
                VStack(spacing: 12) {
                    Text(errorMessage).foregroundColor(.secondary)
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sessionHeader
                        if canDeliver && !isTerminal {
                            actionBar
                        }
                        contentSection
                        if canDeliver && !isTerminal {
                            notesSection
                            attachmentsSection
                        } else if !(session?.attachments ?? []).isEmpty {
                            attachmentsSection
                        }
                        if canManageAttendees || canDeliver {
                            qrSection
                        }
                        attendeesSection
                        if !isTerminal {
                            signingSection
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Deliver session")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(showSpinner: false) }
        .sheet(isPresented: $showSignaturePad) {
            SignaturePadView(signatureImage: $signatureImage) {
                Task { await submitSignature() }
            }
        }
        .confirmationDialog(
            "Complete session?",
            isPresented: $showCompleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Complete anyway", role: .destructive) {
                Task { await completeSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(unsignedAttendees.count) attendee(s) have not signed yet.")
        }
        .alert("Notice", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await uploadPickedPhoto(item) }
        }
        .trackPageView("/projects/\(projectId)/toolbox-talks/\(talkId)/sessions/\(sessionId)/deliver", projectId: projectId)
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session {
                HStack {
                    ToolboxTalkSessionStatusChip(status: session.status ?? "SCHEDULED")
                    Spacer()
                }
                if let location = session.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let scheduled = session.scheduledFor {
                    Label(scheduled, systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if session?.status == "SCHEDULED" {
                Button {
                    Task { await startSession() }
                } label: {
                    if isStarting {
                        ProgressView()
                    } else {
                        Label("Start", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStarting)
            }

            Button {
                if unsignedAttendees.isEmpty {
                    Task { await completeSession() }
                } else {
                    showCompleteConfirm = true
                }
            } label: {
                if isCompleting {
                    ProgressView()
                } else {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isCompleting)
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Talk content")
                .font(.title3.weight(.semibold))
            ToolboxTalkContentEditor(content: $content, readOnly: true, token: token)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session notes")
                .font(.title3.weight(.semibold))
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            Button(isSavingNotes ? "Saving..." : "Save notes") {
                Task { await saveNotes() }
            }
            .disabled(isSavingNotes)
            .buttonStyle(.bordered)
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(.title3.weight(.semibold))
                Spacer()
                if canDeliver && !isTerminal {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        if isUploadingAttachment {
                            ProgressView()
                        } else {
                            Label("Add photo", systemImage: "paperclip")
                        }
                    }
                    .disabled(isUploadingAttachment)
                }
            }
            let attachments = session?.attachments ?? []
            if attachments.isEmpty {
                Text("No attachments.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(attachments) { attachment in
                    HStack {
                        Image(systemName: "doc")
                        VStack(alignment: .leading) {
                            Text(attachment.fileName ?? attachment.fileKey)
                                .font(.subheadline)
                            if let size = attachment.fileSize {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if canDeliver && !isTerminal {
                            Button(role: .destructive) {
                                Task { await removeAttachment(attachment.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QR sign-in")
                .font(.title3.weight(.semibold))
            Text("Generate a link attendees can open on their phone to sign without logging in.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                Task { await generateQR() }
            } label: {
                if isGeneratingQR {
                    ProgressView()
                } else {
                    Label(qrURLString == nil ? "Generate QR link" : "Refresh QR link", systemImage: "qrcode")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isGeneratingQR || !canManageAttendees)

            if let qrURLString, let qrImage = makeQRCode(from: qrURLString) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .frame(maxWidth: .infinity)
                Text(qrURLString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                ShareLink(item: qrURLString) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attendees & signatures")
                .font(.title3.weight(.semibold))
            let attendees = session?.attendees ?? []
            let signatures = session?.signatures ?? []
            if attendees.isEmpty && signatures.isEmpty {
                Text("No attendees or signatures yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(attendees) { attendee in
                HStack {
                    VStack(alignment: .leading) {
                        Text(attendee.displayName).font(.subheadline.weight(.semibold))
                        if let company = attendee.externalCompany ?? attendee.user?.email {
                            Text(company).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if attendee.hasSigned {
                        Label("Signed", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Unsigned")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
            ForEach(signatures.filter { sig in
                !(attendees.contains { $0.latestSignatureId == sig.id })
            }) { signature in
                HStack {
                    VStack(alignment: .leading) {
                        Text(signature.fullName ?? signature.user?.displayName ?? "Signature")
                            .font(.subheadline.weight(.semibold))
                        if let company = signature.company {
                            Text(company).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(signature.signMode ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
    }

    private var signingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign on device")
                .font(.title3.weight(.semibold))

            if canView {
                Button {
                    selfSignMode = true
                    walkInName = ""
                    walkInCompany = ""
                    showSignaturePad = true
                } label: {
                    Label("Sign for myself", systemImage: "pencil.tip")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSigning)
            }

            if canProxySign {
                Divider()
                Text("Walk-in attendee")
                    .font(.subheadline.weight(.semibold))
                TextField("Full name", text: $walkInName)
                    .textFieldStyle(.roundedBorder)
                TextField("Company", text: $walkInCompany)
                    .textFieldStyle(.roundedBorder)
                Button {
                    guard !walkInName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        statusMessage = "Enter a name for the walk-in attendee."
                        return
                    }
                    selfSignMode = false
                    showSignaturePad = true
                } label: {
                    Label("Capture walk-in signature", systemImage: "signature")
                }
                .buttonStyle(.bordered)
                .disabled(isSigning)
            }

            if let declaration = content.declarationText, !declaration.isEmpty {
                Text(declaration)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await APIClient.fetchToolboxTalkSession(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                token: token
            )
            session = fetched
            notes = fetched.notes ?? ""
            if let topics = fetched.topicsDiscussed, !topics.isEmpty {
                content = ToolboxTalkContent(
                    topics: topics,
                    highRiskActivities: fetched.highRiskActivities ?? fetched.revision?.content?.highRiskActivities,
                    ppe: fetched.revision?.content?.ppe,
                    handoutFileKeys: fetched.revision?.content?.handoutFileKeys,
                    declarationText: fetched.revision?.content?.declarationText
                )
            } else {
                content = fetched.revision?.content ?? .empty
            }
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func startSession() async {
        isStarting = true
        defer { isStarting = false }
        LocationManager.shared.requestLocationPermission()
        let location = await LocationManager.shared.getCurrentLocation()
        do {
            _ = try await APIClient.startToolboxTalkSession(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                accuracyMeters: location?.horizontalAccuracy,
                location: session?.location,
                token: token
            )
            await load(showSpinner: false)
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func completeSession() async {
        isCompleting = true
        defer { isCompleting = false }
        do {
            if canDeliver {
                _ = try await APIClient.updateToolboxTalkSession(
                    projectId: projectId,
                    talkId: talkId,
                    sessionId: sessionId,
                    notes: notes,
                    token: token
                )
            }
            _ = try await APIClient.completeToolboxTalkSession(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                token: token
            )
            await load(showSpinner: false)
            statusMessage = "Session completed."
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func saveNotes() async {
        isSavingNotes = true
        defer { isSavingNotes = false }
        do {
            _ = try await APIClient.updateToolboxTalkSession(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                notes: notes,
                token: token
            )
            statusMessage = "Notes saved."
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func generateQR() async {
        isGeneratingQR = true
        defer { isGeneratingQR = false }
        do {
            let response = try await APIClient.createToolboxTalkShareToken(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                token: token
            )
            qrURLString = ToolboxTalkWebURLs.publicSignURL(token: response.token)
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func submitSignature() async {
        guard let signatureImage,
              let data = signatureImage.pngData() ?? signatureImage.jpegData(compressionQuality: 0.85) else {
            statusMessage = "Please provide a signature."
            return
        }
        isSigning = true
        defer { isSigning = false }
        do {
            let fileKey = try await APIClient.uploadToolboxTalkFile(
                data: data,
                fileName: "tbt-signature-\(UUID().uuidString).png",
                mimeType: "image/png",
                token: token
            )
            LocationManager.shared.requestLocationPermission()
            let location = await LocationManager.shared.getCurrentLocation()
            if selfSignMode {
                _ = try await APIClient.signToolboxTalkSession(
                    projectId: projectId,
                    talkId: talkId,
                    sessionId: sessionId,
                    signatureFileKey: fileKey,
                    declarationText: content.declarationText,
                    signMode: "ON_DEVICE",
                    latitude: location?.coordinate.latitude,
                    longitude: location?.coordinate.longitude,
                    accuracyMeters: location?.horizontalAccuracy,
                    token: token
                )
            } else {
                _ = try await APIClient.signToolboxTalkSession(
                    projectId: projectId,
                    talkId: talkId,
                    sessionId: sessionId,
                    signatureFileKey: fileKey,
                    declarationText: content.declarationText,
                    signMode: "ON_DEVICE",
                    fullName: walkInName.trimmingCharacters(in: .whitespacesAndNewlines),
                    company: walkInCompany.trimmingCharacters(in: .whitespacesAndNewlines),
                    latitude: location?.coordinate.latitude,
                    longitude: location?.coordinate.longitude,
                    accuracyMeters: location?.horizontalAccuracy,
                    token: token
                )
                walkInName = ""
                walkInCompany = ""
            }
            self.signatureImage = nil
            await load(showSpinner: false)
            statusMessage = "Signature recorded."
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        isUploadingAttachment = true
        defer {
            isUploadingAttachment = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                statusMessage = "Could not read selected photo."
                return
            }
            let fileKey = try await APIClient.uploadToolboxTalkFile(
                data: data,
                fileName: "tbt-attachment-\(UUID().uuidString).jpg",
                mimeType: "image/jpeg",
                token: token
            )
            _ = try await APIClient.addToolboxTalkAttachment(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                fileKey: fileKey,
                fileName: "photo.jpg",
                fileSize: data.count,
                mimeType: "image/jpeg",
                kind: "PHOTO",
                token: token
            )
            await load(showSpinner: false)
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func removeAttachment(_ attachmentId: Int) async {
        do {
            try await APIClient.deleteToolboxTalkAttachment(
                projectId: projectId,
                talkId: talkId,
                sessionId: sessionId,
                attachmentId: attachmentId,
                token: token
            )
            await load(showSpinner: false)
        } catch {
            statusMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func makeQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
