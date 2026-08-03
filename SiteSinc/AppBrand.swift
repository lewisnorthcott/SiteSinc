import SwiftUI

/// Mirrors `@repo/brand` (`packages/brand/src/brands.ts`) for white-label builds.
/// SiteSinc is the default; McPhillips when `BRAND_MCPHILLIPS` is set.

enum AppBrandId: String {
    case sitesinc
    case mcphillips
}

struct BrandColors {
    let primary: String
    let primaryDark: String
    let link: String
    let deepest: String
    let danger: String
    let primaryHsl: String
    let ringHsl: String
    let primaryRgb: String

    var primaryColor: Color { Color(hex: primary) }
    var primaryDarkColor: Color { Color(hex: primaryDark) }
    var linkColor: Color { Color(hex: link) }
    var deepestColor: Color { Color(hex: deepest) }
    var dangerColor: Color { Color(hex: danger) }
}

struct BrandSurfaces {
    let sidebarBg: String
    let sidebarBorder: String
    let pageBg: String
    let softBg: String
    let softBorder: String
    let accentSoftBg: String
    let replyCalloutBg: String
    let replyCalloutBorder: String
    /// Semantic muted icon style (web uses Tailwind class names).
    let navIconMuted: String
    let cardBg: String

    var pageBgColor: Color { Color(hex: pageBg) }
    var softBgColor: Color { Color(hex: softBg) }
    var softBorderColor: Color { Color(hex: softBorder) }
    var accentSoftBgColor: Color { Color(hex: accentSoftBg) }
    var replyCalloutBgColor: Color { Color(hex: replyCalloutBg) }
    var replyCalloutBorderColor: Color { Color(hex: replyCalloutBorder) }
    var cardBgColor: Color { Color(hex: cardBg) }
    var sidebarBgColor: Color { Color(hex: sidebarBg) }
    var sidebarBorderColor: Color { Color(hex: sidebarBorder) }

    var navIconMutedColor: Color {
        switch navIconMuted {
        case "text-stone-500": return Color(red: 120 / 255, green: 113 / 255, blue: 108 / 255)
        default: return Color.gray
        }
    }
}

struct BrandFonts {
    enum Sans: String { case inter, figtree }
    enum Display: String { case inter, cormorant }

    let sans: Sans
    let display: Display

    /// Body / UI font design closest to the web stack.
    var bodyDesign: Font.Design {
        switch sans {
        case .inter: return .default
        case .figtree: return .rounded
        }
    }

    /// Display / heading design (Cormorant → serif).
    var displayDesign: Font.Design {
        switch display {
        case .inter: return .default
        case .cormorant: return .serif
        }
    }
}

struct BrandAssets {
    let favicon: String
    let appleTouchIcon: String
    let icon192: String
    let icon512: String
    let ogImage: String
    let logo: String
    let logoDark: String?
}

struct BrandSeo {
    let title: String
    let titleTemplate: String
    let description: String
}

struct BrandTerminology {
    let log: String
    let logs: String
    let logSettings: String
    /// e.g. "HSE Inspection" (SiteSinc) / "SHEQ Inspection" (McPhillips)
    let hseInspection: String
    let hseInspections: String
}

struct BrandFeatures {
    let energy: Bool
    let brandedNavbar: Bool
    let navbarLogo: Bool
    let showTenantIndicator: Bool
    let showNavbarNotifications: Bool
    let showNavbarMailbox: Bool
    let showLoginMarketingPanel: Bool
    let brandedLogin: Bool
    let showLoginPasskey: Bool
    let showLoginGoogle: Bool
    let colorfulNavIcons: Bool
    let compactNavLabels: Bool
    let showSidebarSectionLabels: Bool
    let editorialChat: Bool
    let projectCardGlow: Bool
    let showSidebarChatToggle: Bool
    let sidebarProjectPlacement: String
    let showProjectsStatsCards: Bool
    let pinProjectsActionsSidebar: Bool
    let showProjectsListAndMapViews: Bool
    let projectsDefaultView: String
    let showKnowledgeGraph: Bool
}

struct BrandConfig {
    let id: AppBrandId
    let name: String
    let shortName: String
    let siteUrl: String
    let fromEmail: String
    let fromName: String
    let inboundEmailDomain: String?
    let assistantName: String
    let terminology: BrandTerminology
    let fonts: BrandFonts
    let colors: BrandColors
    let surfaces: BrandSurfaces
    let assets: BrandAssets
    let seo: BrandSeo
    let features: BrandFeatures
    let loginOnly: Bool

