import Cocoa
import CoreGraphics
import ImageIO

// MARK: - Data Types

struct PetPackage {
    let id: String
    let displayName: String
    let description: String
    let folder: URL
    let spritesheet: URL
}

enum PetState: String {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case sleeping
    case review

    var row: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .sleeping: return 7
        case .review: return 8
        }
    }

    var frameDurations: [TimeInterval] {
        switch self {
        case .idle: return [0.280, 0.110, 0.110, 0.140, 0.140, 0.320]
        case .runningRight, .runningLeft:
            return [0.120, 0.120, 0.120, 0.120, 0.120, 0.120, 0.120, 0.220]
        case .waving: return [0.140, 0.140, 0.140, 0.280]
        case .jumping: return [0.140, 0.140, 0.140, 0.140, 0.280]
        case .failed: return [0.140, 0.140, 0.140, 0.140, 0.140, 0.140, 0.140, 0.240]
        case .waiting, .sleeping: return [0.160, 0.160, 0.160, 0.160, 0.160, 0.160]
        case .review: return [0.150, 0.150, 0.150, 0.150, 0.150, 0.280]
        }
    }

    var loopsForever: Bool {
        switch self {
        case .waving, .jumping, .failed:
            return false
        default:
            return true
        }
    }
}

// MARK: - Desktop Pet Window

