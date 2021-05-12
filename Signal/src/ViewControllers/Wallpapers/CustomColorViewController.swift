//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol CustomColorViewDelegate: class {
    func didSetCustomColor(value: ChatColorValue)
}

// MARK: -

public class CustomColorViewController: OWSTableViewController2 {

    private let thread: TSThread?

    private weak var customColorViewDelegate: CustomColorViewDelegate?

    private let modeControl = UISegmentedControl()

    private enum Mode: Int {
        case solid = 0
        case gradient = 1
    }

    private var mode: Mode = .solid {
        didSet {
            updateTableContents()
        }
    }

    private let hueSpectrum: HSLSpectrum
    private let hueSlider: SpectrumSlider
    private var hueAlpha: CGFloat { hueSlider.value.clamp01() }

    private var saturationSpectrum: HSLSpectrum
    private let saturationSlider: SpectrumSlider
    private var saturationAlpha: CGFloat { saturationSlider.value.clamp01() }

    public init(thread: TSThread? = nil,
                customColorViewDelegate: CustomColorViewDelegate) {
        self.thread = thread
        self.customColorViewDelegate = customColorViewDelegate

        self.hueSpectrum = Self.buildHueSpectrum()
        hueSlider = SpectrumSlider(spectrum: hueSpectrum,
                                   value: CustomColorViewController.randomAlphaValue())

        let hueValue = self.hueSpectrum.value(forAlpha: hueSlider.value.clamp01())
        self.saturationSpectrum = Self.buildSaturationSpectrum(referenceValue: hueValue)
        saturationSlider = SpectrumSlider(spectrum: saturationSpectrum,
                                          value: CustomColorViewController.randomAlphaValue())

        super.init()

        topHeader = OWSTableViewController2.buildTopHeader(forView: modeControl,
                                                           vMargin: 10)

//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(updateTableContents),
//            name: Wallpaper.wallpaperDidChangeNotification,
//            object: nil
//        )
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(updateTableContents),
//            name: ChatColors.autoChatColorDidChange,
//            object: nil
//        )
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(chatColorDidChange),
//            name: ChatColors.chatColorDidChange,
//            object: nil
//        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .ThemeDidChange,
            object: nil
        )
    }

