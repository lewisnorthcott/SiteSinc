import SwiftUI
import UIKit

/// Shared visual language for the AI chat screens, matching the web app's
/// project assistant (purple/indigo gradient branding, gradient bot avatar,
/// asymmetric message bubbles).
enum ChatTheme {
    static let purple = Color(hex: "8B5CF6")
    static let purpleDark = Color(hex: "6D45D6")

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Gradient "Sparkles" avatar with an online-status dot, used in the chat header.
struct ChatBrandAvatar: View {
    var size: CGFloat = 36
    var showOnlineDot: Bool = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(ChatTheme.brandGradient)
                .frame(width: size, height: size)
                .shadow(color: ChatTheme.purple.opacity(0.35), radius: 8, x: 0, y: 4)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundColor(.white)
                )

            if showOnlineDot {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
    }
}

/// Small gradient square avatar shown next to assistant message bubbles.
struct ChatBotAvatar: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(ChatTheme.brandGradient)
            .frame(width: size, height: size)
            .shadow(color: ChatTheme.purple.opacity(0.25), radius: 4, x: 0, y: 2)
            .overlay(
                Image(systemName: "brain.head.profile")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundColor(.white)
            )
    }
}

/// "Thinking…" bouncing-dots indicator shown while awaiting/streaming a reply.
struct ChatThinkingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(ChatTheme.purple.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .offset(y: animate ? -3 : 0)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: animate
                        )
                }
            }
            Text("Thinking…")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .onAppear { animate = true }
    }
}

/// Rounded chat-bubble shape with one flattened corner, matching the web app's
/// `rounded-br-sm` / `rounded-bl-sm` message bubbles.
struct ChatBubbleShape: Shape {
    var radius: CGFloat = 18
    var flattenedCorner: UIRectCorner

    func path(in rect: CGRect) -> Path {
        var corners: UIRectCorner = .allCorners
        corners.remove(flattenedCorner)
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        // Flattened corner gets a small radius rather than a hard 0, matching the web's `-sm`.
        let smallPath = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: flattenedCorner,
            cornerRadii: CGSize(width: 4, height: 4)
        )
        path.append(smallPath)
        return Path(path.cgPath)
    }
}

/// Pill-style chip used for source/citation references beneath assistant messages.
struct ChatSourcePillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .foregroundColor(.primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
    }
}

extension View {
    func chatSourcePillStyle() -> some View {
        modifier(ChatSourcePillStyle())
    }
}

func iconName(forSourceType sourceType: String) -> String {
    switch sourceType {
    case "drawing", "drawing_live":
        return "square.on.square"
    case "document", "document_live":
        return "doc.text.fill"
    case "rfi", "rfi_live":
        return "questionmark.circle.fill"
    case "form", "form_live":
        return "list.clipboard.fill"
    case "log", "log_live":
        return "exclamationmark.triangle.fill"
    default:
        return "doc.fill"
    }
}
