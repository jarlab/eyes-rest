import SwiftUI

/// EyeRest's Frutiger Aero "glass" look: type, palette, the glass panel, the countdown's glass disc and bubbles, the
/// aqua gel button and the Settings header strip.
///
/// Every surface is built from gradients, highlights and (near-)opaque fills — no `Material`, no backdrop blur — so it
/// renders the same offscreen (`ImageRenderer`) as on screen, and looks right with or without a blur behind it.
/// - Light appearance is the reference look.
/// - Dark appearance (`dark`) tints the glass down a step so it doesn't glare on a dark desktop at night.
/// - Reduce Transparency makes everything opaque and drops the soft-light effects (bokeh, bubbles, blurred glows).
/// - Increase Contrast darkens the ink and strengthens every border.
enum Aero {
    // MARK: Type

    /// Avenir Next — Adrian Frutiger's own humanist-geometric family (1988, revised with Akira Kobayashi in 2004) and
    /// the closest relative of Frutiger that ships with macOS (/System/Library/Fonts/Avenir Next.ttc, so it resolves
    /// by PostScript name in any app). SwiftUI falls back to the system font if it is ever missing. Fixed sizes: the
    /// card is a fixed-size notification, like the system's own.
    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let face = switch weight {
        case .bold, .heavy, .black: "AvenirNext-Bold"
        case .semibold: "AvenirNext-DemiBold"
        case .medium: "AvenirNext-Medium"
        default: "AvenirNext-Regular"
        }
        return .custom(face, fixedSize: size)
    }

    // MARK: Palette

    static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    static func ink(_ increaseContrast: Bool) -> Color { rgb(increaseContrast ? 0x021529 : 0x0A2B4C) }
    static func inkSoft(_ increaseContrast: Bool) -> Color { rgb(increaseContrast ? 0x06223F : 0x1B4368) }
    static func edge(_ increaseContrast: Bool) -> Color { increaseContrast ? rgb(0x0A3A6B) : rgb(0x2C79B8, 0.55) }

    // MARK: Metrics

    static let cardWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 18

    /// Transparent margin around the card that holds its soft shadow: the view (and so the panel) is this much larger
    /// than the visible card.
    ///
    /// Placing the panel (AppKit, y up) with the card 16 pt from the right edge and 12 pt under the menu bar:
    ///
    ///     let v = screen.visibleFrame, size = hostingView.fittingSize        // card + margin
    ///     panel.setFrame(NSRect(x: v.maxX - 16 + shadowMargin.trailing - size.width,   // maxX = v.maxX - 16 + 20
    ///                           y: v.maxY - 12 + shadowMargin.top - size.height,       // top  = v.maxY - 12 + 12
    ///                           width: size.width, height: size.height), display: false)
    ///     panel.hasShadow = false   // the view draws its own shadow; a window shadow would outline the margin
    ///
    /// The top margin (12) also leaves room for the float-in: animate the SwiftUI content from `offset(y: -8)` to 0
    /// (with the fade) instead of moving the window, so the panel never slides up into the menu bar.
    static let shadowMargin = EdgeInsets(top: 12, leading: 20, bottom: 26, trailing: 20)
}

extension View {
    /// The engraved white line under dark text on glass — the Aqua-era "etched" look.
    func etched(_ enabled: Bool = true, opacity: Double = 0.75) -> some View {
        shadow(color: .white.opacity(enabled ? opacity : 0), radius: 0, y: 1)
    }
}

// MARK: - Glass panel

