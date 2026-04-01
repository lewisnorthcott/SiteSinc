import SwiftUI

struct ShareSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheetActivityItems: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
