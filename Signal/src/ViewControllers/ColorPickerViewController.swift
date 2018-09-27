//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ColorViewDelegate: class {
    func colorViewWasTapped(_ colorView: ColorView)
}

class ColorView: UIView {
    public weak var delegate: ColorViewDelegate?
    public let conversationColor: OWSConversationColor

    private let swatchView: UIView
    private let selectedRing: UIView
    public var isSelected: Bool = false {
        didSet {
            self.selectedRing.isHidden = !isSelected
        }
    }

    required init(conversationColor: OWSConversationColor) {
        self.conversationColor = conversationColor
        self.swatchView = UIView()
        self.selectedRing = UIView()

        super.init(frame: .zero)
        self.addSubview(selectedRing)
        self.addSubview(swatchView)

        let cellHeight: CGFloat = 64

        selectedRing.autoSetDimensions(to: CGSize(width: cellHeight, height: cellHeight))
        selectedRing.layer.cornerRadius = cellHeight / 2
        selectedRing.layer.borderColor = Theme.secondaryColor.cgColor
        selectedRing.layer.borderWidth = 2
        selectedRing.autoPinEdgesToSuperviewEdges()
        selectedRing.isHidden = true

        swatchView.backgroundColor = conversationColor.primaryColor
        let swatchSize: CGFloat = 48
        self.swatchView.layer.cornerRadius = swatchSize / 2
        swatchView.autoSetDimensions(to: CGSize(width: swatchSize, height: swatchSize))
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

    private let currentConversationColor: OWSConversationColor

    @objc
    init(currentConversationColor: OWSConversationColor) {
        self.currentConversationColor = currentConversationColor
        sheetViewController = SheetViewController()

        super.init()

        let colorPickerView = ColorPickerView()
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

    private let colorViews: [ColorView]
    weak var delegate: ColorPickerViewDelegate?

    override init(frame: CGRect) {
        let allConversationColors = OWSConversationColor.conversationColorNames.map { OWSConversationColor.conversationColorOrDefault(colorName: $0) }

        self.colorViews = allConversationColors.map { ColorView(conversationColor: $0) }

        super.init(frame: frame)

        colorViews.forEach { $0.delegate = self }

        let headerView = self.buildHeaderView()
        let paletteView = self.buildPaletteView(colorViews: colorViews)

        let rowsStackView = UIStackView(arrangedSubviews: [headerView, paletteView])
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
        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        titleLabel.textColor = Theme.primaryColor

        headerView.addSubview(titleLabel)
        titleLabel.ows_autoPinToSuperviewMargins()

        let bottomBorderView = UIView()
        bottomBorderView.backgroundColor = Theme.hairlineColor
        headerView.addSubview(bottomBorderView)
        bottomBorderView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        bottomBorderView.autoSetDimension(.height, toSize: CGHairlineWidth())

        return headerView
    }

    private func buildPaletteView(colorViews: [ColorView]) -> UIView {
        let paletteView = UIView()
        paletteView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let kRowLength = 4
        let rows: [UIView] = colorViews.chunked(by: kRowLength).map { colorViewsInRow in
            let row = UIStackView(arrangedSubviews: colorViewsInRow)
            row.distribution = UIStackViewDistribution.equalSpacing
            return row
        }
        let rowsStackView = UIStackView(arrangedSubviews: rows)
        rowsStackView.axis = .vertical
        rowsStackView.spacing = ScaleFromIPhone5To7Plus(16, 50)

        paletteView.addSubview(rowsStackView)
        rowsStackView.ows_autoPinToSuperviewMargins()
        return paletteView
    }
}
