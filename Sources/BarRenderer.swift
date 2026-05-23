import AppKit

struct BarRenderer {
    // Square canvas — matches SF Symbol convention for menu-bar extras (HIG)
    static let imageHeight: CGFloat = 18.0
    static let imageWidth: CGFloat  = 18.0
    static let scale: CGFloat = 2.0 // Retina

    // Two horizontal bars stacked vertically (top = session, bottom = weekly)
    static let barWidth: CGFloat  = 14.0
    static let barHeight: CGFloat = 5.0
    static let barGap: CGFloat    = 3.0
    static let barCorner: CGFloat = 1.5

    // Progress colors — semantic (orange = normal, red = danger)
    static let colorOrange = NSColor(srgbRed: 0.773, green: 0.420, blue: 0.310, alpha: 1.0)  // #C56B4F
    static let colorRed    = NSColor(srgbRed: 1.00, green: 0.30, blue: 0.25, alpha: 1.0)     // #FF4D40
    // Track / unauth — bars need a visible track so both rows are always
    // readable even at 0% (otherwise an empty bar disappears entirely).
    static let colorDim    = NSColor(white: 1.0, alpha: 0.45)
    static let colorUnauth = NSColor(white: 1.0, alpha: 0.55)

    static func colorForUsage(_ pct: Double, threshold: Double) -> NSColor {
        if pct >= threshold { return colorRed }
        return colorOrange
    }

    /// Render two stacked horizontal bars — top = session, bottom = weekly.
    static func renderCircles(
        sessionPct: Double,
        weeklyPct: Double,
        invert: Bool = false,
        warningThreshold: Double
    ) -> NSImage {
        return renderImage(width: imageWidth) { ctx in
            let stackH = barHeight * 2 + barGap
            let bottomY = (imageHeight - stackH) / 2.0  // weekly (lower)
            let topY    = bottomY + barHeight + barGap  // session (upper)
            let x       = (imageWidth - barWidth) / 2.0

            drawProgressBar(ctx: ctx, x: x, y: topY,
                            pct: sessionPct, invert: invert,
                            trackColor: colorDim,
                            progressColor: colorForUsage(sessionPct, threshold: warningThreshold))
            drawProgressBar(ctx: ctx, x: x, y: bottomY,
                            pct: weeklyPct, invert: invert,
                            trackColor: colorDim,
                            progressColor: colorForUsage(weeklyPct, threshold: warningThreshold))
        }
    }

    /// Render the unauthenticated state — two empty bar tracks.
    static func renderUnauthenticated() -> NSImage {
        return renderImage(width: imageWidth) { ctx in
            let stackH = barHeight * 2 + barGap
            let bottomY = (imageHeight - stackH) / 2.0
            let topY    = bottomY + barHeight + barGap
            let x       = (imageWidth - barWidth) / 2.0

            drawProgressBar(ctx: ctx, x: x, y: topY,
                            pct: 0, invert: false,
                            trackColor: colorUnauth, progressColor: colorUnauth)
            drawProgressBar(ctx: ctx, x: x, y: bottomY,
                            pct: 0, invert: false,
                            trackColor: colorUnauth, progressColor: colorUnauth)
        }
    }

    private static func drawProgressBar(
        ctx: CGContext,
        x: CGFloat, y: CGFloat,
        pct: Double,
        invert: Bool,
        trackColor: NSColor,
        progressColor: NSColor
    ) {
        // Use NSBezierPath so each path is independent — avoids any CGContext
        // current-path state leaking between the two bar calls.
        let trackRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: barCorner, yRadius: barCorner).fill()

        let actual = max(0, min(100, pct))
        let display = invert ? 100 - actual : actual
        let fillW = barWidth * CGFloat(display / 100.0)
        if fillW > 0.5 {
            let fillRect = NSRect(x: x, y: y, width: fillW, height: barHeight)
            progressColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: barCorner, yRadius: barCorner).fill()
        }
    }

    // MARK: - Private

    /// A simple view for displaying a usage bar inside an NSMenuItem.
    class UsageBarMenuView: NSView {
        private let titleLabel: NSTextField
        private let pctLabel: NSTextField
        private var actualPct: Double = 0
        private var invert: Bool = false

        init(title: String) {
            titleLabel = NSTextField(labelWithString: title)
            pctLabel = NSTextField(labelWithString: "—")
            super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 22))

            titleLabel.font = NSFont.menuFont(ofSize: 13)
            titleLabel.textColor = .labelColor
            addSubview(titleLabel)

            pctLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            pctLabel.textColor = .secondaryLabelColor
            pctLabel.alignment = .right
            addSubview(pctLabel)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            let h = bounds.height
            titleLabel.sizeToFit()
            let labelH = titleLabel.frame.height
            let y = (h - labelH) / 2
            titleLabel.frame = NSRect(x: 14, y: y, width: 52, height: labelH)
            pctLabel.frame = NSRect(x: 160, y: y, width: 34, height: labelH)
        }

        private var warningThreshold: Double = 85

        func update(percentage: Double, invert: Bool, warningThreshold: Double) {
            self.actualPct = max(0, min(100, percentage))
            self.invert = invert
            self.warningThreshold = warningThreshold
            let shown = invert ? 100 - self.actualPct : self.actualPct
            pctLabel.stringValue = "\(Int(shown.rounded()))%"
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let barX: CGFloat = 72
            let barW: CGFloat = 82
            let barH: CGFloat = 6
            let barY = (bounds.height - barH) / 2
            let r: CGFloat = 3

            // Track
            NSColor(white: 0.5, alpha: 0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barW, height: barH),
                         xRadius: r, yRadius: r).fill()

            // Fill — color follows ACTUAL usage (severity), length follows displayed metric
            let shown = invert ? 100 - actualPct : actualPct
            let fillW = barW * CGFloat(shown / 100.0)
            if fillW > 0.5 {
                (actualPct >= warningThreshold ? colorRed : colorOrange).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: fillW, height: barH),
                             xRadius: r, yRadius: r).fill()
            }
        }
    }

    /// Create a Retina-quality NSImage using NSImage's drawingHandler, which
    /// handles backing-store scaling itself — avoids the broken interaction
    /// between cgCtx.scaleBy and NSBitmapImageRep that caused only one of
    /// multiple fills to render.
    private static func renderImage(width: CGFloat, draw: @escaping (CGContext) -> Void) -> NSImage {
        let size = NSSize(width: width, height: imageHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let cgCtx = NSGraphicsContext.current?.cgContext else { return false }
            draw(cgCtx)
            return true
        }
        image.isTemplate = false
        return image
    }
}
