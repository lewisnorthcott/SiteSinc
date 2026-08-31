import SwiftUI

enum FormBannerKind {
    case error
    case success
    case info

    var tint: Color {
        switch self {
        case .error: return BrandChrome.danger
        case .success: return Color.green
        case .info: return BrandChrome.accent
        }
    }

    var icon: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct FormStatusBanner: View {
    let kind: FormBannerKind
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.tint)
                .padding(.top, 1)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(BrandChrome.titleColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandChrome.mutedLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(kind.tint.opacity(0.25), lineWidth: 1)
        )
    }
}

struct FormCompletionMeter: View {
    let completed: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(completed) / Double(total))
    }

    private var remaining: Int { max(0, total - completed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(remaining == 0 ? "Ready to submit" : "\(remaining) required remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(remaining == 0 ? Color.green : BrandChrome.mutedLabel)
                Spacer()
                Text("\(min(completed, total)) / \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BrandChrome.mutedLabel)
            }
            ProgressView(value: fraction)
                .tint(remaining == 0 ? .green : BrandChrome.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .formCardChrome()
    }
}

struct FormSubmitOverlay: View {
    let title: String
    let detail: String?
    let current: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(current) / Double(total))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.15)
                    .tint(BrandChrome.accent)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BrandChrome.titleColor)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(BrandChrome.mutedLabel)
                        .multilineTextAlignment(.center)
                }
                if total > 1 {
                    ProgressView(value: fraction)
                        .tint(BrandChrome.accent)
                    Text("\(min(current, total)) of \(total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BrandChrome.mutedLabel)
                }
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(BrandChrome.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandChrome.softBorder, lineWidth: BrandChrome.isMcPhillips ? 1 : 0)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct FormPhotoFieldControl: View {
    let previews: [UIImage]
    var showMarkup: Bool = false
    var onMarkup: ((Int) -> Void)? = nil
    var onRemove: (Int) -> Void
    var addLabel: String = "Add photo(s)"
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !previews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(previews.enumerated()), id: \.offset) { index, img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipped()
                                    .cornerRadius(10)

                                if showMarkup, let onMarkup {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Button {
                                                onMarkup(index)
                                            } label: {
                                                Image(systemName: "pencil.tip.crop.circle")
                                                    .font(.system(size: 18))
                                                    .foregroundStyle(.white)
                                                    .padding(5)
                                                    .background(.ultraThinMaterial, in: Circle())
                                            }
                                            .accessibilityLabel("Mark up photo")
                                            Spacer()
                                        }
                                    }
                                    .padding(4)
                                }

                                Button {
                                    onRemove(index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white)
                                        .background(Color.black.opacity(0.55), in: Circle())
                                }
                                .padding(4)
                                .accessibilityLabel("Remove photo")
                            }
                            .frame(width: 88, height: 88)
                        }
                    }
                }
            }

            Button(action: onAdd) {
                Label(addLabel, systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(BrandChrome.accent)
        }
    }
}

struct FormCardChrome: ViewModifier {
    var needsAttention: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(needsAttention ? BrandChrome.danger.opacity(0.08) : BrandChrome.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        needsAttention ? BrandChrome.danger.opacity(0.35) : BrandChrome.softBorder,
                        lineWidth: needsAttention ? 1 : (BrandChrome.isMcPhillips ? 1 : 0)
                    )
            )
            .shadow(
                color: BrandChrome.cardShadowColor,
                radius: BrandChrome.cardShadowRadius,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func formCardChrome(needsAttention: Bool = false) -> some View {
        modifier(FormCardChrome(needsAttention: needsAttention))
    }

    func formFieldSurface(needsAttention: Bool = false) -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .formCardChrome(needsAttention: needsAttention)
    }

    func formInputBackground() -> some View {
        background(BrandChrome.searchFieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func formBrandTint() -> some View {
        tint(BrandChrome.accent)
    }
}
