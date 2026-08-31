import SwiftUI

/// Shared list/tile chrome that follows the active brand.
/// SiteSinc keeps the existing blue/white card look; McPhillips uses the
/// quieter editorial surfaces from `AppBrand` (warm page, hairline cards, burgundy).
enum BrandChrome {
    static var brand: BrandConfig { AppBrand.current }
    static var isMcPhillips: Bool { brand.id == .mcphillips }

    /// Product accent used for CTAs, focus rings, progress tints, and selected states.
    static var accent: Color {
        switch brand.id {
        case .sitesinc: return Color(hex: "#3B82F6")
        case .mcphillips: return brand.primaryColor
        }
    }

    static var danger: Color { brand.colors.dangerColor }

    static var titleColor: Color {
        isMcPhillips ? brand.colors.deepestColor : .primary
    }

    static var pageBackground: Color {
        switch brand.id {
        case .sitesinc: return Color(hex: "#F7F9FC")
        case .mcphillips: return brand.surfaces.pageBgColor
        }
    }

    /// System-grouped equivalent for screens that previously used `systemGroupedBackground`.
    static var groupedBackground: Color {
        switch brand.id {
        case .sitesinc: return Color(.systemGroupedBackground)
        case .mcphillips: return brand.surfaces.pageBgColor
        }
    }

    static var cardBackground: Color {
        switch brand.id {
        case .sitesinc: return Color(.systemBackground)
        case .mcphillips: return brand.surfaces.cardBgColor
        }
    }

    /// White hex cards (Drawings/Documents) vs brand card.
    static var solidCardBackground: Color {
        switch brand.id {
        case .sitesinc: return Color(hex: "#FFFFFF")
        case .mcphillips: return brand.surfaces.cardBgColor
        }
    }

    static var softBorder: Color {
        switch brand.id {
        case .sitesinc: return Color.clear
        case .mcphillips: return brand.surfaces.softBorderColor
        }
    }

    static var mutedLabel: Color {
        switch brand.id {
        case .sitesinc: return Color.secondary
        case .mcphillips: return brand.surfaces.navIconMutedColor
        }
    }

    static var searchFieldFill: Color {
        switch brand.id {
        case .sitesinc: return Color(hex: "#EFF2F7")
        case .mcphillips: return brand.surfaces.softBgColor
        }
    }

    /// Unselected chips, icon wells, count badges.
    static var subtleFill: Color {
        switch brand.id {
        case .sitesinc: return Color(.systemGray6)
        case .mcphillips: return brand.surfaces.softBgColor
        }
    }

    static var secondaryCardBackground: Color {
        switch brand.id {
        case .sitesinc: return Color(.secondarySystemBackground)
        case .mcphillips: return brand.surfaces.cardBgColor
        }
    }

    static var cardShadowColor: Color {
        isMcPhillips ? .clear : Color.black.opacity(0.06)
    }

    static var cardShadowRadius: CGFloat { isMcPhillips ? 0 : 4 }
    static var lightShadowColor: Color {
        isMcPhillips ? .clear : Color.black.opacity(0.05)
    }

    static var bodyDesign: Font.Design { brand.fonts.bodyDesign }
    static var displayDesign: Font.Design { brand.fonts.displayDesign }

    static var selectedCardFill: Color {
        accent.opacity(isMcPhillips ? 0.08 : 0.12)
    }

    static var selectedCardBorder: Color {
        accent.opacity(isMcPhillips ? 0.45 : 0.65)
    }
}

// MARK: - View modifiers

struct BrandPageBackground: ViewModifier {
    var useGrouped: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                (useGrouped ? BrandChrome.groupedBackground : BrandChrome.pageBackground)
                    .ignoresSafeArea()
            )
    }
}

struct BrandCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12
    var isSelected: Bool = false
    var elevate: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? BrandChrome.selectedCardFill : BrandChrome.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? BrandChrome.selectedCardBorder : BrandChrome.softBorder,
                        lineWidth: isSelected ? 1.5 : (BrandChrome.isMcPhillips ? 1 : 0)
                    )
            )
            .shadow(
                color: elevate ? (isSelected ? BrandChrome.accent.opacity(BrandChrome.isMcPhillips ? 0 : 0.18) : BrandChrome.cardShadowColor) : .clear,
                radius: elevate ? (isSelected && !BrandChrome.isMcPhillips ? 6 : BrandChrome.cardShadowRadius) : 0,
                x: 0,
                y: elevate ? 2 : 0
            )
    }
}

struct BrandSolidCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12
    var isSelected: Bool = false
    var isHighlighted: Bool = false

    func body(content: Content) -> some View {
        let fill: Color = {
            if isSelected { return BrandChrome.isMcPhillips ? BrandChrome.selectedCardFill : Color(hex: "#DBEAFE") }
            if isHighlighted { return BrandChrome.accent.opacity(0.03) }
            return BrandChrome.solidCardBackground
        }()
        let stroke: Color = {
            if isSelected { return BrandChrome.selectedCardBorder }
            if isHighlighted { return BrandChrome.accent.opacity(0.3) }
            return BrandChrome.softBorder
        }()
        let lineWidth: CGFloat = {
            if isSelected { return 1.5 }
            if isHighlighted { return 1 }
            return BrandChrome.isMcPhillips ? 1 : 0
        }()

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: lineWidth)
            )
            .shadow(
                color: isSelected
                    ? BrandChrome.accent.opacity(BrandChrome.isMcPhillips ? 0 : 0.18)
                    : BrandChrome.cardShadowColor,
                radius: isSelected && !BrandChrome.isMcPhillips ? 6 : BrandChrome.cardShadowRadius,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func brandPageBackground(useGrouped: Bool = false) -> some View {
        modifier(BrandPageBackground(useGrouped: useGrouped))
    }

    func brandCard(cornerRadius: CGFloat = 12, isSelected: Bool = false, elevate: Bool = true) -> some View {
        modifier(BrandCardStyle(cornerRadius: cornerRadius, isSelected: isSelected, elevate: elevate))
    }

    func brandSolidCard(cornerRadius: CGFloat = 12, isSelected: Bool = false, isHighlighted: Bool = false) -> some View {
        modifier(BrandSolidCardStyle(cornerRadius: cornerRadius, isSelected: isSelected, isHighlighted: isHighlighted))
    }

    /// Hides default List background and paints brand page colour behind it.
    func brandListChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(BrandChrome.groupedBackground.ignoresSafeArea())
    }
}

/// Tracked uppercase section label used on McPhillips list screens.
struct BrandSectionLabel: View {
    let title: String

    var body: some View {
        Text(BrandChrome.isMcPhillips ? title.uppercased() : title)
            .font(
                BrandChrome.isMcPhillips
                    ? .system(size: 11, weight: .semibold, design: BrandChrome.bodyDesign)
                    : .headline.weight(.semibold)
            )
            .foregroundColor(BrandChrome.isMcPhillips ? BrandChrome.mutedLabel : .primary)
            .tracking(BrandChrome.isMcPhillips ? 1.0 : 0)
    }
}
