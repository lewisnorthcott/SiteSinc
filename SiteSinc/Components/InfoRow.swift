import SwiftUI

struct InfoRow: View {
    let icon: String?
    let label: String
    let value: String
    
    init(icon: String? = nil, label: String, value: String) {
        self.icon = icon
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(BrandChrome.mutedLabel)
                    .frame(width: 20)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(BrandChrome.mutedLabel)
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(BrandChrome.titleColor)
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
    }
}