//    @objc
//    private func chatColorDidChange(_ notification: NSNotification) {
//        guard let thread = self.thread else {
//            return
//        }
//        guard let threadUniqueId = notification.userInfo?[ChatColors.chatColorDidChangeThreadUniqueIdKey] as? String else {
//            owsFailDebug("Missing threadUniqueId.")
//            return
//        }
//        guard threadUniqueId == thread.uniqueId else {
//            return
//        }
//        updateTableContents()
//    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_TITLE",
                                  comment: "Title for the custom chat color settings view.")

        createSubviews()

        updateTableContents()
    }

    private func createSubviews() {
        modeControl.insertSegment(withTitle: NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_SOLID_COLOR",
                                                               comment: "Label for the 'solid color' mode in the custom chat color settings view."),
                                  at: Mode.solid.rawValue,
                                  animated: false)
        modeControl.insertSegment(withTitle: NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_GRADIENT",
                                                               comment: "Label for the 'gradient' mode in the custom chat color settings view."),
                                  at: Mode.gradient.rawValue,
                                  animated: false)
        modeControl.selectedSegmentIndex = mode.rawValue
        modeControl.addTarget(self,
                              action: #selector(modeControlDidChange),
                              for: .valueChanged)
    }

    private var mockConversationView: MockConversationView?

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let wallpaperPreviewView: UIView
        if let wallpaperView = (databaseStorage.read { transaction in
            Wallpaper.view(for: thread, transaction: transaction)
        }) {
            wallpaperPreviewView = wallpaperView.asPreviewView()
        } else {
            wallpaperPreviewView = UIView()
            wallpaperPreviewView.backgroundColor = Theme.backgroundColor
        }
        wallpaperPreviewView.layer.cornerRadius = OWSTableViewController2.cellRounding
        wallpaperPreviewView.clipsToBounds = true

        let mockConversationView = MockConversationView(
            mode: buildMockConversationMode(),
            hasWallpaper: true
        )
        self.mockConversationView = mockConversationView
        let previewSection = OWSTableSection()
        previewSection.hasBackground = false
        previewSection.add(OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            cell.contentView.addSubview(wallpaperPreviewView)
            wallpaperPreviewView.autoPinEdge(toSuperviewEdge: .left, withInset: self.cellHOuterLeftMargin)
            wallpaperPreviewView.autoPinEdge(toSuperviewEdge: .right, withInset: self.cellHOuterRightMargin)
            wallpaperPreviewView.autoPinHeightToSuperview()

            cell.contentView.addSubview(mockConversationView)
            mockConversationView.autoPinEdge(toSuperviewEdge: .left, withInset: self.cellHOuterLeftMargin)
            mockConversationView.autoPinEdge(toSuperviewEdge: .right, withInset: self.cellHOuterRightMargin)
            mockConversationView.autoPinEdge(toSuperviewEdge: .top, withInset: 24)
            mockConversationView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 24)

            return cell
        } actionBlock: {})
        contents.addSection(previewSection)

        let hueSlider = self.hueSlider
        hueSlider.delegate = self
        let hueSection = OWSTableSection()
        hueSection.hasBackground = false
        hueSection.headerTitle = NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_HUE",
                                                   comment: "Title for the 'hue' section in the chat color settings view.")
        hueSection.customHeaderHeight = 14
        hueSection.add(OWSTableItem {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(hueSlider)
            hueSlider.autoPinEdgesToSuperviewMargins()
            return cell
        } actionBlock: {})
        contents.addSection(hueSection)

        let saturationSlider = self.saturationSlider
        saturationSlider.delegate = self
        let saturationSection = OWSTableSection()
        saturationSection.hasBackground = false
        saturationSection.headerTitle = NSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_SATURATION",
                                                   comment: "Title for the 'Saturation' section in the chat color settings view.")
        saturationSection.customHeaderHeight = 14
        saturationSection.add(OWSTableItem {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(saturationSlider)
            saturationSlider.autoPinEdgesToSuperviewMargins()
            return cell
        } actionBlock: {})
        contents.addSection(saturationSection)

        self.contents = contents
    }

    func buildMockConversationMode() -> MockConversationView.Mode {
        let outgoingText = NSLocalizedString(
            "CHAT_COLOR_OUTGOING_MESSAGE",
            comment: "The outgoing bubble text when setting a chat color."
        )
        let incomingText = NSLocalizedString(
            "CHAT_COLOR_INCOMING_MESSAGE",
            comment: "The incoming bubble text when setting a chat color."
        )
        return .dateIncomingOutgoing(
            incomingText: incomingText,
            outgoingText: outgoingText
        )
    }

    // A custom spectrum that can ensures accessible constrast.
    private static let lightnessSpectrum: LightnessSpectrum = {
        var values: [LightnessValue] = [
            .init(lightness: 0.45, alpha: 0.0 / 360.0),
            .init(lightness: 0.3, alpha: 60.0 / 360.0),
            .init(lightness: 0.3, alpha: 180.0 / 360.0),
            .init(lightness: 0.5, alpha: 240.0 / 360.0),
            .init(lightness: 0.4, alpha: 300.0 / 360.0),
            .init(lightness: 0.45, alpha: 360.0 / 360.0)
        ]
        return LightnessSpectrum(values: values)
    }()

    private static func randomAlphaValue() -> CGFloat {
        let precision: UInt32 = 1024
        return (CGFloat(arc4random_uniform(precision)) / CGFloat(precision)).clamp01()
    }

    private static func buildHueSpectrum() -> HSLSpectrum {
        let lightnessSpectrum = CustomColorViewController.lightnessSpectrum
        var values = [HSLValue]()
        let precision: UInt32 = 1024
        for index in 0..<(precision + 1) {
            let alpha = (CGFloat(index) / CGFloat(precision)).clamp01()
            // There's a linear hue progression.
            let hue = alpha
            // Saturation is always 1 in the hue spectrum.
            let saturation: CGFloat = 1
            // Derive lightness.
            let lightness = lightnessSpectrum.value(forAlpha: alpha).lightness
            values.append(HSLValue(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha))
        }

        return HSLSpectrum(values: values)
    }

    private static func buildSaturationSpectrum(referenceValue: HSLValue) -> HSLSpectrum {
        var values = [HSLValue]()
        let precision: UInt32 = 1024
        for index in 0..<(precision + 1) {
            let alpha = (CGFloat(index) / CGFloat(precision)).clamp01()
            let hue = referenceValue.hue
            let saturation = alpha
            let lightness = referenceValue.lightness
            values.append(HSLValue(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha))
        }
        return HSLSpectrum(values: values)
    }

    private func updateSaturationSpectrum() {
        let hueAlpha = hueSlider.value.clamp01()
        let hueValue = self.hueSpectrum.value(forAlpha: hueAlpha)
        Logger.verbose("hue alpha: \(hueAlpha), hueValue: \(hueValue)")
        self.saturationSpectrum = Self.buildSaturationSpectrum(referenceValue: hueValue)
        self.saturationSlider.spectrum = saturationSpectrum
    }

    private func updateMockConversation() {
        // TODO: mockConversationView
    }

    // MARK: - Events

    @objc
    private func modeControlDidChange(_ sender: UISegmentedControl) {
        guard let mode = Mode(rawValue: sender.selectedSegmentIndex) else {
            owsFailDebug("Couldn't update recordType.")
            return
        }
        self.mode = mode
    }
}

