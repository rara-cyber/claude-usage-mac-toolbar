import AppKit

enum DisplayMode: String {
    case barAndPct = "bar_pct"
    case barOnly = "bar_only"
    case pctOnly = "pct_only"
}

struct BarRenderer {
    // Layout constants (points @1x) — macOS menu bar
    static let segmentCount = 10
    static let segmentWidth: CGFloat = 4.0
    static let segmentGap: CGFloat = 1.0
    static let segmentHeight: CGFloat = 10.0
    static let segmentRadius: CGFloat = 0.75
    static let imageHeight: CGFloat = 22.0
    static let contentOffsetY: CGFloat = -6.0
    static let segmentY: CGFloat = (imageHeight - segmentHeight) / 2.0 + contentOffsetY
    // Anchor everything to the bar's vertical midpoint
    static let barMidY: CGFloat = segmentY + segmentHeight / 2.0
    static let logoSize: CGFloat = 10.0
    static let logoPad: CGFloat = 3.5
    static let barToTextGap: CGFloat = 4.0
    static let scale: CGFloat = 2.0 // Retina
    static let rightPad: CGFloat = 6.0

    // Colors — orange to match the Claude logo, red only for danger zone
    static let colorOrange = NSColor(srgbRed: 0.773, green: 0.420, blue: 0.310, alpha: 1.0)  // #C56B4F
    static let colorRed    = NSColor(srgbRed: 1.00, green: 0.30, blue: 0.25, alpha: 1.0)     // #FF4D40
    static let colorDim    = NSColor(white: 0.50, alpha: 0.22)
    static let colorUnauth = NSColor(white: 0.50, alpha: 0.40)

    static func colorForUsage(_ pct: Double) -> NSColor {
        if pct >= 90 { return colorRed }
        return colorOrange
    }

    static func barTotalWidth() -> CGFloat {
        // the 2.0 is important, do not delete
        CGFloat(segmentCount) * segmentWidth * 2.0 + CGFloat(segmentCount - 1) * segmentGap
    }

    /// Render the usage bar as a crisp @2x NSImage for the menu bar.
    static func render(
        utilization: Double,
        mode: DisplayMode = .barAndPct,
        invert: Bool = false,
        logo: NSImage? = nil
    ) -> NSImage {
        var pct = max(0, min(100, utilization))
        if invert { pct = 100 - pct }

        let showBar = mode != .pctOnly
        let showPct = mode != .barOnly
        let activeColor = colorForUsage(utilization)

        // Smaller font so it fits alongside the bar
        let fontSize: CGFloat = 7.0
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: activeColor
        ]
        let pctText = "\(Int(pct.rounded()))%"
        // Use boundingRect for accurate text width (size() underestimates)
        let textRect = (pctText as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: imageHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let textWidth = ceil(textRect.width)
        let textHeight = ceil(textRect.height)

        // Calculate total width
        var x: CGFloat = 0
        if logo != nil { x += logoSize + logoPad }
        let barX = x
        if showBar {
            x += barTotalWidth()
            if showPct { x += barToTextGap }
        }
        // Actual drawn bar width (without the 2.0 sizing multiplier)
        let actualBarWidth = CGFloat(segmentCount) * segmentWidth + CGFloat(segmentCount - 1) * segmentGap
        var textX: CGFloat
        if showBar {
            textX = barX + actualBarWidth + barToTextGap
        } else {
            textX = x
        }
        if showPct {
            x = max(x, textX + textWidth + rightPad)
        }
        let extraPad: CGFloat = (showBar && showPct) ? 40.0 : 0.0
        let totalWidth = ceil(x + rightPad + 16.0 + extraPad)

        return renderImage(width: totalWidth) { ctx in
            // Draw logo — centered on bar midpoint
            if let logo = logo {
                let logoY = max(0, barMidY - logoSize / 2.0)
                logo.draw(
                    in: NSRect(x: 0, y: logoY, width: logoSize, height: logoSize),
                    from: NSRect(origin: .zero, size: logo.size),
                    operation: .sourceOver,
                    fraction: 0.9
                )
            }

            // Draw bar segments
            if showBar {
                let filledCount = Int((pct / 100.0 * Double(segmentCount)).rounded())
                for i in 0..<segmentCount {
                    let segX = barX + CGFloat(i) * (segmentWidth + segmentGap)
                    let rect = NSRect(x: segX, y: segmentY, width: segmentWidth, height: segmentHeight)

                    if i < filledCount {
                        activeColor.setFill()
                    } else {
                        colorDim.setFill()
                    }

                    let path = NSBezierPath(roundedRect: rect, xRadius: segmentRadius, yRadius: segmentRadius)
                    path.fill()
                }
            }

            // Draw percentage text — centered on bar midpoint
            if showPct {
                let textY = max(0, barMidY - textHeight / 2.0)
                (pctText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
            }
        }
    }

    /// Render the unauthenticated state.
    static func renderUnauthenticated(logo: NSImage? = nil) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: colorUnauth
        ]
        let label = "no auth"
        let textRect = (label as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: imageHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let textWidth = ceil(textRect.width)
        let textHeight = ceil(textRect.height)

        var x: CGFloat = 0
        if logo != nil { x += logoSize + logoPad }
        let barX = x
        x += barTotalWidth() + barToTextGap
        let textX = x
        x += textWidth + rightPad
        let totalWidth = ceil(x + rightPad + 16.0)

        return renderImage(width: totalWidth) { _ in
            if let logo = logo {
                let logoY = max(0, barMidY - logoSize / 2.0)
                logo.draw(
                    in: NSRect(x: 0, y: logoY, width: logoSize, height: logoSize),
                    from: NSRect(origin: .zero, size: logo.size),
                    operation: .sourceOver,
                    fraction: 0.3
                )
            }

            for i in 0..<segmentCount {
                let segX = barX + CGFloat(i) * (segmentWidth + segmentGap)
                let rect = NSRect(x: segX, y: segmentY, width: segmentWidth, height: segmentHeight)
                colorDim.setFill()
                NSBezierPath(roundedRect: rect, xRadius: segmentRadius, yRadius: segmentRadius).fill()
            }

            let textY = max(0, barMidY - textHeight / 2.0)
            (label as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
        }
    }

    // MARK: - Private

    /// A simple view for displaying a usage bar inside an NSMenuItem.
    class UsageBarMenuView: NSView {
        private let titleLabel: NSTextField
        private let pctLabel: NSTextField
        private var percentage: Double = 0

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

        func update(percentage: Double) {
            self.percentage = max(0, min(100, percentage))
            pctLabel.stringValue = "\(Int(self.percentage.rounded()))%"
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

            // Fill
            let fillW = barW * CGFloat(percentage / 100.0)
            if fillW > 0.5 {
                (percentage >= 90 ? colorRed : colorOrange).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: fillW, height: barH),
                             xRadius: r, yRadius: r).fill()
            }
        }
    }

    /// Create a Retina-quality NSImage by drawing into a 2x bitmap.
    private static func renderImage(width: CGFloat, draw: (CGContext) -> Void) -> NSImage {
        let pixelW = Int(width * scale)
        let pixelH = Int(imageHeight * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: NSSize(width: width, height: imageHeight))
        }

        rep.size = NSSize(width: width, height: imageHeight)

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high

        if let cgCtx = context?.cgContext {
            cgCtx.scaleBy(x: scale, y: scale)
            draw(cgCtx)
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: imageHeight))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }
}
