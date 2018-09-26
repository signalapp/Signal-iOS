//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

let colorSwatchHeight: CGFloat = 40

class ColorView: UIView {
    let color: UIColor
    let swatchView: UIView

    required init(color: UIColor) {
        self.color = color
        self.swatchView = UIView()

        super.init(frame: .zero)

        swatchView.backgroundColor = color

        self.swatchView.layer.cornerRadius = colorSwatchHeight / 2

        self.addSubview(swatchView)

        swatchView.autoVCenterInSuperview()
        swatchView.autoSetDimension(.height, toSize: colorSwatchHeight)
        swatchView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        swatchView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        swatchView.autoPinLeadingToSuperviewMargin()
        swatchView.autoPinTrailingToSuperviewMargin()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
}

@objc
protocol ColorPickerDelegate: class {
    func colorPickerDidCancel(_ colorPicker: ColorPickerViewController)
    func colorPicker(_ colorPicker: ColorPickerViewController, didPickColorName colorName: String)
}

@objc
class ColorPickerViewController: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource {

    private let pickerView: UIPickerView
    private let thread: TSThread
    private let colorNames: [String]

    @objc public weak var delegate: ColorPickerDelegate?

    @objc
    required init(thread: TSThread) {
        self.thread = thread
        self.pickerView = UIPickerView()
        self.colorNames = UIColor.ows_conversationColorNames

        super.init(nibName: nil, bundle: nil)

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(didTapSave))

        pickerView.dataSource = self
        pickerView.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = Theme.backgroundColor
        view.addSubview(pickerView)

        pickerView.autoVCenterInSuperview()
        pickerView.autoPinLeadingToSuperviewMargin()
        pickerView.autoPinTrailingToSuperviewMargin()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let colorName = thread.conversationColorName,
            let index = colorNames.index(of: colorName) {
            pickerView.selectRow(index, inComponent: 0, animated: false)
        }
    }

    // MARK: UIPickerViewDataSource

    public func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }

    public func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return self.colorNames.count
    }

    // MARK: UIPickerViewDelegate

    public func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        let vMargin: CGFloat = 16
        return colorSwatchHeight + vMargin * 2
    }

    public func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        guard let colorName = colorNames[safe: row] else {
            owsFailDebug("color was unexpectedly nil")
            return ColorView(color: .white)
        }
        guard let color = UIColor.ows_conversationThemeColor(colorName: colorName) else {
            owsFailDebug("unknown color name")
            return ColorView(color: .white)
        }
        return ColorView(color: color)
    }

    // MARK: Actions

    var currentColorName: String {
        let index = pickerView.selectedRow(inComponent: 0)
        guard let colorName = colorNames[safe: index] else {
            owsFailDebug("index was unexpectedly nil")
            return UIColor.ows_defaultConversationColorName()
        }
        return colorName
    }

    @objc
    public func didTapSave() {
        let colorName = self.currentColorName
        self.delegate?.colorPicker(self, didPickColorName: colorName)
    }

    @objc
    public func didTapCancel() {
        self.delegate?.colorPickerDidCancel(self)
    }
}
