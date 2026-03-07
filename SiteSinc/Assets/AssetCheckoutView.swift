//
//  AssetCheckoutView.swift
//  SiteSinc
//
//  Assets screen: dynamic search to check out an asset; list of my checked-out assets to check in.
//

import SwiftUI
import UIKit

struct AssetCheckoutView: View {
    /// Optional pre-filled code (e.g. from deep link or QR).
    var initialCode: String? = nil

    @EnvironmentObject var sessionManager: SessionManager

    @State private var myCheckedOutAssets: [APIClient.Asset] = []
    @State private var isLoadingMyAssets = false
    @State private var selectedForCheckIn: APIClient.Asset?
    @State private var actionLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var showCheckInPhotoPicker = false
    @State private var checkInPhotoSource: UIImagePickerController.SourceType = .camera
    @State private var showCheckInPhotoSourceSheet = false
    /// Asset we're checking in – captured when opening photo flow so the picker callback has a valid reference.
    @State private var assetPendingCheckIn: APIClient.Asset?

    private var token: String { sessionManager.token ?? "" }
    private var currentUserId: Int? { sessionManager.user?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                checkOutSection
                myCheckedOutSection
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Assets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadMyCheckedOutAssets()
            AssetEventManager.shared.onAssetsChanged = loadMyCheckedOutAssets
            if !token.isEmpty {
                AssetEventManager.shared.connect(token: token)
            }
        }
        .onDisappear {
            AssetEventManager.shared.onAssetsChanged = nil
            AssetEventManager.shared.disconnect()
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
        .sheet(item: $selectedForCheckIn) { asset in
            assetCheckInSheet(asset, onCheckInTapped: {
                assetPendingCheckIn = asset
                showCheckInPhotoSourceSheet = true
            })
        }
        .confirmationDialog("Add photo for check-in", isPresented: $showCheckInPhotoSourceSheet, titleVisibility: .visible) {
            Button("Take Photo") {
                checkInPhotoSource = .camera
                showCheckInPhotoPicker = true
            }
            Button("Choose from Library") {
                checkInPhotoSource = .photoLibrary
                showCheckInPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Take a new photo or choose one from your library.")
        }
        .fullScreenCover(isPresented: $showCheckInPhotoPicker) {
            AssetPhotoPicker(
                sourceType: checkInPhotoSource,
                onImageCaptured: { photoData in
                    showCheckInPhotoPicker = false
                    let assetToCheckIn = assetPendingCheckIn
                    assetPendingCheckIn = nil
                    guard let assetToCheckIn else { return }
                    Task { await checkIn(assetToCheckIn, photoData: photoData) }
                },
                onDismiss: {
                    showCheckInPhotoPicker = false
                    assetPendingCheckIn = nil
                }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Check out an asset (top) – button to dedicated page

    private var checkOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CheckOutAssetView(onCheckOutSuccess: loadMyCheckedOutAssets)
                    .environmentObject(sessionManager)
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "#6366F1"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check out an asset")
                            .font(.headline)
                        Text("Scan a QR code or search by text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - My checked-out assets (bottom)

    private var myCheckedOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My checked-out assets")
                .font(.headline)
            if isLoadingMyAssets {
                HStack {
                    ProgressView()
                    Text("Loading…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if myCheckedOutAssets.isEmpty {
                Text("You have no assets checked out.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(myCheckedOutAssets, id: \.id) { asset in
                        myAssetRow(asset)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func myAssetRow(_ asset: APIClient.Asset) -> some View {
        Button {
            selectedForCheckIn = asset
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
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func assetCheckInSheet(_ asset: APIClient.Asset, onCheckInTapped: @escaping () -> Void) -> some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text(asset.assetNumber)
                    .font(.title2)
                    .fontWeight(.semibold)
                if let desc = asset.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let make = asset.make, let model = asset.model {
                    Text("\(make) \(model)\(asset.year.map { " (\($0))" } ?? "")")
                        .font(.subheadline)
                }
                Text("A photo of the asset is required when checking in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer().frame(height: 8)
                Button {
                    onCheckInTapped()
                } label: {
                    if actionLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Label("Take photo & check in", systemImage: "camera.badge.ellipsis")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(actionLoading)
            }
            .padding()
            .navigationTitle("Check in asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedForCheckIn = nil
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func loadMyCheckedOutAssets() {
        guard let uid = currentUserId, !token.isEmpty else {
            myCheckedOutAssets = []
            return
        }
        isLoadingMyAssets = true
        Task {
            do {
                let list = try await APIClient.fetchAssets(search: nil, availability: "in_use", token: token)
                await MainActor.run {
                    myCheckedOutAssets = list.filter { $0.assignedToUserId == uid }
                    isLoadingMyAssets = false
                }
            } catch {
                await MainActor.run {
                    myCheckedOutAssets = []
                    isLoadingMyAssets = false
                }
            }
        }
    }

    private func checkIn(_ asset: APIClient.Asset, photoData: Data) async {
        guard !token.isEmpty else { return }
        actionLoading = true
        errorMessage = nil
        defer { actionLoading = false }
        do {
            _ = try await APIClient.checkInAsset(assetId: asset.id, photoData: photoData, token: token)
            await MainActor.run {
                selectedForCheckIn = nil
                loadMyCheckedOutAssets()
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

// Allow binding sheet to optional Asset by Id
extension APIClient.Asset: Identifiable {}
