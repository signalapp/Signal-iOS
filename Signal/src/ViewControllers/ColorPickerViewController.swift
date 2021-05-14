//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class OWSColorPickerAccessoryView: NeverClearView {
    override var intrinsicContentSize: CGSize {
        return CGSize(square: kSwatchSize)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return self.intrinsicContentSize
    }

    let kSwatchSize: CGFloat = 24

    @objc
    required init(color: UIColor) {
        super.init(frame: .zero)

        let circleView = CircleView(diameter: kSwatchSize)
        circleView.backgroundColor = color
        addSubview(circleView)
        circleView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: -

protocol ColorViewDelegate: class {
    func colorViewWasTapped(_ colorView: ColorView)
}

class ColorView: UIView {
    public weak var delegate: ColorViewDelegate?
    public let conversationColor: OWSConversationColor

    private let swatchView: CircleView
    private let selectedRing: CircleView
    public var isSelected: Bool = false {
        didSet {
            self.selectedRing.isHidden = !isSelected
        }
    }

    required init(conversationColor: OWSConversationColor) {
        self.conversationColor = conversationColor
        self.swatchView = CircleView()
        self.selectedRing = CircleView()

        super.init(frame: .zero)
        self.addSubview(selectedRing)
        self.addSubview(swatchView)

        // Selected Ring
        let cellHeight: CGFloat = ScaleFromIPhone5(60)
        selectedRing.autoSetDimensions(to: CGSize(square: cellHeight))

        selectedRing.layer.borderColor = Theme.secondaryTextAndIconColor.cgColor
        selectedRing.layer.borderWidth = 2
        selectedRing.autoPinEdgesToSuperviewEdges()
        selectedRing.isHidden = true

        // Color Swatch
        swatchView.backgroundColor = conversationColor.primaryColor

        let swatchSize: CGFloat = ScaleFromIPhone5(46)
        swatchView.autoSetDimensions(to: CGSize(square: swatchSize))

        swatchView.autoCenterInSuperview()

        // gestures
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        self.addGestureRecognizer(tapGesture)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: Actions

    @objc
    func didTap() {
        delegate?.colorViewWasTapped(self)
    }
}

@objc
protocol ColorPickerDelegate: class {
    func colorPicker(_ colorPicker: ColorPicker, didPickConversationColor conversationColor: OWSConversationColor)
}

@objc(OWSColorPicker)
class ColorPicker: NSObject, ColorPickerViewDelegate {

    @objc
    public weak var delegate: ColorPickerDelegate?

    @objc
    let sheetViewController: SheetViewController

    @objc
    init(thread: TSThread) {
        let colorName = thread.conversationColorName
        let currentConversationColor = OWSConversationColor.conversationColorOrDefault(colorName: colorName)
        sheetViewController = SheetViewController()

        super.init()

        let colorPickerView = ColorPickerView(thread: thread)
        colorPickerView.delegate = self
        colorPickerView.select(conversationColor: currentConversationColor)

        sheetViewController.contentView.addSubview(colorPickerView)
        colorPickerView.autoPinEdgesToSuperviewEdges()
    }

    // MARK: ColorPickerViewDelegate

    func colorPickerView(_ colorPickerView: ColorPickerView, didPickConversationColor conversationColor: OWSConversationColor) {
        self.delegate?.colorPicker(self, didPickConversationColor: conversationColor)
    }
}

protocol ColorPickerViewDelegate: class {
    func colorPickerView(_ colorPickerView: ColorPickerView, didPickConversationColor conversationColor: OWSConversationColor)
}

class ColorPickerView: UIView, ColorViewDelegate {

    private let thread: TSThread
    private let colorViews: [ColorView]
    weak var delegate: ColorPickerViewDelegate?

    let mockConversationView = MockConversationView(
        model: MockConversationView.MockModel(items: [
            .incoming(text: NSLocalizedString(
                "COLOR_PICKER_DEMO_MESSAGE_2",
                comment: "The second of two messages demonstrating the chosen conversation color, by rendering this message in an incoming message bubble."
            )),
            .outgoing(text: NSLocalizedString(
                "COLOR_PICKER_DEMO_MESSAGE_1",
                comment: "The first of two messages demonstrating the chosen conversation color, by rendering this message in an outgoing message bubble."
            ))
        ]),
        hasWallpaper: false,
        customChatColor: nil
    )

    init(thread: TSThread) {

        self.thread = thread

        let allConversationColors = OWSConversationColor.conversationColorNames.map { OWSConversationColor.conversationColorOrDefault(colorName: $0) }

        self.colorViews = allConversationColors.map { ColorView(conversationColor: $0) }

        super.init(frame: .zero)

        mockConversationView.conversationColor = thread.conversationColorName

        colorViews.forEach { $0.delegate = self }

        let headerView = self.buildHeaderView()

        let paletteView = self.buildPaletteView(colorViews: colorViews)

        let rowsStackView = UIStackView(arrangedSubviews: [headerView, mockConversationView, paletteView])
        rowsStackView.axis = .vertical
        addSubview(rowsStackView)
        rowsStackView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: ColorViewDelegate

    func colorViewWasTapped(_ colorView: ColorView) {
        self.select(conversationColor: colorView.conversationColor)
        self.delegate?.colorPickerView(self, didPickConversationColor: colorView.conversationColor)
        mockConversationView.conversationColor = colorView.conversationColor.name
    }

    fileprivate func select(conversationColor selectedConversationColor: OWSConversationColor) {
        colorViews.forEach { colorView in
            colorView.isSelected = colorView.conversationColor == selectedConversationColor
        }
    }

    // MARK: View Building

    private func buildHeaderView() -> UIView {
        let headerView = UIView()
        headerView.layoutMargins = UIEdgeInsets(top: 15, left: 16, bottom: 15, right: 16)

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("COLOR_PICKER_SHEET_TITLE", comment: "Modal Sheet title when picking a conversation color.")
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor

        headerView.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()

        let bottomBorderView = UIView()
        bottomBorderView.backgroundColor = Theme.hairlineColor
        headerView.addSubview(bottomBorderView)
        bottomBorderView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        bottomBorderView.autoSetDimension(.height, toSize: CGHairlineWidth())

        return headerView
    }

    private func buildPaletteView(colorViews: [ColorView]) -> UIView {
        let paletteView = UIView()
        let paletteMargin = ScaleFromIPhone5(12)
        paletteView.layoutMargins = UIEdgeInsets(top: paletteMargin, left: paletteMargin, bottom: 0, right: paletteMargin)

        let kRowLength = 4
        let rows: [UIView] = colorViews.chunked(by: kRowLength).map { colorViewsInRow in
            let row = UIStackView(arrangedSubviews: colorViewsInRow)
            row.distribution = UIStackView.Distribution.equalSpacing
            return row
        }
        let rowsStackView = UIStackView(arrangedSubviews: rows)
        rowsStackView.axis = .vertical
        rowsStackView.spacing = ScaleFromIPhone5To7Plus(12, 30)

        paletteView.addSubview(rowsStackView)
        rowsStackView.autoPinEdgesToSuperviewMargins()

        // no-op gesture to keep taps from dismissing SheetView
        paletteView.addGestureRecognizer(UITapGestureRecognizer(target: nil, action: nil))
        return paletteView
    }
}
