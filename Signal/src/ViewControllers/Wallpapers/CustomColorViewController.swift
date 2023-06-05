//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class CustomColorViewController: OWSTableViewController2 {

    private let thread: TSThread?

    public enum ValueMode {
        case createNew
        case editExisting(value: ChatColor)
    }
    private let valueMode: ValueMode

    private let completion: (ChatColor) -> Void

    private let modeControl = UISegmentedControl()

    fileprivate enum EditMode: Int {
        case solidColor
        case gradientColor1
        case gradientColor2
    }

    fileprivate var editMode: EditMode = .solidColor

    fileprivate class ColorSetting {
        // Represents a position within the hueSpectrum.
        var hueAlpha: CGFloat
        // Represents a position within the saturationSpectrum.
        // NOTE: the saturationSpectrum is a function of the hueAlpha.
        var saturationAlpha: CGFloat

        init(hueAlpha: CGFloat, saturationAlpha: CGFloat) {
            self.hueAlpha = hueAlpha
            self.saturationAlpha = saturationAlpha
        }
    }

    private var gradientColor1Setting = CustomColorViewController.randomColorSetting()
    // The "solid color" value is the same as the "gradient 2" color.
    private var solidOrGradientColor2Setting = CustomColorViewController.randomColorSetting()
    fileprivate var angleRadians: CGFloat = 0 {
        didSet {
            if isViewLoaded {
                updateNavigation()
            }
        }
    }

    fileprivate let hueSpectrum: HSLSpectrum
    private let hueSlider: SpectrumSlider

    private var saturationSpectrum: HSLSpectrum
    private let saturationSlider: SpectrumSlider

    public init(thread: TSThread? = nil,
                valueMode: ValueMode,
                completion: @escaping (ChatColor) -> Void) {
        self.thread = thread
        self.valueMode = valueMode
        self.completion = completion

        switch valueMode {
        case .createNew:
            editMode = .solidColor
        case .editExisting(let value):
            switch value.setting {
            case .solidColor(let color):
                editMode = .solidColor
                self.solidOrGradientColor2Setting = color.asColorSetting
            case .gradient(let gradientColor1, let gradientColor2, let angleRadians):
                editMode = .gradientColor1
                self.gradientColor1Setting = gradientColor1.asColorSetting
                self.solidOrGradientColor2Setting = gradientColor2.asColorSetting
                self.angleRadians = angleRadians
            case .themedColor, .themedGradient:
                owsFail("Case not supported by this view.")
            }
        }

        self.hueSpectrum = Self.buildHueSpectrum()
        hueSlider = SpectrumSlider(spectrum: hueSpectrum, value: 0)

        let hueAlpha = hueSlider.value.clamp01()
        let hueValue = self.hueSpectrum.value(forAlpha: hueAlpha)
        self.saturationSpectrum = Self.buildSaturationSpectrum(referenceValue: hueValue)
        saturationSlider = SpectrumSlider(spectrum: saturationSpectrum, value: 0)

        super.init()

        topHeader = OWSTableViewController2.buildTopHeader(forView: modeControl,
                                                           vMargin: 10)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .themeDidChange,
            object: nil
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_TITLE",
                                  comment: "Title for the custom chat color settings view.")

        navigationItem.rightBarButtonItem = .init(title: CommonStrings.setButton,
                                                  style: .done,
                                                  target: self,
                                                  action: #selector(didTapSet))

        createSubviews()

        updateNavigation()

        updateTableContents()
    }

    private func createSubviews() {
        modeControl.insertSegment(withTitle: OWSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_SOLID_COLOR",
                                                               comment: "Label for the 'solid color' mode in the custom chat color settings view."),
                                  at: EditMode.solidColor.rawValue,
                                  animated: false)
        modeControl.insertSegment(withTitle: OWSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_GRADIENT",
                                                               comment: "Label for the 'gradient' mode in the custom chat color settings view."),
                                  at: EditMode.gradientColor1.rawValue,
                                  animated: false)
        switch editMode {
        case .solidColor:
            modeControl.selectedSegmentIndex = EditMode.solidColor.rawValue
        case .gradientColor1, .gradientColor2:
            modeControl.selectedSegmentIndex = EditMode.gradientColor1.rawValue
        }
        modeControl.addTarget(self,
                              action: #selector(modeControlDidChange),
                              for: .valueChanged)
    }

    private var hasUnsavedChanges: Bool {
        switch valueMode {
        case .createNew:
            return true
        case .editExisting(let value):
            return currentColorOrGradientSetting() != value.setting
        }
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private enum NavigationState {
        case unknown
        case noUnsavedChanges
        case hasUnsavedChanges
    }
    private var navigationState: NavigationState = .unknown

    private func updateNavigation() {
        let navigationState: NavigationState = (hasUnsavedChanges
                                                    ? .hasUnsavedChanges
                                                    : .noUnsavedChanges)
        guard self.navigationState != navigationState else {
            return
        }
        self.navigationState = navigationState

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    private var previewView: CustomColorPreviewView?

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let previewView = CustomColorPreviewView(thread: self.thread, delegate: self)
        self.previewView = previewView

        let previewSection = OWSTableSection()
        previewSection.hasBackground = false
        previewSection.add(OWSTableItem { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            cell.contentView.addSubview(previewView)
            previewView.autoPinEdge(toSuperviewEdge: .left, withInset: self.cellHOuterLeftMargin)
            previewView.autoPinEdge(toSuperviewEdge: .right, withInset: self.cellHOuterRightMargin)
            previewView.autoPinEdge(toSuperviewEdge: .top)
            previewView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 6)
            previewView.autoPinHeightToSuperview()

            return cell
        } actionBlock: {})
        contents.add(previewSection)

        // Sliders

        let hueSlider = self.hueSlider
        let saturationSlider = self.saturationSlider

        updateSliderContent()

        hueSlider.delegate = self
        let hueSection = OWSTableSection()
        hueSection.hasBackground = false
        hueSection.customHeaderHeight = 1
        hueSection.add(self.sliderItem(
            sliderView: hueSlider,
            headerText: OWSLocalizedString(
                "CUSTOM_CHAT_COLOR_SETTINGS_HUE",
                comment: "Title for the 'hue' section in the chat color settings view."
            )
        ))
        contents.add(hueSection)

        saturationSlider.delegate = self
        let saturationSection = OWSTableSection()
        saturationSection.hasBackground = false
        saturationSection.customHeaderHeight = 1
        saturationSection.add(self.sliderItem(
            sliderView: saturationSlider,
            headerText: OWSLocalizedString(
                "CUSTOM_CHAT_COLOR_SETTINGS_SATURATION",
                comment: "Title for the 'Saturation' section in the chat color settings view."
            )
        ))
        contents.add(saturationSection)

        self.contents = contents
    }

    private func sliderItem(sliderView: UIView, headerText: String) -> OWSTableItem {
        return .init {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none

            let headerLabel = UILabel()
            headerLabel.font = UIFont.dynamicTypeSubheadline.semibold()
            headerLabel.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray15 : UIColor.ows_gray60
            headerLabel.text = headerText
            cell.contentView.addSubview(headerLabel)
            headerLabel.autoPinEdge(toSuperviewMargin: .leading, withInset: 6)
            headerLabel.autoPinEdge(toSuperviewMargin: .trailing, withInset: 6)
            headerLabel.autoPinEdge(toSuperviewMargin: .top)

            cell.contentView.addSubview(sliderView)
            sliderView.autoPinWidthToSuperviewMargins()
            sliderView.autoPinEdge(toSuperviewMargin: .bottom)
            sliderView.autoPinEdge(.top, to: .bottom, of: headerLabel, withOffset: 6)

            return cell
        }
    }

    // A custom spectrum that can ensures accessible contrast.
    private static let lightnessSpectrum: LightnessSpectrum = {
        var values: [LightnessValue] = [
            .init(lightness: 0.45, alpha: 0.0 / 360.0),
            .init(lightness: 0.4, alpha: 60.0 / 360.0),
            .init(lightness: 0.4, alpha: 180.0 / 360.0),
            .init(lightness: 0.5, alpha: 240.0 / 360.0),
            .init(lightness: 0.4, alpha: 300.0 / 360.0),
            .init(lightness: 0.45, alpha: 360.0 / 360.0)
        ]
        return LightnessSpectrum(values: values)
    }()

    private static func randomAlphaValue() -> CGFloat {
        CGFloat.random(in: 0..<1, choices: 1024).clamp01()
    }

    private static func randomColorSetting() -> ColorSetting {
        ColorSetting(hueAlpha: randomAlphaValue(), saturationAlpha: randomAlphaValue())
    }

    private static func buildHueSpectrum() -> HSLSpectrum {
        let lightnessSpectrum = CustomColorViewController.lightnessSpectrum
        var values = [HSLValue]()
        // This lightness spectrum is non-linear.
        // The hue spectrum is non-linear to exactly the same extent.
        // Therefore the hue spectrum only needs as many values
        // as the lightness spectrum.
        for lightnessValue in lightnessSpectrum.values {
            let alpha = lightnessValue.alpha.clamp01()
            // There's a linear hue progression.
            let hue = alpha
            // Saturation is always 1 in the hue spectrum.
            let saturation: CGFloat = 1
            // Derive lightness.
            let lightness = lightnessValue.lightness
            values.append(HSLValue(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha))
        }
        return HSLSpectrum(values: values)
    }

    private static func buildSaturationSpectrum(referenceValue: HSLValue) -> HSLSpectrum {
        var values = [HSLValue]()
        // This spectrum is linear, so we only need 2 endpoint values.
        let precision: UInt32 = 1
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
        self.saturationSpectrum = Self.buildSaturationSpectrum(referenceValue: hueValue)
        self.saturationSlider.spectrum = saturationSpectrum
    }

    private func updateSliderContent() {
        // Update sliders to reflect editMode.
        func apply(colorSetting: ColorSetting) {
            hueSlider.value = colorSetting.hueAlpha
            saturationSlider.value = colorSetting.saturationAlpha

            // Update saturation slider to reflect hue slider state.
            updateSaturationSpectrum()
        }
        switch editMode {
        case .solidColor:
            apply(colorSetting: self.solidOrGradientColor2Setting)
        case .gradientColor1:
            apply(colorSetting: self.gradientColor1Setting)
        case .gradientColor2:
            apply(colorSetting: self.solidOrGradientColor2Setting)
        }
    }

    private func updateMockConversation(isDebounced: Bool) {
        previewView?.updateMockConversation(isDebounced: isDebounced)
    }

    // MARK: - Events

    @objc
    private func modeControlDidChange(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case EditMode.solidColor.rawValue:
            self.editMode = .solidColor
        case EditMode.gradientColor1.rawValue, EditMode.gradientColor2.rawValue:
            self.editMode = .gradientColor2
        default:
            owsFailDebug("Couldn't update editMode.")
        }
        updateTableContents()
        updateNavigation()
    }

    fileprivate var gradientColor1: OWSColor {
        gradientColor1Setting.asOWSColor(hueSpectrum: hueSpectrum)
    }

    fileprivate var gradientColor2: OWSColor {
        solidOrGradientColor2Setting.asOWSColor(hueSpectrum: hueSpectrum)
    }

    private func currentColorOrGradientSetting() -> ColorOrGradientSetting {
        switch editMode {
        case .solidColor:
            let solidColor = self.solidOrGradientColor2Setting.asOWSColor(hueSpectrum: hueSpectrum)
            return .solidColor(color: solidColor)
        case .gradientColor1, .gradientColor2:
            return .gradient(gradientColor1: gradientColor1,
                             gradientColor2: gradientColor2,
                             angleRadians: self.angleRadians)
        }
    }

    fileprivate var currentChatColor: ChatColor {
        let setting = self.currentColorOrGradientSetting()
        switch valueMode {
        case .createNew:
            return ChatColor(id: ChatColor.randomId, setting: setting)
        case .editExisting(let oldValue):
            // Preserve the old id and creationTimestamp.
            return ChatColor(id: oldValue.id,
                             setting: setting,
                             creationTimestamp: oldValue.creationTimestamp)
        }
    }

    fileprivate func hasWallpaper(transaction: SDSAnyReadTransaction) -> Bool {
        nil != Wallpaper.wallpaperForRendering(for: self.thread, transaction: transaction)
    }

    private func showSaveUI() {
        let newValue = self.currentChatColor

        switch valueMode {
        case .createNew:
            saveAndDismiss()
            return
        case .editExisting(let oldValue):
            guard oldValue != newValue else {
                saveAndDismiss()
                return
            }
        }

        let usageCount = databaseStorage.read { transaction in
            ChatColors.usageCount(forValue: newValue, transaction: transaction)
        }
        guard usageCount > 1 else {
            saveAndDismiss()
            return
        }

        let messageFormat = OWSLocalizedString("CHAT_COLOR_SETTINGS_UPDATE_ALERT_MESSAGE_%d", tableName: "PluralAware",
                                              comment: "Message for the 'edit chat color confirm alert' in the chat color settings view. Embeds: {{ the number of conversations that use this chat color }}.")
        let message = String.localizedStringWithFormat(messageFormat, usageCount)
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("CHAT_COLOR_SETTINGS_UPDATE_ALERT_ALERT_TITLE",
                                     comment: "Title for the 'edit chat color confirm alert' in the chat color settings view."),
            message: message
        )

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.saveButton
        ) { [weak self] _ in
            self?.saveAndDismiss()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }
    private func saveAndDismiss() {
        let newValue = self.currentChatColor
        completion(newValue)
        self.navigationController?.popViewController(animated: true)
    }

    private func dismissWithoutSaving() {
        self.navigationController?.popViewController(animated: true)
    }

    @objc
    private func didTapSet() {
        showSaveUI()
    }

    @objc
    private func didTapCancel() {
        guard hasUnsavedChanges else {
            dismissWithoutSaving()
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismissWithoutSaving()
        })
    }

    @objc
    private func didTapDone() {
        showSaveUI()
    }
}

