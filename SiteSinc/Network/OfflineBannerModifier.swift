import SwiftUI

struct OfflineBannerModifier: ViewModifier {
    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
//            if !networkStatusManager.isNetworkAvailable {
//                VStack {
//                    HStack {
//                        Image(systemName: "wifi.slash")
//                            .foregroundColor(.orange)
//                            .font(.system(size: 16))
//                        Text("No Internet Access")
//                            .font(.caption)
//                            .foregroundColor(.orange)
//                        Spacer()
//                    }
//                    .padding(.vertical, 8)
//                    .padding(.horizontal)
//                    .background(Color.orange.opacity(0.1))
//                    .cornerRadius(8)
//                    .padding(.horizontal, 16)
//                    .padding(.top, 8)
//                    Spacer()
//                }
//            }
        }
    }
}

extension View {
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