/// Frosted sky-blue glass: a white-to-sky body, lime and aqua light rising from the bottom corners, a little bokeh
/// along the bottom edge, a bowed specular sheen across the top, a luminous inner edge and a crisp outer hairline,
/// over a soft shadow that stays outside the glass.
struct AeroGlassPanel: View {
    var cornerRadius: CGFloat = Aero.cornerRadius
    /// Where the sheen's lower edge runs; the default fits the card's layout.
    var sheenShape = AeroSheen()
    var dark = false
    var reduceTransparency = false
    var increaseContrast = false
    var castsShadow = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Nearly opaque on purpose: without a backdrop blur, sharp content behind (code, text) would show through as
        // faint stripes at any lower opacity. The glass reads from its gradients and highlights, not see-through.
        let alpha = reduceTransparency ? 1 : 0.985
        let tint: [UInt32] = dark ? [0xE3F1FB, 0xC8E3F6, 0x96CAEC] : [0xFBFEFF, 0xDDF1FD, 0xA9DBF7]
        ZStack {
            // Body: near-white at the top, deepening to clear sky blue at the bottom.
            shape.fill(LinearGradient(stops: zip(tint, [0, 0.5, 1]).map { .init(color: Aero.rgb($0, alpha), location: $1) },
                                      startPoint: .top, endPoint: .bottom))

            // Fresh light rising from below: lime at the leading corner, aqua at the trailing one.
            Rectangle().fill(RadialGradient(colors: [Aero.rgb(0xB4EC7E, dark ? 0.45 : 0.55), .clear],
                                            center: UnitPoint(x: 0.08, y: 1.15), startRadius: 0, endRadius: 170))
            Rectangle().fill(RadialGradient(colors: [Aero.rgb(0x7DE3F4, dark ? 0.45 : 0.55), .clear],
                                            center: UnitPoint(x: 0.85, y: 1.2), startRadius: 0, endRadius: 190))
            if !reduceTransparency { AeroBokeh(strength: dark ? 0.5 : 1) }
            sheen
        }
        .clipShape(shape)
        .overlay {
            // Luminous inner edge: a soft glow plus a bright line just inside a crisp outer hairline.
            if !reduceTransparency {
                shape.inset(by: 1).stroke(.white.opacity(dark ? 0.45 : 0.7), lineWidth: 5).blur(radius: 3)
                    .clipShape(shape)
            }
            shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.55)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            shape.strokeBorder(Aero.edge(increaseContrast), lineWidth: increaseContrast ? 1.5 : 1)
        }
        .background { if castsShadow { AeroOuterShadow(cornerRadius: cornerRadius) } }
    }

    /// The curved specular sheen across the top, with a faint glint along its lower edge that fades in only right of
    /// the countdown disc. Under Reduce Transparency it is an opaque gradient with no glint. In Dark Mode the sheen is
    /// sky-tinted rather than white, so the top of the card stays a step below paper-white.
    @ViewBuilder private var sheen: some View {
        let end = UnitPoint(x: 0.5, y: 0.62)
        if reduceTransparency {
            // Ends on the body's own colour at that height, so the opaque version has no step at all.
            sheenShape.fill(LinearGradient(colors: [Aero.rgb(dark ? 0xEEF7FD : 0xFFFFFF),
                                                     Aero.rgb(dark ? 0xCFE6F7 : 0xD7EEFC)],
                                            startPoint: .top, endPoint: end))
        } else {
            let gloss = Aero.rgb(dark ? 0xEEF7FD : 0xFFFFFF)
            sheenShape.fill(LinearGradient(colors: [gloss.opacity(dark ? 0.8 : 0.95), gloss.opacity(dark ? 0.3 : 0.35)],
                                            startPoint: .top, endPoint: end))
            sheenShape.edge.stroke(LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0.3),
                .init(color: .white.opacity(dark ? 0.4 : 0.6), location: 0.68),
                .init(color: .white.opacity(0), location: 1),
            ], startPoint: .leading, endPoint: .trailing), lineWidth: 1)
        }
    }
}

/// The card's drop shadow, masked to the outside of the card so it never darkens the glass.
private struct AeroOuterShadow: View {
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(Aero.rgb(0x0B3A66))
            .shadow(color: Aero.rgb(0x0B3A66, 0.30), radius: 11, y: 6)
            .shadow(color: Aero.rgb(0x0B3A66, 0.18), radius: 1.5, y: 1)
            .mask {
                GeometryReader { proxy in
                    let card = CGRect(origin: .zero, size: proxy.size)
                    Path { path in
                        path.addRect(card.insetBy(dx: -60, dy: -60))
                        path.addRoundedRect(in: card, cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                                            style: .continuous)
                    }
                    .fill(style: FillStyle(eoFill: true))
                }
            }
    }
}