// MARK: -

extension CustomColorViewController: SpectrumSliderDelegate {
    fileprivate func spectrumSliderDidChange(_ spectrumSlider: SpectrumSlider) {
        let currentColorSetting: ColorSetting
        switch editMode {
        case .solidColor:
            currentColorSetting = self.solidOrGradientColor2Setting
        case .gradientColor1:
            currentColorSetting = self.gradientColor1Setting
        case .gradientColor2:
            currentColorSetting = self.solidOrGradientColor2Setting
        }

        if spectrumSlider == self.hueSlider {
            Logger.verbose("hueSlider did change.")
            currentColorSetting.hueAlpha = hueSlider.value.clamp01()
            updateSaturationSpectrum()
        } else if spectrumSlider == self.saturationSlider {
            Logger.verbose("saturationSlider did change.")
            currentColorSetting.saturationAlpha = saturationSlider.value.clamp01()
        } else {
            owsFailDebug("Unknown slider.")
        }

        updateMockConversation(isDebounced: true)
        updateNavigation()
    }
}

// MARK: -

private protocol SpectrumSliderDelegate: AnyObject {
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

    public var value: CGFloat {
        didSet {
            setNeedsLayout()
        }
    }

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
            let knobMinX: CGFloat = 0
            let knobMaxX: CGFloat = max(0, view.width - Self.knobDiameter)
            knobView.frame = CGRect(x: view.value.lerp(knobMinX, knobMaxX),
                                    y: 0,
                                    width: Self.knobDiameter,
                                    height: Self.knobDiameter)