// MARK: -

extension CustomColorViewController: SpectrumSliderDelegate {
    fileprivate func spectrumSliderDidChange(_ spectrumSlider: SpectrumSlider) {
        if spectrumSlider == self.hueSlider {
            Logger.verbose("hueSlider did change.")
            updateSaturationSpectrum()
        } else if spectrumSlider == self.saturationSlider {
            Logger.verbose("saturationSlider did change.")
            // Do nothing.
        } else {
            owsFailDebug("Unknown slider.")
        }

        updateMockConversation()
    }
}

// MARK: -

private protocol SpectrumSliderDelegate: class {
    func spectrumSliderDidChange(_ spectrumSlider: SpectrumSlider)
}

// MARK: -

private class SpectrumSlider: ManualLayoutView {
    fileprivate weak var delegate: SpectrumSliderDelegate?

    var spectrum: HSLSpectrum {
        didSet {
            spectrumImageView.image = nil
            ensureSpectrumImage()
        }
    }

    public var value: CGFloat

    private let knobView = ManualLayoutViewWithLayer(name: "knobView")

    private let spectrumImageView = CVImageView.circleView()

    init(spectrum: HSLSpectrum, value: CGFloat) {
        self.spectrum = spectrum
        self.value = value

        super.init(name: "SpectrumSlider")

        self.shouldDeactivateConstraints = false

        createSubviews()
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    private static let knobDiameter: CGFloat = 28
    private static let knobShadowRadius: CGFloat = 4
    private static let spectrumImageDiameter: CGFloat = 24

    private func createSubviews() {
        let spectrumImageView = self.spectrumImageView
        spectrumImageView.clipsToBounds = true
        addSubview(spectrumImageView)

        let knobView = self.knobView
        knobView.addPillBlock()
        knobView.backgroundColor = .ows_white
        knobView.layer.shadowColor = UIColor.ows_black.cgColor
        knobView.layer.shadowOffset = CGSize(width: 0, height: 2)
        knobView.layer.shadowOpacity = 0.3
        knobView.layer.shadowRadius = Self.knobShadowRadius
        addSubview(knobView) { view in
            guard let view = view as? SpectrumSlider else {
                owsFailDebug("Invalid view.")
                return
            }
//            Logger.verbose("---- view.value: \(view.value), ")
            let knobMinX: CGFloat = 0
            let knobMaxX: CGFloat = max(0, view.width - Self.knobDiameter)
            knobView.frame = CGRect(x: view.value.lerp(knobMinX, knobMaxX),
                                    y: 0,
                                    width: Self.knobDiameter,
                                    height: Self.knobDiameter)

            let inset = (Self.knobDiameter - Self.spectrumImageDiameter) * 0.5
            spectrumImageView.frame = view.bounds.inset(by: UIEdgeInsets(margin: inset))
//            spectrumImageView.addRedBorder()

            view.ensureSpectrumImage()
        }

        self.autoSetDimension(.height, toSize: Self.knobDiameter)

        addGestureRecognizer(SpectrumGestureRecognizer(target: self, action: #selector(handleGesture(_:))))
        self.isUserInteractionEnabled = true
    }

    @objc
    private func handleGesture(_ sender: SpectrumGestureRecognizer) {
        switch sender.state {
        case .began, .changed, .ended:
            let location = sender.location(in: self)
            self.value = location.x.inverseLerp(0, self.bounds.width).clamp01()
            layoutSubviews()
            self.delegate?.spectrumSliderDidChange(self)
        default:
            break
        }
    }

    private func ensureSpectrumImage() {
        let scale = UIScreen.main.scale
        let spectrumImageSizePoints = spectrumImageView.bounds.size
        let spectrumImageSizePixels = spectrumImageSizePoints * scale
        guard spectrumImageSizePixels.isNonEmpty else {
            spectrumImageView.image = nil
            return
        }
        if let spectrumImage = spectrumImageView.image,
           spectrumImage.pixelSize == spectrumImageSizePixels {
            // Image is already valid.
            return
        }

        spectrumImageView.image = nil

        UIGraphicsBeginImageContextWithOptions(spectrumImageSizePoints, false, scale)
        defer {
            UIGraphicsEndImageContext()
        }

        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: spectrumImageSizePoints))

        // We use point resolution; we could use pixel resolution.
        let xIncrement: CGFloat = 1
        var x: CGFloat = 0
        while x < spectrumImageSizePoints.width {
            let alpha = x / spectrumImageSizePoints.width
            let hslValue = spectrum.value(forAlpha: alpha)
//            Logger.verbose("---- drawing alpha: \(alpha), hue: \(hslValue.hue), saturation: \(hslValue.saturation), lightness: \(hslValue.lightness), ")
            hslValue.uiColor.setFill()
            UIRectFill(CGRect(x: x, y: 0, width: xIncrement, height: spectrumImageSizePoints.height))
            x += xIncrement
        }

//        // Draw the image into the new image
//        draw(in: CGRect(origin: CGPoint(x: additionalWidth / 2, y: 0), size: size))
//
//        // Draw the title label into the new image
//        titleLabel.drawText(in: CGRect(origin: CGPoint(
//            x: size.width > titleSize.width ? (size.width - titleSize.width) / 2 : 0,
//            y: size.height + spacing
//        ), size: titleSize))

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            owsFailDebug("Could not build image.")
            return
        }

        owsAssertDebug(image.size == spectrumImageSizePoints)
        owsAssertDebug(image.pixelSize == spectrumImageSizePixels)

        spectrumImageView.image = image
    }

