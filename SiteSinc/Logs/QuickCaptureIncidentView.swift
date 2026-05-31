import SwiftUI
import PhotosUI

struct QuickCaptureIncidentView: View {
    let projectId: Int
    let token: String
    let projectName: String
    let recordType: IncidentRecordType
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineLogManager.shared

    @State private var description = ""
    @State private var occurredAt = Date()
    @State private var selectedLocationId: Int?
    @State private var severityBand: SeverityBand?
    @State private var injuryInvolved = false
    @State private var bodyMapRegions: Set<String> = []
    @State private var riddorKeys: Set<String> = []
    @State private var isAnonymous = false
    @State private var selectedTypeId: Int?
    @State private var settings: LogSettings?
    @State private var selectedFiles: [URL] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var duplicateMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    TextField("Description (required)", text: $description, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("When & where") {
                    DatePicker("When did it happen?", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                    LocationSelector(
                        projectId: projectId,
                        token: sessionManager.token ?? token,
                        selectedLocationId: $selectedLocationId
                    )
                }

                Section("Incident details") {
                    SeverityPickerView(selectedBand: $severityBand)
                    Toggle("Someone was injured", isOn: $injuryInvolved)
                    if injuryInvolved {
                        BodyMapSelectorView(selectedRegions: $bodyMapRegions)
                    }
                    RiddorCheckView(selectedKeys: $riddorKeys)
                    Toggle("Report anonymously", isOn: $isAnonymous)
                }

                Section("Photos") {
                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                        Label("Add photos", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: photoPickerItems) { _, items in
                        Task { await loadPhotos(from: items) }
                    }
                }

                if let duplicateMessage {
                    Section {
                        Text(duplicateMessage)
                            .foregroundColor(.orange)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Report \(recordType.displayTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .disabled(isSubmitting || description.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { await loadSettings() }
        }
    }

    private func loadSettings() async {
        do {
            let fetched = try await APIClient.fetchLogSettings(projectId: projectId, token: sessionManager.token ?? token)
            await MainActor.run {
                settings = fetched
                selectedTypeId = fetched.types.first(where: { logTypeNameMatchesIncidentHub($0.name) })?.id
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
                try? data.write(to: url)
                await MainActor.run { selectedFiles.append(url) }
            }
        }
    }

    private func submit() async {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        duplicateMessage = nil

        let isoFormatter = ISO8601DateFormatter()
        var request = CreateLogRequest(
            title: "",
            description: description.trimmingCharacters(in: .whitespaces),
            typeId: selectedTypeId,
            tradeId: nil, statusId: nil, hazardId: nil,
            contributingConditionId: nil, contributingBehaviourId: nil,
            dueDate: nil, priorityId: nil, folderId: nil,
            isPrivate: false, assigneeId: nil, distributionUserIds: nil,
            location: nil, specification: nil, locationId: selectedLocationId,
            attachments: nil
        )
        CreateLogIncidentFields(
            recordType: recordType,
            isAnonymous: isAnonymous,
            occurredAt: isoFormatter.string(from: occurredAt),
            severityBand: severityBand,
            injuryInvolved: injuryInvolved,
            riddorReasons: Array(riddorKeys),
            bodyMap: Array(bodyMapRegions)
        ).apply(to: &request, incidentMode: true)

        do {
            if offlineManager.isOffline {
                await saveOffline(request: request)
                return
            }

            var attachments: [CreateLogRequest.AttachmentData] = []
            for url in selectedFiles {
                if let data = try? Data(contentsOf: url) {
                    let att = try await uploadData(data: data, fileName: url.lastPathComponent)
                    attachments.append(att)
                }
            }
            request.attachments = attachments.isEmpty ? nil : attachments

            let result = try await APIClient.createLog(
                projectId: projectId, logData: request,
                token: sessionManager.token ?? token
            )
            await MainActor.run {
                isSubmitting = false
                if result.duplicate {
                    duplicateMessage = result.message ?? "Report already saved"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onSuccess()
                        dismiss()
                    }
                } else {
                    onSuccess()
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func saveOffline(request: CreateLogRequest) async {
        offlineManager.queueQuickCaptureLog(
            projectId: projectId,
            projectName: projectName,
            request: request,
            localFileURLs: selectedFiles,
            token: sessionManager.token ?? token
        )
        await MainActor.run {
            isSubmitting = false
            onSuccess()
            dismiss()
        }
    }

    private func uploadData(data: Data, fileName: String) async throws -> CreateLogRequest.AttachmentData {
        guard let url = URL(string: "\(APIClient.baseURL)/upload") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let authToken = sessionManager.token ?? token
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }
        let uploadResponse = try JSONDecoder().decode(UploadedFileResponse.self, from: responseData)
        return CreateLogRequest.AttachmentData(
            fileUrl: uploadResponse.fileUrl,
            fileName: uploadResponse.fileName,
            fileType: uploadResponse.fileType
        )
    }
}