            let inset = (Self.knobDiameter - Self.spectrumImageDiameter) * 0.5
            spectrumImageView.frame = view.bounds.inset(by: UIEdgeInsets(margin: inset))

            view.ensureSpectrumImage()
        }

        self.autoSetDimension(.height, toSize: Self.knobDiameter)

        addGestureRecognizer(CustomColorGestureRecognizer(target: self, action: #selector(handleGesture(_:))))
        self.isUserInteractionEnabled = true
    }

    @objc
    private func handleGesture(_ sender: CustomColorGestureRecognizer) {
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
            hslValue.asUIColor.setFill()
            UIRectFill(CGRect(x: x, y: 0, width: xIncrement, height: spectrumImageSizePoints.height))
            x += xIncrement
        }

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            owsFailDebug("Could not build image.")
            return
        }

        owsAssertDebug(image.size == spectrumImageSizePoints)
        owsAssertDebug(image.pixelSize == spectrumImageSizePixels)

        spectrumImageView.image = image
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

    var asUIColor: UIColor {
        UIColor(hue: hue, saturation: saturation, lightness: lightness, alpha: 1)
    }

    var asOWSColor: OWSColor {
        self.asUIColor.asOWSColor
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

// MARK: -

extension OWSColor {
    fileprivate var asColorSetting: CustomColorViewController.ColorSetting {
        let uiColor = self.asUIColor

        var hue: CGFloat = 0
        var saturationHSB: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturationHSB, brightness: &brightness, alpha: &alpha)

        hue = hue.clamp01()
        saturationHSB = saturationHSB.clamp01()
        brightness = brightness.clamp01()

        // Convert HSB to HSL.

        let lightness = (2 - saturationHSB) * brightness / 2

        let saturationHSL: CGFloat
        if lightness == 0 {
            saturationHSL = saturationHSB
        } else if lightness == 1 {
            saturationHSL = 0
        } else if lightness < 0.5 {
            saturationHSL = (saturationHSB * brightness / (lightness * 2)).clamp01()
        } else {
            saturationHSL = (saturationHSB * brightness / (2 - lightness * 2)).clamp01()
        }

        return CustomColorViewController.ColorSetting(hueAlpha: hue, saturationAlpha: saturationHSL)
    }
}