/// The glass's top highlight. Its lower edge is a bowed arc: it leaves the trailing side at `trailing` of the height,
/// stays just above the Done button, sags to its lowest point in the open glass below the message (`sag`), and comes
/// back up to `leading` behind the countdown disc — so it reads as the rim of a curved reflection, not a straight seam
/// across the card. With `edgeOnly`, the shape is just that arc, for the glint line along it.
struct AeroSheen: Shape {
    var leading: CGFloat = 0.64
    var trailing: CGFloat = 0.52
    var sag: CGFloat = 0.8
    var edgeOnly = false

    var edge: AeroSheen { AeroSheen(leading: leading, trailing: trailing, sag: sag, edgeOnly: true) }

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        return Path { path in
            if edgeOnly {
                path.move(to: point(1, trailing))
            } else {
                path.move(to: point(0, 0))
                path.addLine(to: point(1, 0))
                path.addLine(to: point(1, trailing))
            }
            path.addCurve(to: point(0, leading), control1: point(0.78, trailing + 0.03), control2: point(0.42, sag))
            if !edgeOnly { path.closeSubpath() }
        }
    }
}

/// Soft out-of-focus light caught along the bottom edge of the glass, well away from the text.
private struct AeroBokeh: View {
    var strength: Double
    /// (x, y) as fractions of the panel, radius in points, peak opacity.
    private static let lights: [(x: CGFloat, y: CGFloat, r: CGFloat, a: Double)] = [
        (0.08, 0.98, 26, 0.30), (0.43, 1.03, 30, 0.22), (0.71, 1.04, 22, 0.25), (0.995, 0.96, 22, 0.25),
    ]

    var body: some View {
        Canvas { context, size in
            for light in Self.lights {
                let center = CGPoint(x: size.width * light.x, y: size.height * light.y)
                let a = light.a * strength
                context.fill(Path(ellipseIn: CGRect(x: center.x - light.r, y: center.y - light.r,
                                                    width: light.r * 2, height: light.r * 2)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(a), .white.opacity(a * 0.5), .clear]),
                                                   center: center, startRadius: 0, endRadius: light.r))
            }
        }
        .allowsHitTesting(false)
    }
}

/// A small soap bubble: a clear body with an aqua rim and a bright highlight at its upper left. The aqua rim keeps it
/// visible on near-white glass.
struct AeroBubble: View {
    var diameter: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.15), Aero.rgb(0x8ADAF7, 0.4)],
                                 center: .center, startRadius: 0, endRadius: diameter / 2))
            .overlay(Circle().strokeBorder(Aero.rgb(0x2B8FCF, 0.6), lineWidth: max(0.6, diameter * 0.1)))
            .overlay(alignment: .topLeading) {
                Circle().fill(.white)
                    .frame(width: diameter * 0.32, height: diameter * 0.32)
                    .offset(x: diameter * 0.2, y: diameter * 0.17)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - Glass disc (countdown)

/// A convex glass disc: pale sky body, lighter caustic glow at the bottom, a specular cap at the top, hairline rim.
struct AeroGlassDisc: View {
    var dark = false
    var increaseContrast = false

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(LinearGradient(colors: dark ? [Aero.rgb(0xE8F4FC), Aero.rgb(0xB6DCF3)]
                                                          : [Aero.rgb(0xF4FBFF), Aero.rgb(0xC0E5FA)],
                                             startPoint: .top, endPoint: .bottom))
                Circle().fill(RadialGradient(colors: [.white.opacity(dark ? 0.7 : 0.85), .clear],
                                             center: UnitPoint(x: 0.5, y: 0.95), startRadius: 0, endRadius: d * 0.45))
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(dark ? 0.8 : 1), .white.opacity(0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.78, height: d * 0.46)
                    .offset(y: -d * 0.24)
                Circle().strokeBorder(Aero.edge(increaseContrast), lineWidth: increaseContrast ? 1.5 : 1)
                Circle().inset(by: 1).strokeBorder(.white.opacity(0.8), lineWidth: 1)
            }
            .frame(width: d, height: d)
            .shadow(color: Aero.rgb(0x0B3A66, 0.22), radius: 3, y: 1.5)
        }
    }
}

