//
//  CheckOutAssetView.swift
//  SiteSinc
//
//  Page to find an asset (QR scan primary, text search secondary) and check it out.
//

import SwiftUI
import UIKit

struct CheckOutAssetView: View {
    var onCheckOutSuccess: (() -> Void)?

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss

    @State private var showScanner = false
    @State private var searchText: String = ""
    @State private var searchResults: [APIClient.Asset] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var foundAsset: APIClient.Asset?
    @State private var lookupLoading = false
    @State private var actionLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var showCheckOutPhotoPicker = false
    @State private var checkOutPhotoSource: UIImagePickerController.SourceType = .camera
    @State private var assetToCheckOut: APIClient.Asset?
    @State private var showCheckOutPhotoSourceSheet = false

    private let searchDebounceInterval: UInt64 = 350_000_000

    private var token: String { sessionManager.token ?? "" }
    private var currentUserId: Int? { sessionManager.user?.id }

    private var canCheckInOut: Bool {
        (sessionManager.user?.permissions?.map { $0.name } ?? []).contains("check_inandout_assets")
    }

    private var isAvailable: Bool {
        foundAsset?.isEligibleForCheckOut ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if foundAsset == nil {
                    scanSection
                    searchSection
                }
                if let asset = foundAsset {
                    assetCard(asset)
                }
            }
            .padding()
        }
        .navigationTitle("Check out an asset")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Add photo for check-out", isPresented: $showCheckOutPhotoSourceSheet, titleVisibility: .visible) {
            Button("Take Photo") {
                checkOutPhotoSource = .camera
                showCheckOutPhotoPicker = true
            }
            Button("Choose from Library") {
                checkOutPhotoSource = .photoLibrary
                showCheckOutPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {
                assetToCheckOut = nil
            }
        } message: {
            Text("Take a new photo or choose one from your library.")
        }
        .fullScreenCover(isPresented: $showCheckOutPhotoPicker) {
            AssetPhotoPicker(
                sourceType: checkOutPhotoSource,
                onImageCaptured: { photoData in
                    showCheckOutPhotoPicker = false
                    guard let asset = assetToCheckOut else { return }
                    assetToCheckOut = nil
                    Task { await checkOut(asset, photoData: photoData) }
                },
                onDismiss: {
                    showCheckOutPhotoPicker = false
                    assetToCheckOut = nil
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRCodeScannerView(
                onScan: { str in
                    showScanner = false
                    lookupByCode(extractCode(from: str))
                },
                onCancel: {
                    showScanner = false
                }
            )
            .ignoresSafeArea()
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Scan (primary)

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan QR code")
                .font(.headline)
            Button {
                showScanner = true
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 32))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan asset QR code")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Point your camera at the asset's QR code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Search (secondary)

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or search by text")
                .font(.headline)
            TextField("Asset number, description, make, model…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, _ in
                    scheduleSearch()
                }
            if isSearching {
                HStack {
                    ProgressView()
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                if searchResults.isEmpty {
                    Text("No assets found.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(searchResults, id: \.id) { asset in
                            searchResultRow(asset)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func searchResultRow(_ asset: APIClient.Asset) -> some View {
        let eligible = asset.isEligibleForCheckOut
        return Button {
            if eligible && canCheckInOut {
                foundAsset = asset
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.assetNumber)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    if let desc = asset.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(asset.checkOutEligibilityLabel)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(eligible ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(eligible ? .green : .orange)
                    .clipShape(Capsule())
                if eligible && canCheckInOut {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!eligible || !canCheckInOut)
    }

    // MARK: - Found asset card

    private func assetCard(_ asset: APIClient.Asset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(asset.assetNumber)
                    .font(.headline)
                Spacer()
                Text(asset.checkOutEligibilityLabel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(asset.isEligibleForCheckOut ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(asset.isEligibleForCheckOut ? .green : .orange)
                    .clipShape(Capsule())
            }
            if let desc = asset.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let make = asset.make, let model = asset.model {
                Text("\(make) \(model)\(asset.year.map { " (\($0))" } ?? "")")
                    .font(.subheadline)
            }
            if isAvailable && canCheckInOut {
                Text("A photo of the asset is required when checking out.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
                Button {
                    assetToCheckOut = asset
                    showCheckOutPhotoSourceSheet = true
                } label: {
                    if actionLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Label("Take photo & check out", systemImage: "camera.badge.ellipsis")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(actionLoading || currentUserId == nil)
            }
            Button("Choose a different asset") {
                foundAsset = nil
                searchResults = []
                searchText = ""
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    /// If the scanned string is a URL with ?code=..., extract the code; otherwise return the whole string.
    private func extractCode(from str: String) -> String {
        if let url = URL(string: str),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return code
        }
        return str
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: searchDebounceInterval)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !token.isEmpty else {
            searchResults = []
            return
        }
        await MainActor.run { isSearching = true }
        defer { Task { @MainActor in isSearching = false } }
        do {
            let list = try await APIClient.fetchAssets(search: query, availability: nil, token: token)
            await MainActor.run {
                searchResults = list
            }
        } catch {
            await MainActor.run {
                searchResults = []
            }
        }
    }

    private func lookupByCode(_ code: String) {
        guard !code.isEmpty, !token.isEmpty else { return }
        lookupLoading = true
        Task {
            do {
                let asset = try await APIClient.fetchAssetByCode(code: code, token: token)
                await MainActor.run {
                    foundAsset = asset
                    lookupLoading = false
                }
            } catch let err as APIError {
                await MainActor.run {
                    lookupLoading = false
                    switch err {
                    case .invalidResponse(let status) where status == 404:
                        showError("Asset not found for this code.")
                    case .forbidden:
                        showError("You don't have permission to view assets.")
                    case .badRequest(let message):
                        showError(message)
                    default:
                        showError(err.displayMessage)
                    }
                }
            } catch {
                await MainActor.run {
                    lookupLoading = false
                    showError((error as NSError).localizedDescription)
                }
            }
        }
    }

    private func checkOut(_ asset: APIClient.Asset, photoData: Data) async {
        guard let userId = currentUserId, !token.isEmpty else { return }
        actionLoading = true
        errorMessage = nil
        defer { actionLoading = false }
        do {
            _ = try await APIClient.checkOutAsset(assetId: asset.id, userId: userId, photoData: photoData, token: token)
            await MainActor.run {
                onCheckOutSuccess?()
                dismiss()
            }
        } catch let err as APIError {
            await MainActor.run {
                showError(err.displayMessage)
            }
        } catch {
            await MainActor.run {
                showError((error as NSError).localizedDescription)
            }
        }
    }
}