// MARK: -

extension CustomColorViewController.ColorSetting {
    func asOWSColor(hueSpectrum: HSLSpectrum) -> OWSColor {
        let hueValue = hueSpectrum.value(forAlpha: self.hueAlpha)
        let saturationSpectrum = CustomColorViewController.buildSaturationSpectrum(referenceValue: hueValue)
        let saturationValue = saturationSpectrum.value(forAlpha: self.saturationAlpha)
        return saturationValue.asOWSColor
    }
}

// MARK: -

extension CustomColorViewController: CustomColorPreviewDelegate {
    fileprivate func switchToEditMode(_ value: CustomColorViewController.EditMode) {
        guard self.editMode != value else {
            return
        }
        self.editMode = value
        updateSliderContent()
    }

    var previewWidth: CGFloat {
        self.view.width - cellOuterInsets.totalWidth
    }
}

// MARK: -

private protocol CustomColorPreviewDelegate: AnyObject {
    var angleRadians: CGFloat { get set }
    var editMode: CustomColorViewController.EditMode { get }
    var gradientColor1: OWSColor { get }
    var gradientColor2: OWSColor { get }

    var currentChatColor: ChatColor { get }
    func hasWallpaper(transaction: SDSAnyReadTransaction) -> Bool

    func switchToEditMode(_ value: CustomColorViewController.EditMode)