    class SpectrumGestureRecognizer: UIGestureRecognizer {
        private var isActive = false

        @objc
        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            handle(event: event)
        }

        @objc
        public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            handle(event: event)
        }

        @objc
        public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            handle(event: event)
        }

        @objc
        public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            handle(event: event)
        }

        private func handle(event: UIEvent) {
            guard let allTouches = event.allTouches,
                  allTouches.count == 1,
                  let firstTouch = allTouches.first else {
                self.state = .failed
                self.isActive = false
                return
            }
            switch firstTouch.phase {
            case .began:
                if !self.isActive {
                    self.state = .began
                    self.isActive = true
                    return
                }
            case .moved, .stationary:
                if self.isActive {
                    self.state = .changed
                    self.isActive = true
                    return
                }
            case .ended:
                if self.isActive {
                    self.state = .ended
                    self.isActive = false
                    return
                }
            default:
                break
            }
            self.state = .failed
            self.isActive = false
        }
    }
}

// MARK: -

private struct LightnessValue: LerpableValue {
    let lightness: CGFloat
    let alpha: CGFloat

    init(lightness: CGFloat, alpha: CGFloat) {
        self.lightness = lightness.clamp01()
        self.alpha = alpha.clamp01()
    }

    func interpolate(_ other: LightnessValue, interpolationAlpha: CGFloat) -> LightnessValue {
        let interpolationAlpha = interpolationAlpha.clamp01()
        return LightnessValue(lightness: interpolationAlpha.lerp(lightness, other.lightness),
                              alpha: interpolationAlpha.lerp(alpha, other.alpha))
    }
}

// MARK: -

private struct LightnessSpectrum: LerpableSpectrum {
    let values: [LightnessValue]

    func interpolate(left: LightnessValue, right: LightnessValue, interpolationAlpha: CGFloat) -> LightnessValue {
        owsAssertDebug(left.alpha <= right.alpha)

        return left.interpolate(right, interpolationAlpha: interpolationAlpha)
    }
}

// MARK: -

private struct HSLValue: LerpableValue {
    let hue: CGFloat
    let saturation: CGFloat
    let lightness: CGFloat
    // This property is only used in the context of spectrums.
    // It is _NOT_ a transparency/opacity alpha.
    // It represents the values alpha within a spectrum.
    let alpha: CGFloat

    init(hue: CGFloat, saturation: CGFloat, lightness: CGFloat, alpha: CGFloat = 0) {
        self.hue = hue.clamp01()
        self.saturation = saturation.clamp01()
        self.lightness = lightness.clamp01()
        self.alpha = alpha.clamp01()
    }