    /// Alias for API `X-Brand-Id` (web brand `id`).
    var apiBrandId: String { id.rawValue }
    var displayName: String { name }

    var primaryHex: String { colors.primary }
    var primaryDarkHex: String { colors.primaryDark }
    var secondaryHex: String { colors.link }
    var primaryColor: Color { colors.primaryColor }
    var primaryDarkColor: Color { colors.primaryDarkColor }
    var secondaryColor: Color { colors.linkColor }

    var faceIDLoginReason: String {
        "Log in to \(name) with Face ID."
    }

    var signOutConfirmationTitle: String {
        "Sign out of \(name)?"
    }
}

enum AppBrand {
    static let sitesinc = BrandConfig(
        id: .sitesinc,
        name: "SiteSinc",
        shortName: "SiteSinc",
        siteUrl: "https://www.sitesinc.com",
        fromEmail: "notifications@sitesinc.co.uk",
        fromName: "SiteSinc",
        inboundEmailDomain: nil,
        assistantName: "Project Assistant",
        terminology: BrandTerminology(
            log: "Log",
            logs: "Logs",
            logSettings: "Log Settings",
            hseInspection: "HSE Inspection",
            hseInspections: "HSE Inspections"
        ),
        fonts: BrandFonts(sans: .inter, display: .inter),
        colors: BrandColors(
            primary: "#635bff",
            primaryDark: "#5048e5",
            link: "#635bff",
            deepest: "#3f37c9",
            danger: "#ef4444",
            primaryHsl: "243 95% 68%",
            ringHsl: "243 95% 68%",
            primaryRgb: "99, 91, 255"
        ),
        surfaces: BrandSurfaces(
            sidebarBg: "#ffffff",
            sidebarBorder: "#e5e7eb",
            pageBg: "#f9fafb",
            softBg: "#f1f1f9",
            softBorder: "#e5e5f0",
            accentSoftBg: "#f9f9ff",
            replyCalloutBg: "#eef2ff",
            replyCalloutBorder: "#c7d2fe",
            navIconMuted: "text-gray-500",
            cardBg: "#ffffff"
        ),
        assets: BrandAssets(
            favicon: "/favicon.png",
            appleTouchIcon: "/apple-touch-icon.png",
            icon192: "/android-chrome-192x192.png",
            icon512: "/android-chrome-512x512.png",
            ogImage: "/og-image.jpg",
            logo: "/favicon.svg",
            logoDark: "/favicon.svg"
        ),
        seo: BrandSeo(
            title: "SiteSinc — Construction Management Software for Drawings, RFIs & Site Logs",
            titleTemplate: "%s | SiteSinc",
            description: "AI-powered construction management software for UK teams. Manage drawings, RFIs, daily logs, and documents in one platform. 90-day free trial from £25/month."
        ),
        features: BrandFeatures(
            energy: true,
            brandedNavbar: false,
            navbarLogo: false,
            showTenantIndicator: true,
            showNavbarNotifications: true,
            showNavbarMailbox: true,
            showLoginMarketingPanel: true,
            brandedLogin: false,
            showLoginPasskey: true,
            showLoginGoogle: true,
            colorfulNavIcons: true,
            compactNavLabels: false,
            showSidebarSectionLabels: true,
            editorialChat: false,
            projectCardGlow: true,
            showSidebarChatToggle: true,
            sidebarProjectPlacement: "bottom",
            showProjectsStatsCards: true,
            pinProjectsActionsSidebar: false,
            showProjectsListAndMapViews: true,
            projectsDefaultView: "grid",
            showKnowledgeGraph: true
        ),
        loginOnly: false
    )