    var previewWidth: CGFloat { get }
}

// MARK: -

private class CustomColorPreviewView: UIView {
    private let mockConversationView: MockConversationView

    private weak var delegate: CustomColorPreviewDelegate?

    public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                viewSizeDidChange()
            }
        }
    }

    public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                viewSizeDidChange()
            }
        }
    }

    private func viewSizeDidChange() {
        updateKnobLayout()
    }

    init(thread: TSThread?, delegate: CustomColorPreviewDelegate) {

        let (mockConversationView, wallpaperPreviewView) = Self.databaseStorage.read { transaction -> (MockConversationView, UIView) in
            let mockConversationView =
                MockConversationView(
                    model: CustomColorPreviewView.buildMockConversationModel(),
                    hasWallpaper: delegate.hasWallpaper(transaction: transaction),
                    customChatColor: delegate.currentChatColor
                )

            let wallpaperPreviewView: UIView
            if let wallpaperView = Wallpaper.view(for: thread, transaction: transaction) {
                wallpaperPreviewView = wallpaperView.asPreviewView()
            } else {
                wallpaperPreviewView = UIView()
                wallpaperPreviewView.backgroundColor = Theme.backgroundColor
            }

            return (mockConversationView, wallpaperPreviewView)
        }

        self.mockConversationView = mockConversationView

        self.delegate = delegate

        super.init(frame: .zero)

        wallpaperPreviewView.layer.cornerRadius = OWSTableViewController2.cellRounding
        wallpaperPreviewView.clipsToBounds = true

        wallpaperPreviewView.setContentHuggingLow()
        wallpaperPreviewView.setCompressionResistanceLow()
        self.addSubview(wallpaperPreviewView)
        wallpaperPreviewView.autoPinEdgesToSuperviewEdges()

        mockConversationView.delegate = self
        mockConversationView.setContentHuggingVerticalHigh()
        mockConversationView.setCompressionResistanceVerticalHigh()
        self.addSubview(mockConversationView)
        mockConversationView.autoPinWidthToSuperview()
        mockConversationView.autoPinEdge(toSuperviewEdge: .top, withInset: 32)
        mockConversationView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 32)

        ensureControlState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate lazy var updateMockConversationEvent = {
        DebouncedEvents.build(mode: .lastOnly,
                              maxFrequencySeconds: 0.05,
                              onQueue: .asyncOnQueue(queue: .main)) { [weak self] in
            self?._updateMockConversation()
        }
    }()

    fileprivate func updateMockConversation(isDebounced: Bool) {
        if isDebounced {
            updateMockConversationEvent.requestNotify()
        } else {
            self._updateMockConversation()
        }
    }

    private func _updateMockConversation() {
        guard let delegate = delegate else { return }

        mockConversationView.customChatColor = delegate.currentChatColor

        if let knobView1 = self.knobView1 {
            knobView1.setChatColor(ChatColor(id: "knob1",
                                             setting: .solidColor(color: delegate.gradientColor1)))
        }
        if let knobView2 = self.knobView2 {
            knobView2.setChatColor(ChatColor(id: "knob2",
                                             setting: .solidColor(color: delegate.gradientColor2)))
        }
    }

    private class KnobView: UIView {

        static let swatchSize: CGFloat = 44
        static let selectedBorderThickness: CGFloat = 4
        static let unselectedBorderThickness: CGFloat = 1
        static var knobSize: CGFloat { swatchSize + selectedBorderThickness * 2 }

        var isSelected: Bool {
            didSet {
                updateSelection()
            }
        }

        func setChatColor(_ value: ChatColor) {
            swatchView.setting = value.setting
        }

        private let selectedBorder = OWSLayerView.circleView()
        private let unselectedBorder = OWSLayerView.circleView()

        private let swatchView: ColorOrGradientSwatchView

        init(isSelected: Bool, chatColor: ChatColor, name: String? = nil) {
            self.isSelected = isSelected
            self.swatchView = ColorOrGradientSwatchView(setting: chatColor.setting, shapeMode: .circle)

            super.init(frame: .zero)

            self.translatesAutoresizingMaskIntoConstraints = false
            self.autoSetDimensions(to: .square(Self.knobSize))

            swatchView.layer.borderColor = UIColor.ows_white.cgColor
            swatchView.layer.shadowColor = UIColor.ows_black.cgColor
            swatchView.layer.shadowOffset = CGSize(width: 0, height: 2)
            swatchView.layer.shadowOpacity = 0.3
            swatchView.layer.shadowRadius = 4
            swatchView.autoSetDimensions(to: .square(Self.swatchSize))
            self.addSubview(swatchView)
            swatchView.autoCenterInSuperview()

            let selectedColor = (Theme.isDarkThemeEnabled
                                    ? UIColor.ows_white
                                    : UIColor(white: 0, alpha: 0.6))
            selectedBorder.layer.borderColor = selectedColor.cgColor
            selectedBorder.layer.borderWidth = Self.selectedBorderThickness
            selectedBorder.autoSetDimensions(to: .square(Self.swatchSize + Self.selectedBorderThickness * 2))
            self.addSubview(selectedBorder)
            selectedBorder.autoCenterInSuperview()

            unselectedBorder.layer.borderColor = UIColor(white: 0, alpha: 0.1).cgColor
            unselectedBorder.layer.borderWidth = Self.unselectedBorderThickness
            unselectedBorder.autoSetDimensions(to: .square(Self.swatchSize + Self.unselectedBorderThickness * 2))
            self.addSubview(unselectedBorder)
            unselectedBorder.autoCenterInSuperview()

            if Self.showKnobLabels, let name = name {
                let label = UILabel()
                label.text = name
                label.font = .dynamicTypeCaption1
                label.textColor = .ows_white
                self.addSubview(label)
                label.autoCenterInSuperview()
            }

            updateSelection()
        }

        private static let showKnobLabels = false

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateSelection() {
            selectedBorder.isHidden = !isSelected
            unselectedBorder.isHidden = isSelected
            swatchView.layer.borderWidth = isSelected ? 1 : 2
        }
    }

    private var knobView1: KnobView?
    private var knobView2: KnobView?
    private var axisShapeView: UIView?
    private var axisShapeLayer: CAShapeLayer?

    private var knobView1ConstraintX: NSLayoutConstraint?
    private var knobView1ConstraintY: NSLayoutConstraint?
    private var knobView2ConstraintX: NSLayoutConstraint?
    private var knobView2ConstraintY: NSLayoutConstraint?

    private func ensureControlState() {
        guard let delegate = delegate else { return }

        switch delegate.editMode {
        case .solidColor:
            return
        case .gradientColor1, .gradientColor2:
            break
        }

        let axisShapeView = UIView()
        self.axisShapeView = axisShapeView
        addSubview(axisShapeView)
        axisShapeView.autoPinEdgesToSuperviewEdges()
        let axisShapeLayer = CAShapeLayer()
        self.axisShapeLayer = axisShapeLayer
        axisShapeView.layer.addSublayer(axisShapeLayer)

        let knobView1 = KnobView(isSelected: delegate.editMode == .gradientColor1,
                                 chatColor: ChatColor(id: "knob1",
                                                      setting: .solidColor(color: delegate.gradientColor1)),
                                 name: "1")
        let knobView2 = KnobView(isSelected: delegate.editMode == .gradientColor2,
                                 chatColor: ChatColor(id: "knob2",
                                                      setting: .solidColor(color: delegate.gradientColor2)),
                                 name: "2")
        self.knobView1 = knobView1
        self.knobView2 = knobView2

        addSubview(knobView1)
        addSubview(knobView2)

        knobView1ConstraintX = NSLayoutConstraint(item: knobView1,
                                                  attribute: .centerX,
                                                  relatedBy: .equal,
                                                  toItem: self,
                                                  attribute: .centerX,
                                                  multiplier: 1,
                                                  constant: 0)
        knobView1ConstraintY = NSLayoutConstraint(item: knobView1,
                                                  attribute: .centerY,
                                                  relatedBy: .equal,
                                                  toItem: self,
                                                  attribute: .centerY,
                                                  multiplier: 1,
                                                  constant: 0)
        knobView2ConstraintX = NSLayoutConstraint(item: knobView2,
                                                  attribute: .centerX,
                                                  relatedBy: .equal,
                                                  toItem: self,
                                                  attribute: .centerX,
                                                  multiplier: 1,
                                                  constant: 0)
        knobView2ConstraintY = NSLayoutConstraint(item: knobView2,
                                                  attribute: .centerY,
                                                  relatedBy: .equal,
                                                  toItem: self,
                                                  attribute: .centerY,
                                                  multiplier: 1,
                                                  constant: 0)
        knobView1ConstraintX?.autoInstall()
        knobView1ConstraintY?.autoInstall()
        knobView2ConstraintX?.autoInstall()
        knobView2ConstraintY?.autoInstall()

        updateKnobLayout()

        addGestureRecognizer(CustomColorGestureRecognizer(target: self, action: #selector(handleGesture(_:))))
        self.isUserInteractionEnabled = true

        DispatchQueue.main.async { [weak self] in
            self?.ensureTooltip()
        }
    }

    private enum GestureMode {
        case none
        case knob1
        case knob2
    }

    private var gestureMode: GestureMode = .none

    @objc
    private func handleGesture(_ sender: CustomColorGestureRecognizer) {
        switch sender.state {
        case .began, .changed, .ended:
            guard let delegate = self.delegate,
                  let knobView1 = self.knobView1,
                  let knobView2 = self.knobView2 else {
                gestureMode = .none
                return
            }
            let touchLocation = sender.location(in: self)

            if sender.state == .began {
                // Only "grab" a knob if the gesture starts near a knob.
                let knobDistance1 = knobView1.frame.center.distance(touchLocation)
                let knobDistance2 = knobView2.frame.center.distance(touchLocation)
                let minFirstTouchDistance = KnobView.knobSize * 2
                if knobDistance1 < minFirstTouchDistance,
                   knobDistance2 < minFirstTouchDistance {
                    if knobDistance1 < knobDistance2 {
                        gestureMode = .knob1
                    } else {
                        gestureMode = .knob2
                    }
                } else if knobDistance1 < minFirstTouchDistance {
                    gestureMode = .knob1
                } else if knobDistance2 < minFirstTouchDistance {
                    gestureMode = .knob2
                } else {
                    gestureMode = .none
                    return
                }
            }

            delegate.switchToEditMode(gestureMode == .knob1
                                        ? .gradientColor1
                                        : .gradientColor2)
            knobView1.isSelected = gestureMode == .knob1
            knobView2.isSelected = gestureMode == .knob2

            let viewCenter = self.bounds.center
            var touchVector = touchLocation - viewCenter
            // Note the signs.
            touchVector = CGPoint(x: +touchVector.x, y: -touchVector.y)

            switch gestureMode {
            case .knob1:
                break
            case .knob2:
                // To simplify the math, pretend we're manipulating the first knob
                // by inverting the vector.
                touchVector *= -1
            case .none:
                return
            }

            let angleRadians = atan2(touchVector.x, touchVector.y)
            delegate.angleRadians = angleRadians
            updateKnobLayout()
            updateMockConversation(isDebounced: true)
            dismissTooltip()
        default:
            gestureMode = .none
        }
    }

    private func updateKnobLayout() {
        guard let delegate = self.delegate,
              let knobView1ConstraintX = self.knobView1ConstraintX,
              let knobView1ConstraintY = self.knobView1ConstraintY,
              let knobView2ConstraintX = self.knobView2ConstraintX,
              let knobView2ConstraintY = self.knobView2ConstraintY,
              let axisShapeLayer = self.axisShapeLayer else {
            return
        }

        let knobInset: CGFloat = 20
        let knobRect = self.bounds.inset(by: UIEdgeInsets(margin: knobInset))
        guard knobRect.size.width > 0,
              knobRect.size.height > 0 else {
            return
        }

        let angleRadians = delegate.angleRadians
        // Note the signs.
        let unitVector = CGPoint(x: +sin(angleRadians), y: -cos(angleRadians))
        let oversizeVector = unitVector * knobRect.size.largerAxis
        let scaleFactorX = (knobRect.size.width / 2) / abs(oversizeVector.x)
        let scaleFactorY = (knobRect.size.height / 2) / abs(oversizeVector.y)
        let scaleFactor: CGFloat
        if abs(oversizeVector.x) > 0,
           abs(oversizeVector.y) > 0 {
            scaleFactor = min(scaleFactorX, scaleFactorY)
        } else if abs(oversizeVector.x) > 0 {
            scaleFactor = scaleFactorX
        } else if abs(oversizeVector.y) > 0 {
            scaleFactor = scaleFactorY
        } else {
            owsFailDebug("Invalid vector state.")
            scaleFactor = 1
        }
        let vector1 = oversizeVector * +scaleFactor
        // Knob 2 is always opposite knob 1.
        let vector2 = vector1 * -1

        knobView1ConstraintX.constant = vector1.x
        knobView1ConstraintY.constant = vector1.y
        knobView2ConstraintX.constant = vector2.x
        knobView2ConstraintY.constant = vector2.y

        axisShapeLayer.frame = self.bounds
        axisShapeLayer.fillColor = UIColor.ows_white.cgColor
        axisShapeLayer.strokeColor = UIColor(white: 0, alpha: 0.1).cgColor
        let axisPath = UIBezierPath()
        let knobCenter1 = self.bounds.center + vector1
        let knobCenter2 = self.bounds.center + vector2
        let axisVector = knobCenter2 - knobCenter1
        if axisVector.length > 0 {
            // We want to draw the "axis" of the gradient.
            // This is a bar between the two "knobs" which
            // represent the 2 gradient control points.
            //
            // P2                            P3
            //
            // K1 ...........................K2
            //
            // P1                            P4
            //
            // We do this by deriving an "offset vector".
            // We rotate the axis vector 90 degrees.
            var offAxisVector = CGPoint(x: axisVector.y, y: -axisVector.x)
            let axisThickness: CGFloat = 8
            // Then scale it to half the thickness of the axis.
            offAxisVector *= axisThickness * 0.5 / offAxisVector.length

            // By adding the "offset vector" to the two knob locations,
            // we derive the corners of the axis.
            let p1 = knobCenter1 + offAxisVector
            let p2 = knobCenter1 - offAxisVector
            let p3 = knobCenter2 - offAxisVector
            let p4 = knobCenter2 + offAxisVector

            axisPath.move(to: p1)
            axisPath.addLine(to: p2)
            axisPath.addLine(to: p3)
            axisPath.addLine(to: p4)
            axisPath.addLine(to: p1)
        }
        axisShapeLayer.path = axisPath.cgPath
    }

    private static func buildMockConversationModel() -> MockConversationView.MockModel {
        MockConversationView.MockModel(items: [
            .date,
            .incoming(text: OWSLocalizedString(
                "CHAT_COLOR_INCOMING_MESSAGE_1",
                comment: "The first incoming bubble text when setting a chat color."
            )),
            .outgoing(text: OWSLocalizedString(
                "CHAT_COLOR_OUTGOING_MESSAGE_1",
                comment: "The first outgoing bubble text when setting a chat color."
            )),
            .incoming(text: OWSLocalizedString(
                "CHAT_COLOR_INCOMING_MESSAGE_2",
                comment: "The second incoming bubble text when setting a chat color."
            )),
            .outgoing(text: OWSLocalizedString(
                "CHAT_COLOR_OUTGOING_MESSAGE_2",
                comment: "The second outgoing bubble text when setting a chat color."
            ))
        ])
    }

    // MARK: - Tooltip

    private static let keyValueStore = SDSKeyValueStore(collection: "CustomColorPreviewView")
    private static let tooltipWasDismissedKey = "tooltipWasDismissed"

    private var customColorTooltip: CustomColorTooltip?

    fileprivate func dismissTooltip() {
        databaseStorage.write { transaction in
            Self.keyValueStore.setBool(true, key: Self.tooltipWasDismissedKey, transaction: transaction)
        }
        hideTooltip()
    }

    private func hideTooltip() {
        customColorTooltip?.removeFromSuperview()
        customColorTooltip = nil
    }

    private func ensureTooltip() {
        let shouldShowTooltip = databaseStorage.read { transaction in
            !Self.keyValueStore.getBool(Self.tooltipWasDismissedKey, defaultValue: false, transaction: transaction)
        }
        let isShowingTooltip = customColorTooltip != nil
        guard shouldShowTooltip != isShowingTooltip else {
            return
        }
        if nil != self.customColorTooltip {
            hideTooltip()
        } else {
            guard let knobView1 = knobView1,
                  let knobView2 = knobView2 else {
                hideTooltip()
                return
            }
            let knobView = (knobView1.frame.y < knobView2.frame.y
                                ? knobView1
                                : knobView2)
            self.customColorTooltip = CustomColorTooltip.present(fromView: self,
                                                                 widthReferenceView: self,
                                                                 tailReferenceView: knobView) { [weak self] in
                self?.dismissTooltip()
            }
        }
    }
}

// MARK: -

class CustomColorGestureRecognizer: UIGestureRecognizer {
    private var isActive = false

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

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
            guard let view = self.view,
                  view.bounds.contains(firstTouch.location(in: view)) else {
                self.state = .failed
                self.isActive = false
                return
            }
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

// MARK: -

extension CustomColorPreviewView: MockConversationDelegate {
    var mockConversationViewWidth: CGFloat { delegate?.previewWidth ?? 0 }
}

// MARK: -

private class CustomColorTooltip: TooltipView {

    private override init(fromView: UIView,
                          widthReferenceView: UIView,
                          tailReferenceView: UIView,
                          wasTappedBlock: (() -> Void)?) {
        super.init(fromView: fromView,
                   widthReferenceView: widthReferenceView,
                   tailReferenceView: tailReferenceView,
                   wasTappedBlock: wasTappedBlock)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public class func present(fromView: UIView,
                              widthReferenceView: UIView,
                              tailReferenceView: UIView,
                              wasTappedBlock: (() -> Void)?) -> CustomColorTooltip {
        return CustomColorTooltip(fromView: fromView,
                                  widthReferenceView: widthReferenceView,
                                  tailReferenceView: tailReferenceView,
                                  wasTappedBlock: wasTappedBlock)
    }

    public override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString("CUSTOM_CHAT_COLOR_SETTINGS_TOOLTIP",
                                       comment: "Tooltip highlighting the custom chat color controls.")
        label.font = .dynamicTypeSubheadline
        label.textColor = .ows_white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return horizontalStack(forSubviews: [label])
    }

    public override var bubbleColor: UIColor {
        .ows_accentBlue
    }

    public override var tailDirection: TooltipView.TailDirection {
        .up
    }

    public override var bubbleInsets: UIEdgeInsets {
        UIEdgeInsets(hMargin: 12, vMargin: 7)
    }

    public override var bubbleHSpacing: CGFloat {
        10
    }
}