    func interpolate(_ other: HSLValue, interpolationAlpha: CGFloat) -> HSLValue {
        let interpolationAlpha = interpolationAlpha.clamp01()
        return HSLValue(hue: interpolationAlpha.lerp(hue, other.hue),
                        saturation: interpolationAlpha.lerp(saturation, other.saturation),
                        lightness: interpolationAlpha.lerp(lightness, other.lightness),
                        alpha: interpolationAlpha.lerp(alpha, other.alpha))
    }

    var uiColor: UIColor {
        UIColor(hue: hue, saturation: saturation, lightness: lightness, alpha: 1)
    }

    var description: String {
        "[hue: \(hue), saturation: \(saturation), lightness: \(lightness), alpha: \(alpha)]"
    }
}

// MARK: -

private struct HSLSpectrum: LerpableSpectrum {
    let values: [HSLValue]

    func interpolate(left: HSLValue, right: HSLValue, interpolationAlpha: CGFloat) -> HSLValue {
        owsAssertDebug(left.alpha <= right.alpha)

        return left.interpolate(right, interpolationAlpha: interpolationAlpha)
    }
}

// MARK: -

private protocol LerpableValue {
    var alpha: CGFloat { get }
}

// MARK: -

private protocol LerpableSpectrum {
    associatedtype Value: LerpableValue

    var values: [Value] { get }

    func interpolate(left: Value, right: Value, interpolationAlpha: CGFloat) -> Value
}

// MARK: -

extension LerpableSpectrum {
    func value(forAlpha targetAlpha: CGFloat) -> Value {
        let values = self.values
        guard values.count > 1 else {
            owsFailDebug("Invalid values: \(values.count).")
            return values.first!
        }
        let targetAlpha = targetAlpha.clamp01()

        var leftIndex: Int = 0
        var rightIndex: Int = values.count - 1
        while true {
            guard leftIndex <= rightIndex,
                  let left = values[safe: leftIndex],
                  let right = values[safe: rightIndex] else {
                owsFailDebug("Invalid indices. leftIndex: \(leftIndex), rightIndex: \(rightIndex), values: \(values.count).")
                return values.first!
            }
            guard left.alpha <= right.alpha,
                  left.alpha <= targetAlpha,
                  right.alpha >= targetAlpha else {
                owsFailDebug("Invalid alphas. left.alpha: \(left.alpha), right.alpha: \(right.alpha), targetAlpha: \(targetAlpha).")
                return left
            }
            if leftIndex == rightIndex {
                return left
            }
            if leftIndex + 1 == rightIndex {
                owsAssertDebug(left.alpha < right.alpha)
                owsAssertDebug(left.alpha <= targetAlpha)
                owsAssertDebug(targetAlpha <= right.alpha)

                let interpolationAlpha = targetAlpha.inverseLerp(left.alpha, right.alpha, shouldClamp: true)
                return interpolate(left: left, right: right, interpolationAlpha: interpolationAlpha)
            }
            let midpointIndex = (leftIndex + rightIndex) / 2
            guard let midpoint = values[safe: midpointIndex] else {
                owsFailDebug("Invalid indices. leftIndex: \(leftIndex), rightIndex: \(rightIndex), midpointIndex: \(midpointIndex).")
                return values.first!
            }
            if midpoint.alpha < targetAlpha {
                leftIndex = midpointIndex
            } else if midpoint.alpha > targetAlpha {
                rightIndex = midpointIndex
            } else {
                return midpoint
            }
        }
    }
}

extension UIColor {
    // Convert HSL to HSB.
    convenience init(hue: CGFloat, saturation saturationHSL: CGFloat, lightness: CGFloat, alpha: CGFloat) {
        owsAssertDebug(0 <= hue)
        owsAssertDebug(1 >= hue)
        owsAssertDebug(0 <= saturationHSL)
        owsAssertDebug(1 >= saturationHSL)
        owsAssertDebug(0 <= lightness)
        owsAssertDebug(1 >= lightness)
        owsAssertDebug(0 <= alpha)
        owsAssertDebug(1 >= alpha)

        let hue = hue.clamp01()
        let saturationHSL = saturationHSL.clamp01()
        let lightness = lightness.clamp01()
        let alpha = alpha.clamp01()

        let brightness = (lightness + saturationHSL * min(lightness, 1 - lightness)).clamp01()
        let saturationHSB: CGFloat = {
            if brightness == 0 {
                return 0
            } else {
                return (2 * (1 - lightness / brightness)).clamp01()
            }
        }()

        self.init(hue: hue, saturation: saturationHSB, brightness: brightness, alpha: alpha)
    }
}