    static let mcphillips = BrandConfig(
        id: .mcphillips,
        name: "McPhillips",
        shortName: "McPhillips",
        siteUrl: "https://mcphillips.ai",
        fromEmail: "notifications@mcphillips.ai",
        fromName: "McPhillips",
        inboundEmailDomain: "mail.mcphillips.ai",
        assistantName: "McPhillips Assistant",
        terminology: BrandTerminology(
            log: "Site Observation",
            logs: "Site Observations",
            logSettings: "Site Observation Settings",
            hseInspection: "SHEQ Inspection",
            hseInspections: "SHEQ Inspections"
        ),
        fonts: BrandFonts(sans: .figtree, display: .cormorant),
        colors: BrandColors(
            primary: "#6f1515",
            primaryDark: "#440d0d",
            link: "#590805",
            deepest: "#260707",
            danger: "#d22630",
            primaryHsl: "0 68% 26%",
            ringHsl: "0 68% 26%",
            primaryRgb: "111, 21, 21"
        ),
        surfaces: BrandSurfaces(
            sidebarBg: "#f7f5f3",
            sidebarBorder: "#e4dcd6",
            pageBg: "#f7f5f3",
            softBg: "#f9f1f1",
            softBorder: "#e8d5d5",
            accentSoftBg: "#faf5f5",
            replyCalloutBg: "#fdf2f2",
            replyCalloutBorder: "#f5c6c6",
            navIconMuted: "text-stone-500",
            cardBg: "#fffcfa"
        ),
        assets: BrandAssets(
            favicon: "/brands/mcphillips/favicon.png",
            appleTouchIcon: "/brands/mcphillips/apple-touch-icon.png",
            icon192: "/brands/mcphillips/icon-192.png",
            icon512: "/brands/mcphillips/icon-512.png",
            ogImage: "/brands/mcphillips/og-image.svg",
            logo: "/brands/mcphillips/logo.svg",
            logoDark: "/brands/mcphillips/logo-light.svg"
        ),
        seo: BrandSeo(
            title: "McPhillips",
            titleTemplate: "%s | McPhillips",
            description: "McPhillips construction project management."
        ),
        features: BrandFeatures(
            energy: false,
            brandedNavbar: true,
            navbarLogo: true,
            showTenantIndicator: false,
            showNavbarNotifications: false,
            showNavbarMailbox: false,
            showLoginMarketingPanel: false,
            brandedLogin: true,
            showLoginPasskey: false,
            showLoginGoogle: false,
            colorfulNavIcons: false,
            compactNavLabels: true,
            showSidebarSectionLabels: false,
            editorialChat: true,
            projectCardGlow: false,
            showSidebarChatToggle: false,
            sidebarProjectPlacement: "top",
            showProjectsStatsCards: false,
            pinProjectsActionsSidebar: true,
            showProjectsListAndMapViews: false,
            projectsDefaultView: "list",
            showKnowledgeGraph: false
        ),
        loginOnly: true
    )

    /// Active brand for this binary (compile-time, like host detection on web).
    static var current: BrandConfig {
        #if BRAND_MCPHILLIPS
        return mcphillips
        #else
        return sitesinc
        #endif
    }

    // MARK: - Convenience (kept for existing call sites)

    static var displayName: String { current.name }
    static var apiBrandId: String { current.id.rawValue }
    static var primaryHex: String { current.colors.primary }
    static var primaryDarkHex: String { current.colors.primaryDark }
    static var secondaryHex: String { current.colors.link }
    static var primaryColor: Color { current.colors.primaryColor }
    static var primaryDarkColor: Color { current.colors.primaryDarkColor }
    static var secondaryColor: Color { current.colors.linkColor }

    static var faceIDLoginReason: String {
        "Log in to \(current.name) with Face ID."
    }

    static var signOutConfirmationTitle: String {
        "Sign out of \(current.name)?"
    }

    /// SiteSinc platform/support accounts (e.g. support@sitesinc.co.uk) must never
    /// surface in white-label builds — user pickers, assignee dropdowns, etc.
    private static let hiddenPlatformEmailDomains = ["sitesinc.co.uk", "sitesinc.com"]

    static func isHiddenPlatformUser(email: String?) -> Bool {
        guard current.id != .sitesinc else { return false }
        guard let domain = email?.lowercased().split(separator: "@").last else { return false }
        return hiddenPlatformEmailDomains.contains(String(domain))
    }
}

/// Login / tenant-picker wordmark that follows the active brand.
struct BrandWordmark: View {
    var body: some View {
        let brand = AppBrand.current
        let displayFont = Font.system(.title, design: brand.fonts.displayDesign).weight(.regular)

        switch brand.id {
        case .sitesinc:
            HStack(spacing: 0) {
                Text("Site")
                    .font(displayFont)
                Text("Sinc")
                    .font(displayFont)
                    .foregroundColor(brand.colors.primaryColor)
            }
        case .mcphillips:
            Image("McPhillipsLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel(brand.name)
        }
    }
}
