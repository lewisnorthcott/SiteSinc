import SwiftUI

public struct CloudProgressIcon: View {
    public let isLoading: Bool
    public let progress: Double // 0.0 - 1.0
    public let baseIcon: String
    public let tint: Color

    @State private var rotation: Double = 0

    public init(isLoading: Bool, progress: Double, baseIcon: String, tint: Color) {
        self.isLoading = isLoading
        self.progress = progress
        self.baseIcon = baseIcon
        self.tint = tint
    }

    public var body: some View {
        let clamped = max(0.01, min(0.999, progress))
        let ringSize: CGFloat = 30
        let line: CGFloat = 2.5
        ZStack {
            if isLoading {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: line)
                    .frame(width: ringSize, height: ringSize)
            }
            if isLoading {
                Circle()
                    .trim(from: 0, to: CGFloat(clamped))
                    .stroke(style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .foregroundColor(tint)
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(rotation - 90))
                    .animation(.easeInOut(duration: 0.25), value: progress)
                    .animation(isLoading ? .linear(duration: 1.4).repeatForever(autoreverses: false) : .default, value: rotation)
                    .onAppear { if isLoading { rotation = 360 } }
            }
            Image(systemName: baseIcon)
                .foregroundColor(tint)
                .font(.system(size: 15))
        }
    }
}