final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetSpriteView: NSView {
    static let cellWidth = 192
    static let cellHeight = 208
    static let columns = 8
    static let rows = 9

    private(set) var package: PetPackage
    private(set) var atlas: CGImage
    var state: PetState = .idle {
        didSet {
            if oldValue != state {
                frameIndex = 0
                elapsedInFrame = 0
                needsDisplay = true
            }
        }
    }
    var frameIndex = 0
    var elapsedInFrame: TimeInterval = 0
    var isDraggingPet = false
    var onTap: (() -> Void)?
    var onContextAction: ((String) -> Void)?

    private var dragOffset = NSPoint.zero
    private var mouseDownScreen = NSPoint.zero
    private var didDrag = false
    private var lastClickTime: TimeInterval = 0
    private var oneShotCompletion: (() -> Void)?

    init(frame frameRect: NSRect, package: PetPackage, atlas: CGImage) {
        self.package = package
        self.atlas = atlas
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = "\(package.displayName): \(package.description)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        let source = CGRect(
            x: frameIndex * Self.cellWidth,
            y: state.row * Self.cellHeight,
            width: Self.cellWidth,
            height: Self.cellHeight
        )

        guard let frame = atlas.cropping(to: source) else {
            ctx.restoreGState()
            return
        }

        let destination = aspectFitRect(
            sourceSize: CGSize(width: Self.cellWidth, height: Self.cellHeight),
            in: bounds
        )
        ctx.draw(frame, in: destination)
        ctx.restoreGState()
    }

    func advance(by delta: TimeInterval) {
        let durations = state.frameDurations
        guard !durations.isEmpty else { return }

        elapsedInFrame += delta
        while elapsedInFrame >= durations[frameIndex] {
            elapsedInFrame -= durations[frameIndex]
            frameIndex += 1

            if frameIndex >= durations.count {
                if state.loopsForever {
                    frameIndex = 0
                } else {
                    frameIndex = 0
                    let completion = oneShotCompletion
                    oneShotCompletion = nil
                    completion?()
                    break
                }
            }
        }

        needsDisplay = true
    }

    func playOnce(_ newState: PetState, then completion: @escaping () -> Void) {
        oneShotCompletion = completion
        state = newState
    }

    func update(package: PetPackage, atlas: CGImage) {
        self.package = package
        self.atlas = atlas
        state = .idle
        frameIndex = 0
        elapsedInFrame = 0
        toolTip = "\(package.displayName): \(package.description)"
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isDraggingPet = true
        didDrag = false
        mouseDownScreen = NSEvent.mouseLocation
        guard let window else { return }
        dragOffset = event.locationInWindow
        lastClickTime = ProcessInfo.processInfo.systemUptime
        window.orderFrontRegardless()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownScreen.x
        let dy = current.y - mouseDownScreen.y
        if dx * dx + dy * dy > 9 { didDrag = true }

        var origin = current
        origin.x -= dragOffset.x
        origin.y -= dragOffset.y

        let frame = window.frame
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingPet = false
        if let window {
            UserDefaults.standard.set(window.frame.origin.x, forKey: "pet.origin.x")
            UserDefaults.standard.set(window.frame.origin.y, forKey: "pet.origin.y")
        }
        if !didDrag {
            onTap?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle("Stay", action: #selector(ctxStay), keyEquivalent: ""))
        menu.addItem(withTitle("Wander", action: #selector(ctxWander), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle("Wave", action: #selector(ctxWave), keyEquivalent: ""))
        menu.addItem(withTitle("Jump", action: #selector(ctxJump), keyEquivalent: ""))
        menu.addItem(withTitle("Review", action: #selector(ctxReview), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle("Open AlwaysPet...", action: #selector(ctxOpen), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func withTitle(_ title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func ctxStay() { onContextAction?("stay") }
    @objc private func ctxWander() { onContextAction?("wander") }
    @objc private func ctxWave() { onContextAction?("wave") }
    @objc private func ctxJump() { onContextAction?("jump") }
    @objc private func ctxReview() { onContextAction?("review") }
    @objc private func ctxOpen() { onContextAction?("open") }

    private func aspectFitRect(sourceSize: CGSize, in bounds: NSRect) -> CGRect {
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let width = sourceSize.width * scale
        let height = sourceSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }
}

// MARK: - Pet Gallery Card

final class PetCardView: NSView {
    let package: PetPackage
    private let atlas: CGImage?

    var isActive: Bool = false { didSet { needsDisplay = true } }
    var isChosen: Bool = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private var frameIndex: Int
    private var elapsed: TimeInterval = 0

    private static let accentWarm = NSColor(calibratedHue: 0.06, saturation: 0.72, brightness: 0.96, alpha: 1.0)
    private static let accentGlow = NSColor(calibratedHue: 0.08, saturation: 0.55, brightness: 1.0, alpha: 1.0)

    init(package: PetPackage) {
        self.package = package
        self.atlas = try? AppDelegate.loadAtlas(from: package.spritesheet)
        let maxFrames = PetState.idle.frameDurations.count
        self.frameIndex = maxFrames > 0 ? Int.random(in: 0..<maxFrames) : 0
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 230))
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = false
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowBlurRadius = 8
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1.0
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func advance(by delta: TimeInterval) {
        let durations = PetState.idle.frameDurations
        guard !durations.isEmpty, atlas != nil else { return }
        elapsed += delta
        while elapsed >= durations[frameIndex] {
            elapsed -= durations[frameIndex]
            frameIndex = (frameIndex + 1) % durations.count
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let cardRect = bounds.insetBy(dx: 3, dy: 3)
        let cornerRadius: CGFloat = 18
        let path = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

        if isChosen {
            let bgColor = NSColor.controlAccentColor.withAlphaComponent(0.06)
            bgColor.setFill()
            path.fill()

            Self.accentWarm.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 2.5
            path.stroke()

            let glowPath = NSBezierPath(roundedRect: cardRect.insetBy(dx: -1, dy: -1), xRadius: cornerRadius + 1, yRadius: cornerRadius + 1)
            Self.accentGlow.withAlphaComponent(0.15).setStroke()
            glowPath.lineWidth = 4
            glowPath.stroke()
        } else if isHovered {
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        } else {
            NSColor.controlBackgroundColor.withAlphaComponent(0.7).setFill()
            path.fill()
            NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if let atlas = atlas {
            ctx.saveGState()
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)

            let srcRect = CGRect(
                x: frameIndex * PetSpriteView.cellWidth,
                y: PetState.idle.row * PetSpriteView.cellHeight,
                width: PetSpriteView.cellWidth,
                height: PetSpriteView.cellHeight
            )

            if let sprite = atlas.cropping(to: srcRect) {
                let area = NSRect(x: 30, y: 20, width: bounds.width - 60, height: 120)
                let srcSize = CGSize(width: CGFloat(PetSpriteView.cellWidth), height: CGFloat(PetSpriteView.cellHeight))
                let scale = min(area.width / srcSize.width, area.height / srcSize.height)
                let w = srcSize.width * scale
                let h = srcSize.height * scale
                let dx = area.midX - w / 2
                let dy = area.midY - h / 2

                ctx.saveGState()
                ctx.translateBy(x: dx, y: dy + h)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(sprite, in: CGRect(x: 0, y: 0, width: w, height: h))
                ctx.restoreGState()
            }

            ctx.restoreGState()
        } else {
            let placeholder = "?" as NSString
            let pAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 48, weight: .ultraLight),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let pSize = placeholder.size(withAttributes: pAttrs)
            placeholder.draw(at: NSPoint(x: (bounds.width - pSize.width) / 2, y: 60), withAttributes: pAttrs)
        }

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail

        let nameFont = NSFont(descriptor: NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: .body)
            .withDesign(.rounded)!
            .withSymbolicTraits(isActive ? .bold : []),
            size: 14) ?? NSFont.systemFont(ofSize: 14, weight: isActive ? .bold : .semibold)

        let nameRect = NSRect(x: 10, y: 170, width: bounds.width - 20, height: 22)
        let nameStr = NSMutableAttributedString(
            string: package.displayName,
            attributes: [
                .font: nameFont,
                .foregroundColor: isChosen ? Self.accentWarm : NSColor.labelColor,
                .paragraphStyle: para
            ]
        )
        nameStr.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

        if isActive {
            let badgeText = "ACTIVE" as NSString
            let badgeFont = NSFont(descriptor: NSFontDescriptor
                .preferredFontDescriptor(forTextStyle: .caption1)
                .withDesign(.rounded)!
                .withSymbolicTraits(.bold),
                size: 9) ?? NSFont.systemFont(ofSize: 9, weight: .bold)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor.white
            ]
            let badgeSize = badgeText.size(withAttributes: badgeAttrs)
            let badgeW = badgeSize.width + 10
            let badgeH: CGFloat = 16
            let badgeX = (bounds.width - badgeW) / 2
            let badgeY: CGFloat = 195

            let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2)
            NSColor.systemGreen.withAlphaComponent(0.85).setFill()
            badgePath.fill()

            badgeText.draw(
                at: NSPoint(x: badgeX + 5, y: badgeY + (badgeH - badgeSize.height) / 2),
                withAttributes: badgeAttrs
            )
        } else {
            let descRect = NSRect(x: 12, y: 194, width: bounds.width - 24, height: 16)
            let descFont = NSFont(descriptor: NSFontDescriptor
                .preferredFontDescriptor(forTextStyle: .caption1)
                .withDesign(.rounded)!,
                size: 11) ?? NSFont.systemFont(ofSize: 11)
            let descAttrs: [NSAttributedString.Key: Any] = [
                .font: descFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: para
            ]
            (package.description as NSString).draw(
                with: descRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: descAttrs,
                context: nil
            )
        }
    }
}

// MARK: - Pet Grid Layout

final class PetGridView: NSView {
    override var isFlipped: Bool { true }

    private let cardW: CGFloat = 180
    private let cardH: CGFloat = 230
    private let gap: CGFloat = 24
    private let topPad: CGFloat = 16

    func layoutCards() {
        let w = bounds.width
        guard w > 0 else { return }

        let cols = max(1, Int((w + gap) / (cardW + gap)))
        let totalW = CGFloat(cols) * cardW + CGFloat(cols - 1) * gap
        let padX = (w - totalW) / 2

        for (i, view) in subviews.enumerated() {
            let col = i % cols
            let row = i / cols
            view.frame = NSRect(
                x: padX + CGFloat(col) * (cardW + gap),
                y: topPad + CGFloat(row) * (cardH + gap),
                width: cardW,
                height: cardH
            )
        }

        let rowCount = subviews.isEmpty ? 0 : (subviews.count + cols - 1) / cols
        let contentH = topPad + CGFloat(rowCount) * cardH + max(0, CGFloat(rowCount - 1)) * gap + 24
        let minH = enclosingScrollView?.contentSize.height ?? 0
        let newH = max(contentH, minH)
        if abs(frame.height - newH) > 0.5 {
            frame.size.height = newH
        }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        layoutCards()
    }
}

// MARK: - Main Window Controller

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private var packages: [PetPackage]
    private var activeId: String
    private var selectedIndex: Int = -1

    private let onActivate: (PetPackage) -> Void
    private let onDeactivate: () -> Void
    private let onRefresh: () -> [PetPackage]
    private let onWanderChanged: (Bool) -> Void
    private let onPinnedChanged: (Bool) -> Void
    private let onSizeChanged: (Double) -> Void
    var onClose: (() -> Void)?

    private let scrollView = NSScrollView()
    private let gridView = PetGridView(frame: .zero)
    private var cardViews: [PetCardView] = []

    private let activateButton: NSButton
    private let wanderButton: NSButton
    private let pinButton: NSButton
    private let launchAtLoginButton: NSButton
    private let sizeSlider: NSSlider
    private var petCountLabel: NSTextField!
    private var refreshButton: NSButton!
    private var animTimer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    private static let accentWarm = NSColor(calibratedHue: 0.06, saturation: 0.72, brightness: 0.96, alpha: 1.0)

    init(packages: [PetPackage], activeId: String,
         wanderEnabled: Bool, pinnedOnTop: Bool, scale: Double,
         onActivate: @escaping (PetPackage) -> Void,
         onDeactivate: @escaping () -> Void,
         onRefresh: @escaping () -> [PetPackage],
         onWanderChanged: @escaping (Bool) -> Void,
         onPinnedChanged: @escaping (Bool) -> Void,
         onSizeChanged: @escaping (Double) -> Void) {

        self.packages = packages
        self.activeId = activeId
        self.onActivate = onActivate
        self.onDeactivate = onDeactivate
        self.onRefresh = onRefresh
        self.onWanderChanged = onWanderChanged
        self.onPinnedChanged = onPinnedChanged
        self.onSizeChanged = onSizeChanged

        self.activateButton = NSButton(title: "Activate", target: nil, action: nil)
        self.wanderButton = NSButton(title: "", target: nil, action: nil)
        self.pinButton = NSButton(title: "", target: nil, action: nil)
        self.launchAtLoginButton = NSButton(title: "", target: nil, action: nil)
        self.sizeSlider = NSSlider(value: scale, minValue: 0.35, maxValue: 1.5, target: nil, action: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AlwaysPet"
        window.minSize = NSSize(width: 460, height: 420)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("AlwaysPetMain")
        if !window.setFrameUsingName("AlwaysPetMain") {
            window.center()
        }

        super.init(window: window)
        window.delegate = self

        wanderButton.state = wanderEnabled ? .on : .off
        pinButton.state = pinnedOnTop ? .on : .off

        buildUI()
        populateCards()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(packages: [PetPackage], activeId: String) {
        self.packages = packages
        self.activeId = activeId
        populateCards()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.layoutIfNeeded()
        gridView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        gridView.layoutCards()
        selectActiveCard()
        startAnimationTimer()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        startAnimationTimer()
    }

    func windowDidResignKey(_ notification: Notification) {
        stopAnimationTimer()
    }

    func windowWillClose(_ notification: Notification) {
        stopAnimationTimer()
        onClose?()
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let bgEffect = NSVisualEffectView()
        bgEffect.material = .underWindowBackground
        bgEffect.blendingMode = .behindWindow
        bgEffect.state = .active
        bgEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bgEffect)

        NSLayoutConstraint.activate([
            bgEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            bgEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bgEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bgEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        let headerBg = NSVisualEffectView()
        headerBg.material = .headerView
        headerBg.blendingMode = .withinWindow
        headerBg.state = .active
        headerBg.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerBg)

        let titleFont = NSFont(descriptor: NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: .largeTitle)
            .withDesign(.rounded)!
            .withSymbolicTraits(.bold),
            size: 28) ?? NSFont.systemFont(ofSize: 28, weight: .bold)

        let titleLabel = NSTextField(labelWithString: "AlwaysPet")
        titleLabel.font = titleFont
        titleLabel.textColor = .labelColor

        let subtitleFont = NSFont(descriptor: NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: .subheadline)
            .withDesign(.rounded)!,
            size: 13) ?? NSFont.systemFont(ofSize: 13)

        let subtitleLabel = NSTextField(labelWithString: "Choose a desktop companion from your collection")
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = .secondaryLabelColor

        petCountLabel = NSTextField(labelWithString: "\(packages.count) pet\(packages.count == 1 ? "" : "s") available")
        petCountLabel.font = NSFont(descriptor: NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: .caption1)
            .withDesign(.rounded)!,
            size: 11) ?? NSFont.systemFont(ofSize: 11)
        petCountLabel.textColor = .tertiaryLabelColor

        refreshButton = NSButton(title: "", target: self, action: #selector(refreshPets))
        refreshButton.bezelStyle = .circular
        refreshButton.isBordered = false
        refreshButton.toolTip = "Scan for new pets"

        let refreshIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!)
        refreshIcon.contentTintColor = .secondaryLabelColor
        refreshIcon.wantsLayer = true
        refreshIcon.translatesAutoresizingMaskIntoConstraints = false
        refreshIcon.tag = 999
        refreshButton.addSubview(refreshIcon)
        NSLayoutConstraint.activate([
            refreshIcon.centerXAnchor.constraint(equalTo: refreshButton.centerXAnchor),
            refreshIcon.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            refreshIcon.widthAnchor.constraint(equalToConstant: 16),
            refreshIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        gridView.autoresizingMask = [.width]
        scrollView.documentView = gridView

        let toolbarBg = NSVisualEffectView()
        toolbarBg.material = .titlebar
        toolbarBg.blendingMode = .withinWindow
        toolbarBg.state = .active
        toolbarBg.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolbarBg)

        let toolbarSeparator = NSBox()
        toolbarSeparator.boxType = .separator

        activateButton.bezelStyle = .rounded
        activateButton.target = self
        activateButton.action = #selector(activateSelected)
        activateButton.keyEquivalent = "\r"
        activateButton.isEnabled = false
        activateButton.controlSize = .large
        activateButton.wantsLayer = true
        activateButton.layer?.cornerRadius = 8
        activateButton.contentTintColor = .white
        activateButton.bezelColor = Self.accentWarm

        wanderButton.setButtonType(.toggle)
        wanderButton.bezelStyle = .rounded
        wanderButton.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Wander")
        wanderButton.imagePosition = .imageLeading
        wanderButton.title = "Wander"
        wanderButton.toolTip = "Let the pet walk around your screen"
        wanderButton.target = self
        wanderButton.action = #selector(wanderToggled)
        wanderButton.controlSize = .regular

        pinButton.setButtonType(.toggle)
        pinButton.bezelStyle = .rounded
        pinButton.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Always on Top")
        pinButton.imagePosition = .imageLeading
        pinButton.title = "Always on Top"
        pinButton.toolTip = "Keep pet visible above all other windows"
        pinButton.target = self
        pinButton.action = #selector(pinToggled)
        pinButton.controlSize = .regular

        launchAtLoginButton.setButtonType(.toggle)
        launchAtLoginButton.bezelStyle = .rounded
        launchAtLoginButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Launch at Login")
        launchAtLoginButton.imagePosition = .imageLeading
        launchAtLoginButton.title = "Launch at Login"
        launchAtLoginButton.toolTip = "Automatically start AlwaysPet when you log in"
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginToggled)
        launchAtLoginButton.controlSize = .regular
        launchAtLoginButton.state = Self.isLaunchAgentInstalled() ? .on : .off

        let sizeIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Size")!)
        sizeIcon.contentTintColor = .secondaryLabelColor

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeSliderChanged)
        sizeSlider.isContinuous = true
        sizeSlider.controlSize = .small
        sizeSlider.toolTip = "Adjust the pet size on your desktop"

        let allViews: [NSView] = [
            titleLabel, subtitleLabel, petCountLabel, refreshButton, scrollView,
            toolbarSeparator, wanderButton, pinButton, launchAtLoginButton, sizeIcon, sizeSlider, activateButton
        ]
        for v in allViews {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        let headerHeight: CGFloat = 90

        NSLayoutConstraint.activate([
            headerBg.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerBg.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerBg.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerBg.heightAnchor.constraint(equalToConstant: headerHeight),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),

            refreshButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            refreshButton.widthAnchor.constraint(equalToConstant: 28),
            refreshButton.heightAnchor.constraint(equalToConstant: 28),

            petCountLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            petCountLabel.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: headerHeight + 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: toolbarSeparator.topAnchor, constant: -8),

            toolbarBg.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbarBg.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbarBg.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            toolbarBg.heightAnchor.constraint(equalToConstant: 56),

            toolbarSeparator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbarSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbarSeparator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -56),

            wanderButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            wanderButton.centerYAnchor.constraint(equalTo: toolbarBg.centerYAnchor),

            pinButton.leadingAnchor.constraint(equalTo: wanderButton.trailingAnchor, constant: 10),
            pinButton.centerYAnchor.constraint(equalTo: toolbarBg.centerYAnchor),

            launchAtLoginButton.leadingAnchor.constraint(equalTo: pinButton.trailingAnchor, constant: 10),
            launchAtLoginButton.centerYAnchor.constraint(equalTo: toolbarBg.centerYAnchor),

            sizeIcon.leadingAnchor.constraint(equalTo: launchAtLoginButton.trailingAnchor, constant: 16),
            sizeIcon.centerYAnchor.constraint(equalTo: toolbarBg.centerYAnchor),
            sizeIcon.widthAnchor.constraint(equalToConstant: 16),
            sizeIcon.heightAnchor.constraint(equalToConstant: 16),

            sizeSlider.leadingAnchor.constraint(equalTo: sizeIcon.trailingAnchor, constant: 8),
            sizeSlider.widthAnchor.constraint(equalToConstant: 90),
            sizeSlider.centerYAnchor.constraint(equalTo: toolbarBg.centerYAnchor),

            activateButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            activateButton.centerYAnchor.constraint(equalTo: toolbarBg.centerYAnchor),
            activateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
    }

    // MARK: - Cards

    private func populateCards() {
        for card in cardViews { card.removeFromSuperview() }
        cardViews.removeAll()

        for (i, pkg) in packages.enumerated() {
            let card = PetCardView(package: pkg)
            card.isActive = pkg.id == activeId
            let idx = i
            card.onClick = { [weak self] in self?.selectCard(at: idx) }
            cardViews.append(card)
            gridView.addSubview(card)
        }
    }

    private func selectCard(at index: Int) {
        guard packages.indices.contains(index) else { return }

        if cardViews.indices.contains(selectedIndex) {
            cardViews[selectedIndex].isChosen = false
        }

        selectedIndex = index
        cardViews[index].isChosen = true

        let isCurrent = packages[index].id == activeId
        activateButton.isEnabled = true
        if isCurrent {
            activateButton.title = "Disable"
            activateButton.bezelColor = .systemRed
        } else {
            activateButton.title = "Activate"
            activateButton.bezelColor = Self.accentWarm
        }
    }

    private func selectActiveCard() {
        let idx = packages.firstIndex { $0.id == activeId } ?? 0
        if packages.indices.contains(idx) {
            selectCard(at: idx)
        }
    }

    // MARK: - Actions

    @objc private func activateSelected() {
        guard packages.indices.contains(selectedIndex) else { return }
        let pkg = packages[selectedIndex]

        if pkg.id == activeId {
            onDeactivate()
            activeId = ""
            for card in cardViews { card.isActive = false }
            activateButton.title = "Activate"
            activateButton.bezelColor = Self.accentWarm
        } else {
            activeId = pkg.id
            for (i, card) in cardViews.enumerated() {
                card.isActive = packages[i].id == activeId
            }
            activateButton.title = "Disable"
            activateButton.bezelColor = .systemRed
            onActivate(pkg)
        }
    }

    @objc private func wanderToggled() {
        onWanderChanged(wanderButton.state == .on)
    }

    @objc private func pinToggled() {
        onPinnedChanged(pinButton.state == .on)
    }

    @objc private func sizeSliderChanged() {
        onSizeChanged(sizeSlider.doubleValue)
    }

    @objc private func refreshPets() {
        if let iconView = refreshButton.viewWithTag(999), let layer = iconView.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: iconView.bounds.midX, y: iconView.bounds.midY)
            layer.removeAllAnimations()
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = Double.pi * 2
            spin.duration = 0.5
            layer.add(spin, forKey: "spin")
        }

        let oldCount = packages.count
        let newPackages = onRefresh()
        packages = newPackages
        populateCards()
        gridView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        gridView.layoutCards()
        selectActiveCard()

        let diff = packages.count - oldCount
        if diff > 0 {
            petCountLabel.stringValue = "\(packages.count) pets available (+\(diff) new!)"
            petCountLabel.textColor = .systemGreen
        } else if diff < 0 {
            petCountLabel.stringValue = "\(packages.count) pet\(packages.count == 1 ? "" : "s") available (\(diff) removed)"
            petCountLabel.textColor = .systemOrange
        } else {
            petCountLabel.stringValue = "\(packages.count) pet\(packages.count == 1 ? "" : "s") available (up to date)"
            petCountLabel.textColor = .tertiaryLabelColor
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            self.petCountLabel.stringValue = "\(self.packages.count) pet\(self.packages.count == 1 ? "" : "s") available"
            self.petCountLabel.textColor = .tertiaryLabelColor
        }
    }

    @objc private func launchAtLoginToggled() {
        let enable = launchAtLoginButton.state == .on
        if enable {
            Self.installLaunchAgent()
            if Self.isLaunchAgentInstalled() {
                showToast("AlwaysPet will now start automatically when you log in.")
            } else {
                launchAtLoginButton.state = .off
                showError("Failed to install login agent", detail: "Could not write to ~/Library/LaunchAgents. Check disk permissions.")
            }
        } else {
            Self.uninstallLaunchAgent()
            if !Self.isLaunchAgentInstalled() {
                showToast("AlwaysPet will no longer start at login.")
            } else {
                launchAtLoginButton.state = .on
                showError("Failed to remove login agent", detail: "Could not remove the launch agent file.")
            }
        }
    }

    private func showToast(_ message: String) {
        guard let contentView = window?.contentView else { return }
        let toast = NSTextField(labelWithString: message)
        toast.font = NSFont(descriptor: NSFontDescriptor
            .preferredFontDescriptor(forTextStyle: .callout)
            .withDesign(.rounded)!,
            size: 12) ?? NSFont.systemFont(ofSize: 12)
        toast.textColor = .white
        toast.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        toast.drawsBackground = true
        toast.isBezeled = false
        toast.alignment = .center
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 8
        toast.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -72),
            toast.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -80),
            toast.heightAnchor.constraint(equalToConstant: 32),
        ])

        toast.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            toast.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.removeFromSuperview()
            })
        }
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let w = window {
            alert.beginSheetModal(for: w)
        } else {
            alert.runModal()
        }
    }

    private static let launchAgentPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/Library/LaunchAgents/local.alwayspet.plist"
    }()

    static func isLaunchAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    private static func installLaunchAgent() {
        let executablePath = Bundle.main.executablePath ?? Bundle.main.bundlePath + "/Contents/MacOS/AlwaysPet"
        let bundleRoot = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>local.alwayspet</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executablePath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <dict>
            <key>SuccessfulExit</key>
            <false/>
          </dict>
          <key>StandardOutPath</key>
          <string>\(bundleRoot)/alwayspet.log</string>
          <key>StandardErrorPath</key>
          <string>\(bundleRoot)/alwayspet.err.log</string>
        </dict>
        </plist>
        """

        let dir = (launchAgentPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)

        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["unload", launchAgentPath]
        try? unload.run()
        unload.waitUntilExit()

        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        load.arguments = ["load", launchAgentPath]
        try? load.run()
        load.waitUntilExit()
    }

    private static func uninstallLaunchAgent() {
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["unload", launchAgentPath]
        try? unload.run()
        unload.waitUntilExit()

        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }

    // MARK: - Card Animation

    private func startAnimationTimer() {
        guard animTimer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let dt = min(now - self.lastTick, 0.1)
            self.lastTick = now
            for card in self.cardViews { card.advance(by: dt) }
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    private func stopAnimationTimer() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: PetWindow!
    private var petView: PetSpriteView!
    private var timer: Timer!
    private var statusItem: NSStatusItem!
    private var petPackages: [PetPackage] = []
    private var currentPackage: PetPackage!
    private var mainWindowController: MainWindowController?
    private var wanderEnabled = true
    private var pinnedOnTop = true
    private var velocity: CGFloat = 42
    private var lastTick = ProcessInfo.processInfo.systemUptime

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            petPackages = try Self.loadPetPackages()
            currentPackage = Self.selectedPackage(from: petPackages)
            let atlas = try Self.loadAtlas(from: currentPackage.spritesheet)
            createWindow(package: currentPackage, atlas: atlas)
            createStatusItem(package: currentPackage)
            startTimer()
        } catch {
            showStartupError(error)
            NSApp.terminate(nil)
            return
        }

        openMainWindow()
        checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        savePosition()
    }

    // MARK: - Update Check

    private static let currentVersion = "0.1.0"
    private static let versionURL = URL(string: "https://freeyour.pet/version.json")!

    private func checkForUpdates() {
        URLSession.shared.dataTask(with: Self.versionURL) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latest = json["version"] as? String,
                  let urlString = json["url"] as? String,
                  let downloadURL = URL(string: urlString),
                  latest.compare(Self.currentVersion, options: .numeric) == .orderedDescending
            else { return }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "AlwaysPet \(latest) is available"
                alert.informativeText = "You're running \(Self.currentVersion). Would you like to download the update?"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(downloadURL)
                }
            }
        }.resume()
    }

    // MARK: - Desktop Pet

    private func createWindow(package: PetPackage, atlas: CGImage) {
        let size = restoredSize()
        let origin = restoredOrigin(size: size)
        petView = PetSpriteView(frame: NSRect(origin: .zero, size: size), package: package, atlas: atlas)
        petView.onTap = { [weak self] in self?.openMainWindow() }
        petView.onContextAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case "stay":
                self.setWandering(false)
            case "wander":
                self.setWandering(true)
            case "wave":
                self.wave()
            case "jump":
                self.jump()
            case "review":
                self.review()
            case "open":
                self.openMainWindow()
            default:
                break
            }
        }

        window = PetWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = petView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
    }

    private func createStatusItem(package: PetPackage) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = package.displayName
        statusItem.button?.toolTip = package.description

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open AlwaysPet...", action: #selector(openMainWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Pause Wandering", action: #selector(toggleWandering(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Keep Above Windows", action: #selector(togglePinned(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Wave", action: #selector(wave), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Jump", action: #selector(jump), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Review", action: #selector(review), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Failed", action: #selector(failed), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Smaller", action: #selector(smaller), keyEquivalent: "-"))
        menu.addItem(NSMenuItem(title: "Bigger", action: #selector(bigger), keyEquivalent: "+"))
        menu.addItem(NSMenuItem(title: "Center Pet", action: #selector(centerPet), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AlwaysPet", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        updateMenuState()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(now - lastTick, 0.1)
        lastTick = now

        if wanderEnabled && !petView.isDraggingPet {
            movePet(delta: delta)
        } else if petView.state == .runningLeft || petView.state == .runningRight {
            petView.state = .idle
        }

        petView.advance(by: delta)
    }

    private func movePet(delta: TimeInterval) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame

        frame.origin.x += velocity * CGFloat(delta)
        if frame.minX <= visible.minX + 8 {
            frame.origin.x = visible.minX + 8
            velocity = abs(velocity)
        } else if frame.maxX >= visible.maxX - 8 {
            frame.origin.x = visible.maxX - frame.width - 8
            velocity = -abs(velocity)
        }

        frame.origin.y = max(frame.origin.y, visible.minY + 8)
        window.setFrame(frame, display: false)

        if petView.state == .idle || petView.state == .runningLeft || petView.state == .runningRight {
            petView.state = velocity >= 0 ? .runningRight : .runningLeft
        }
    }

    // MARK: - Main Window

    @objc private func openMainWindow() {
        do {
            petPackages = try Self.loadPetPackages()
        } catch {
            showStartupError(error)
            return
        }

        let scale = UserDefaults.standard.object(forKey: "pet.scale") == nil
            ? 0.75
            : UserDefaults.standard.double(forKey: "pet.scale")

        if let controller = mainWindowController {
            controller.update(packages: petPackages, activeId: currentPackage.id)
            controller.showWindow(nil)
        } else {
            let controller = MainWindowController(
                packages: petPackages,
                activeId: currentPackage.id,
                wanderEnabled: wanderEnabled,
                pinnedOnTop: pinnedOnTop,
                scale: scale,
                onActivate: { [weak self] pkg in self?.switchPet(to: pkg) },
                onDeactivate: { [weak self] in self?.hidePet() },
                onRefresh: { [weak self] in
                    guard let self else { return [] }
                    self.petPackages = (try? Self.loadPetPackages()) ?? self.petPackages
                    return self.petPackages
                },
                onWanderChanged: { [weak self] on in self?.setWandering(on) },
                onPinnedChanged: { [weak self] on in self?.setPinned(on) },
                onSizeChanged: { [weak self] s in self?.setScale(s) }
            )
            controller.onClose = {
                NSApp.setActivationPolicy(.accessory)
            }
            mainWindowController = controller
            controller.showWindow(nil)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Helpers

    private func setWandering(_ enabled: Bool) {
        wanderEnabled = enabled
        if !wanderEnabled {
            petView.state = .idle
            savePosition()
        }
        updateMenuState()
    }

    private func setPinned(_ pinned: Bool) {
        pinnedOnTop = pinned
        window.level = pinnedOnTop ? .floating : .normal
        updateMenuState()
    }

    private func setScale(_ scale: Double) {
        let petW = CGFloat(PetSpriteView.cellWidth)
        let petH = CGFloat(PetSpriteView.cellHeight)
        let newWidth = min(max(petW * CGFloat(scale), 64), 384)
        let newHeight = newWidth * petH / petW

        let oldFrame = window.frame
        let newFrame = NSRect(
            x: oldFrame.midX - newWidth / 2,
            y: oldFrame.midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        window.setFrame(newFrame, display: true)
        petView.frame = NSRect(origin: .zero, size: newFrame.size)
        UserDefaults.standard.set(Double(newWidth / petW), forKey: "pet.scale")
    }

    // MARK: - Pet Management

    private func switchPet(to package: PetPackage) {
        do {
            let atlas = try Self.loadAtlas(from: package.spritesheet)
            currentPackage = package
            petView.update(package: package, atlas: atlas)
            statusItem.button?.title = package.displayName
            statusItem.button?.toolTip = package.description
            UserDefaults.standard.set(package.id, forKey: "pet.selected.id")
            window.orderFrontRegardless()
        } catch {
            showStartupError(error)
        }
    }

    private func hidePet() {
        window.orderOut(nil)
        UserDefaults.standard.removeObject(forKey: "pet.selected.id")
    }

    // MARK: - Menu Actions

    @objc private func toggleWandering(_ sender: NSMenuItem) {
        wanderEnabled.toggle()
        if !wanderEnabled {
            petView.state = .idle
            savePosition()
        }
        updateMenuState()
    }

    @objc private func togglePinned(_ sender: NSMenuItem) {
        pinnedOnTop.toggle()
        window.level = pinnedOnTop ? .floating : .normal
        updateMenuState()
    }

    @objc private func wave() { playOneShot(.waving) }
    @objc private func jump() { playOneShot(.jumping) }
    @objc private func failed() { playOneShot(.failed) }
    @objc private func review() { petView.state = .review }

    @objc private func smaller() { resizePet(by: 0.875) }
    @objc private func bigger() { resizePet(by: 1.125) }

    @objc private func centerPet() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = window.frame
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        window.setFrameOrigin(origin)
        savePosition()
    }

    @objc private func quit() {
        savePosition()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func playOneShot(_ state: PetState) {
        petView.playOnce(state) { [weak self] in
            guard let self else { return }
            self.petView.state = self.wanderEnabled ? (self.velocity >= 0 ? .runningRight : .runningLeft) : .idle
        }
    }

    private func resizePet(by factor: CGFloat) {
        let oldFrame = window.frame
        let newWidth = min(max(oldFrame.width * factor, 64), 384)
        let newHeight = newWidth * CGFloat(PetSpriteView.cellHeight) / CGFloat(PetSpriteView.cellWidth)
        let newFrame = NSRect(
            x: oldFrame.midX - newWidth / 2,
            y: oldFrame.midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        window.setFrame(newFrame, display: true)
        petView.frame = NSRect(origin: .zero, size: newFrame.size)
        UserDefaults.standard.set(Double(newWidth / CGFloat(PetSpriteView.cellWidth)), forKey: "pet.scale")
        savePosition()
    }

    private func restoredSize() -> NSSize {
        let defaults = UserDefaults.standard
        let scale = defaults.object(forKey: "pet.scale") == nil ? 0.75 : defaults.double(forKey: "pet.scale")
        return NSSize(
            width: CGFloat(PetSpriteView.cellWidth) * CGFloat(scale),
            height: CGFloat(PetSpriteView.cellHeight) * CGFloat(scale)
        )
    }

    private func restoredOrigin(size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "pet.origin.x") != nil,
           defaults.object(forKey: "pet.origin.y") != nil {
            let x = defaults.double(forKey: "pet.origin.x")
            let y = defaults.double(forKey: "pet.origin.y")
            return NSPoint(
                x: min(max(CGFloat(x), visible.minX), visible.maxX - size.width),
                y: min(max(CGFloat(y), visible.minY), visible.maxY - size.height)
            )
        }
        return NSPoint(x: visible.maxX - size.width - 48, y: visible.minY + 40)
    }

    private func savePosition() {
        guard let window else { return }
        UserDefaults.standard.set(window.frame.origin.x, forKey: "pet.origin.x")
        UserDefaults.standard.set(window.frame.origin.y, forKey: "pet.origin.y")
    }

    private func updateMenuState() {
        guard let items = statusItem.menu?.items else { return }
        if items.indices.contains(2) {
            items[2].state = wanderEnabled ? .off : .on
            items[2].title = wanderEnabled ? "Pause Wandering" : "Resume Wandering"
        }
        if items.indices.contains(3) {
            items[3].state = pinnedOnTop ? .on : .off
        }
    }

    private func showStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "AlwaysPet could not load your Codex pet"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .critical
        alert.runModal()
    }

    // MARK: - Pet Loading

    private static func selectedPackage(from packages: [PetPackage]) -> PetPackage {
        let defaults = UserDefaults.standard
        if let selectedId = defaults.string(forKey: "pet.selected.id"),
           let selected = packages.first(where: { $0.id == selectedId }) {
            return selected
        }
        return packages.first(where: { $0.id == "ninecry" }) ?? packages[0]
    }

    static func loadPetPackages() throws -> [PetPackage] {
        var seen = Set<String>()
        var packages: [PetPackage] = []

        let userPetsRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("pets")
        for folder in petFolders(in: userPetsRoot) {
            if let pkg = try? loadPetPackage(in: folder), !seen.contains(pkg.id) {
                seen.insert(pkg.id)
                packages.append(pkg)
            }
        }

        if let bundlePath = Bundle.main.resourcePath {
            let bundledPetsRoot = URL(fileURLWithPath: bundlePath).appendingPathComponent("pets")
            for folder in petFolders(in: bundledPetsRoot) {
                if let pkg = try? loadPetPackage(in: folder), !seen.contains(pkg.id) {
                    seen.insert(pkg.id)
                    packages.append(pkg)
                }
            }
        }

        packages.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        guard !packages.isEmpty else {
            throw NSError(domain: "AlwaysPet", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No pets found. Install pets to ~/.codex/pets or bundle them in Resources/pets."
            ])
        }

        return packages
    }

    private static func petFolders(in root: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func loadPetPackage(in folder: URL) throws -> PetPackage {
        let manifestURL = folder.appendingPathComponent("pet.json")
        let data = try Data(contentsOf: manifestURL)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let json = raw as? [String: Any] else {
            throw NSError(domain: "AlwaysPet", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid pet.json at \(manifestURL.path)."
            ])
        }

        let id = json["id"] as? String ?? folder.lastPathComponent
        let displayName = json["displayName"] as? String ?? id
        let description = json["description"] as? String ?? "Codex pet"
        let spritesheetPath = json["spritesheetPath"] as? String ?? "spritesheet.webp"
        let spritesheet = folder.appendingPathComponent(spritesheetPath)

        guard FileManager.default.fileExists(atPath: spritesheet.path) else {
            throw NSError(domain: "AlwaysPet", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Missing spritesheet at \(spritesheet.path)."
            ])
        }

        return PetPackage(
            id: id,
            displayName: displayName,
            description: description,
            folder: folder,
            spritesheet: spritesheet
        )
    }

    static func loadAtlas(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "AlwaysPet", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Could not decode spritesheet at \(url.path)."
            ])
        }

        guard image.width == PetSpriteView.cellWidth * PetSpriteView.columns,
              image.height == PetSpriteView.cellHeight * PetSpriteView.rows else {
            throw NSError(domain: "AlwaysPet", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Spritesheet has size \(image.width)x\(image.height), expected 1536x1872."
            ])
        }

        return image
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