// MARK: - Gel button

/// An aqua gel pill in the Aqua tradition: bright aqua body lit from below, a glossy cap across the top half, a dark
/// hairline and a soft contact shadow, with a navy label (legible over the gloss). Pressing dims the gloss and deepens
/// the gel a little, and the label with it, so the label stays well above 4.5:1 (measured: 5.1 at rest, pressed ≥ 5).
struct AeroGelButtonStyle: ButtonStyle {
    var increaseContrast = false

    func makeBody(configuration: Configuration) -> some View {
        AeroGelPill(pressed: configuration.isPressed, increaseContrast: increaseContrast) { configuration.label }
    }
}

/// The gel pill with its label, for the button style (and for rendering the pressed state directly).
struct AeroGelPill<Label: View>: View {
    var pressed = false
    var increaseContrast = false
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(Aero.font(13, .semibold))
            .foregroundStyle(Aero.rgb(increaseContrast || pressed ? 0x021529 : 0x05203D))
            .etched(!increaseContrast && !pressed, opacity: 0.35)
            .padding(.horizontal, 20)
            .frame(minWidth: 78, minHeight: 26)
            .background { AeroGel(pressed: pressed, increaseContrast: increaseContrast) }
            .contentShape(Capsule())
    }
}

private struct AeroGel: View {
    var pressed: Bool
    var increaseContrast: Bool

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            ZStack(alignment: .top) {
                Capsule().fill(LinearGradient(stops: [
                    .init(color: Aero.rgb(0x74D3F7), location: 0),
                    .init(color: Aero.rgb(0x2EA5EA), location: 0.5),
                    .init(color: Aero.rgb(0x279BE3), location: 0.62),
                    .init(color: Aero.rgb(0x7EE2FB), location: 1),
                ], startPoint: .top, endPoint: .bottom))
                Capsule().fill(RadialGradient(colors: [Aero.rgb(0xD2FAFF, 0.8), .clear],
                                              center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: h * 0.75))
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(pressed ? 0.75 : 0.95), .white.opacity(0.3)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.46)
                    .padding(.horizontal, h * 0.2)
                    .padding(.top, 1.5)
                Capsule().strokeBorder(increaseContrast ? Aero.rgb(0x06305E) : Aero.rgb(0x0E5FA6, 0.85),
                                       lineWidth: increaseContrast ? 1.5 : 1)
            }
            .overlay { if pressed { Capsule().fill(Aero.rgb(0x0A4A8A, 0.1)) } }
            .shadow(color: Aero.rgb(0x0B3A66, 0.35), radius: 1.5, y: 1)
        }
    }
}

// MARK: - Settings header

/// The Settings window's header strip: the app icon and name on a band of the card's glass, so the window and the
/// reminder read as one app. Sized for a 440–480 pt window (it fills the width it is given, 72 pt tall).
/// In the app: `AeroHeaderStrip(icon: Image(nsImage: NSApp.applicationIconImage), …)`, passing the environment's
/// `accessibilityReduceTransparency` and `colorSchemeContrast == .increased`; `dark` is `colorScheme == .dark`.
struct AeroHeaderStrip: View {
    var icon: Image
    var title = "EyeRest"
    var subtitle: String
    var dark = false
    var reduceTransparency = false
    var increaseContrast = false

    var body: some View {
        HStack(spacing: 12) {
            icon.resizable().interpolation(.high).frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Aero.font(18, .semibold))
                    .foregroundStyle(Aero.ink(increaseContrast))
                    .etched(!increaseContrast)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(Aero.font(12.5, .medium))
                    .foregroundStyle(Aero.inkSoft(increaseContrast))
                    .etched(!increaseContrast)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 72)
        .background(AeroGlassPanel(cornerRadius: 12, sheenShape: AeroSheen(leading: 0.86, trailing: 0.8, sag: 0.97),
                                   dark: dark, reduceTransparency: reduceTransparency,
                                   increaseContrast: increaseContrast, castsShadow: false))
        .accessibilityElement(children: .combine)
    }
}
