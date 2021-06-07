//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit
import PromiseKit
import BonMot

class DonationViewController: OWSTableViewController2 {
    private var currencyCode = Stripe.defaultCurrencyCode {
        didSet {
            guard oldValue != currencyCode else { return }
            customValueTextField.setCurrencyCode(currencyCode)
            state = nil
            updateTableContents()
        }
    }
    private let customValueTextField = CustomValueTextField()

    private var donationAmount: NSDecimalNumber? {
        switch state {
        case .presetSelected(let amount): return NSDecimalNumber(value: amount)
        case .customValueSelected: return customValueTextField.decimalNumber
        default: return nil
        }
    }

    enum State: Equatable {
        case presetSelected(amount: UInt)
        case customValueSelected
        case donatedSuccessfully
    }
    private var state: State? {
        didSet {
            guard oldValue != state else { return }
            if oldValue == .customValueSelected { clearCustomTextField() }
            if state == .donatedSuccessfully { updateTableContents() }
            updatePresetButtonSelection()
        }
    }

    func clearCustomTextField() {
        customValueTextField.text = nil
        customValueTextField.resignFirstResponder()
    }

    override func viewDidLoad() {
        shouldAvoidKeyboard = true

        super.viewDidLoad()

        customValueTextField.placeholder = NSLocalizedString(
            "DONATION_VIEW_CUSTOM_AMOUNT_PLACEHOLDER",
            comment: "Default text for the custom amount field of the donation view."
        )
        customValueTextField.delegate = self
        customValueTextField.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "custom_amount_text_field")

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // If we're the root view, add a cancel button
        if navigationController?.viewControllers.first == self {
            navigationItem.leftBarButtonItem = .init(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(didTapDone)
            )
        }
    }

    @objc
    func didTapDone() {
        self.dismiss(animated: true)
    }

    static let bubbleBorderWidth: CGFloat = 1.5
    static let bubbleBorderColor = UIColor(rgbHex: 0xdedede)
    static var bubbleBackgroundColor: UIColor { Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white }

    func newCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        return cell
    }

    override var canBecomeFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // If we become the first responder, but the user was entering
        // a customValue, restore the first responder state to the text field.
        if result, case .customValueSelected = state {
            customValueTextField.becomeFirstResponder()
        }
        return result
    }

    var presetButtons: [UInt: UIView] = [:]
    func updatePresetButtonSelection() {
        for (amount, button) in presetButtons {
            if case .presetSelected(amount: amount) = self.state {
                button.layer.borderColor = Theme.accentBlueColor.cgColor
            } else {
                button.layer.borderColor = Self.bubbleBorderColor.cgColor
            }
        }
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer {
            self.contents = contents
            if case .customValueSelected = state { customValueTextField.becomeFirstResponder() }
        }

        let section = OWSTableSection()
        section.hasBackground = false
        contents.addSection(section)

        section.customHeaderView = {
            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 28, right: 16)

            let imageView = UIImageView()
            imageView.image = #imageLiteral(resourceName: "character-loving")
            imageView.contentMode = .scaleAspectFit
            imageView.autoSetDimension(.height, toSize: 144)
            stackView.addArrangedSubview(imageView)

            let label = UILabel()
            label.textAlignment = .center
            label.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
            label.text = NSLocalizedString(
                "DONATION_VIEW_TITLE",
                comment: "Title for the donate to signal view"
            )
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            stackView.addArrangedSubview(label)

            return stackView
        }()

        if case .donatedSuccessfully = state {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newCell()

                    let backgroundView = UIView()
                    backgroundView.backgroundColor = Self.bubbleBackgroundColor
                    backgroundView.layer.cornerRadius = 12
                    cell.insertSubview(backgroundView, belowSubview: cell.contentView)
                    backgroundView.autoPinEdgesToSuperviewMargins()

                    cell.contentView.layoutMargins = UIEdgeInsets(
                        hMargin: Self.cellHInnerMargin,
                        vMargin: 38
                    )

                    let label = UILabel()
                    label.textAlignment = .center
                    label.font = .ows_dynamicTypeBody
                    label.textColor = Theme.primaryTextColor
                    label.text = NSLocalizedString(
                        "DONATION_VIEW_THANKS_FOR_YOUR_SUPPORT",
                        comment: "Thank you message on the donate to signal view"
                    )
                    label.numberOfLines = 0
                    label.lineBreakMode = .byWordWrapping

                    cell.contentView.addSubview(label)
                    label.autoPinEdgesToSuperviewMargins()

                    return cell
                },
                actionBlock: {}
            ))
        } else {
            addApplePayItemsIfAvailable(to: section)

            // If ApplePay isn't available, show just a link to the website
            if !Self.isApplePayAvailable {
                section.add(.init(
                    customCellBlock: { [weak self] in
                        guard let self = self else { return UITableViewCell() }
                        let cell = self.newCell()

                        let donateButton = OWSFlatButton()
                        donateButton.setBackgroundColors(upColor: Theme.accentBlueColor)
                        donateButton.setTitleColor(.ows_white)
                        donateButton.setAttributedTitle(NSAttributedString.composed(of: [
                            NSLocalizedString(
                                "SETTINGS_DONATE",
                                comment: "Title for the 'donate to signal' link in settings."
                            ),
                            Special.noBreakSpace,
                            NSAttributedString.with(
                                image: #imageLiteral(resourceName: "open-20").withRenderingMode(.alwaysTemplate),
                                font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold
                            )
                        ]).styled(
                            with: .font(UIFont.ows_dynamicTypeBodyClamped.ows_semibold),
                            .color(.ows_white)
                        ))
                        donateButton.layer.cornerRadius = 12
                        donateButton.clipsToBounds = true
                        donateButton.setPressedBlock { [weak self] in
                            self?.openDonateWebsite()
                        }

                        cell.contentView.addSubview(donateButton)
                        donateButton.autoPinEdgesToSuperviewMargins()
                        donateButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)

                        return cell
                    },
                    actionBlock: {}
                ))
            }
        }

        let whySection = OWSTableSection()
        whySection.hasBackground = false
        contents.addSection(whySection)

        whySection.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let label = UILabel()
                label.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
                label.textColor = Theme.primaryTextColor
                label.text = NSLocalizedString(
                    "DONATION_VIEW_WHY_DONATE_TITLE",
                    comment: "The title of the 'Why Donate' section of the donate to signal view"
                )
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping

                cell.contentView.addSubview(label)
                label.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {}
        ))

        whySection.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let label = UILabel()
                label.font = .ows_dynamicTypeBody
                label.textColor = Theme.primaryTextColor
                label.text = NSLocalizedString(
                    "DONATION_VIEW_WHY_DONATE_BODY",
                    comment: "The body of the 'Why Donate' section of the donate to signal view"
                )
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping

                cell.contentView.addSubview(label)
                label.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {}
        ))
    }

    private let currencyFormatter: NumberFormatter = {
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .decimal
        return currencyFormatter
    }()
    private func formatCurrency(_ value: NSDecimalNumber, includeSymbol: Bool = true) -> String {
        let isZeroDecimalCurrency = Stripe.zeroDecimalCurrencyCodes.contains(currencyCode)

        let decimalPlaces: Int
        if isZeroDecimalCurrency {
            decimalPlaces = 0
        } else if value.doubleValue == Double(value.intValue) {
            decimalPlaces = 0
        } else {
            decimalPlaces = 2
        }

        currencyFormatter.minimumFractionDigits = decimalPlaces
        currencyFormatter.maximumFractionDigits = decimalPlaces

        let valueString = currencyFormatter.string(from: value) ?? value.stringValue

        guard includeSymbol else { return valueString }

        switch Presets.symbol(for: currencyCode) {
        case .before(let symbol): return symbol + valueString
        case .after(let symbol): return valueString + symbol
        case .currencyCode: return currencyCode + " " + valueString
        }
    }

    private func openDonateWebsite() {
        UIApplication.shared.open(URL(string: "https://signal.org/donate")!, options: [:], completionHandler: nil)
    }
}

// MARK: - ApplePay

extension DonationViewController: PKPaymentAuthorizationControllerDelegate {
    static var isApplePayAvailable: Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks)
    }

    static let supportedNetworks: [PKPaymentNetwork] = [
        .visa,
        .masterCard,
        .amex,
        .discover,
        .JCB,
        .interac
    ]

    func addApplePayItemsIfAvailable(to section: OWSTableSection) {
        guard Self.isApplePayAvailable else { return }

        // Currency Picker

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let stackView = UIStackView()
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = 8
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewEdges()

                let label = UILabel()
                label.font = .ows_dynamicTypeBodyClamped
                label.textColor = Theme.primaryTextColor
                label.text = NSLocalizedString(
                    "DONATION_VIEW_AMOUNT_LABEL",
                    comment: "Donation amount label for the donate to signal view"
                )
                stackView.addArrangedSubview(label)

                let picker = OWSButton { [weak self] in
                    guard let self = self else { return }
                    let vc = CurrencyPickerViewController(
                        dataSource: StripeCurrencyPickerDataSource(currentCurrencyCode: self.currencyCode)
                    ) { [weak self] currencyCode in
                        self?.currencyCode = currencyCode
                    }
                    self.navigationController?.pushViewController(vc, animated: true)
                }

                picker.setAttributedTitle(NSAttributedString.composed(of: [
                    self.currencyCode,
                    Special.noBreakSpace,
                    NSAttributedString.with(
                        image: #imageLiteral(resourceName: "chevron-down-18").withRenderingMode(.alwaysTemplate),
                        font: .ows_regularFont(withSize: 17)
                    ).styled(
                        with: .color(Self.bubbleBorderColor)
                    )
                ]).styled(
                    with: .font(.ows_regularFont(withSize: 17)),
                    .color(Theme.primaryTextColor)
                ), for: .normal)

                picker.setBackgroundImage(UIImage.init(color: Self.bubbleBackgroundColor), for: .normal)
                picker.setBackgroundImage(UIImage.init(color: Self.bubbleBackgroundColor.withAlphaComponent(0.8)), for: .highlighted)

                let pillView = PillView()
                pillView.layer.borderWidth = Self.bubbleBorderWidth
                pillView.layer.borderColor = Self.bubbleBorderColor.cgColor
                pillView.clipsToBounds = true
                pillView.addSubview(picker)
                picker.autoPinEdgesToSuperviewEdges()
                picker.autoSetDimension(.width, toSize: 74, relation: .greaterThanOrEqual)

                stackView.addArrangedSubview(pillView)
                pillView.autoSetDimension(.height, toSize: 36, relation: .greaterThanOrEqual)

                let leadingSpacer = UIView.hStretchingSpacer()
                let trailingSpacer = UIView.hStretchingSpacer()
                stackView.insertArrangedSubview(leadingSpacer, at: 0)
                stackView.addArrangedSubview(trailingSpacer)
                leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)

                return cell
            },
            actionBlock: {}
        ))

        // Preset donation options

        if let preset = Presets.presets[currencyCode] {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newCell()

                    let vStack = UIStackView()
                    vStack.axis = .vertical
                    vStack.distribution = .fillEqually
                    vStack.spacing = 16
                    cell.contentView.addSubview(vStack)
                    vStack.autoPinEdgesToSuperviewMargins()

                    self.presetButtons.removeAll()

                    for amounts in preset.amounts.chunked(by: 3) {
                        let hStack = UIStackView()
                        hStack.axis = .horizontal
                        hStack.distribution = .fillEqually
                        hStack.spacing = UIDevice.current.isIPhone5OrShorter ? 8 : 14

                        vStack.addArrangedSubview(hStack)

                        for amount in amounts {
                            let button = OWSFlatButton()
                            hStack.addArrangedSubview(button)
                            button.setBackgroundColors(
                                upColor: Self.bubbleBackgroundColor,
                                downColor: Self.bubbleBackgroundColor.withAlphaComponent(0.8)
                            )
                            button.layer.cornerRadius = 12
                            button.clipsToBounds = true
                            button.layer.borderWidth = Self.bubbleBorderWidth
                            button.setPressedBlock { [weak self] in
                                self?.state = .presetSelected(amount: amount)
                            }

                            button.setTitle(
                                title: self.formatCurrency(NSDecimalNumber(value: amount)),
                                font: .ows_regularFont(withSize: UIDevice.current.isIPhone5OrShorter ? 18 : 20),
                                titleColor: Theme.primaryTextColor
                            )

                            button.autoSetDimension(.height, toSize: 48)

                            self.presetButtons[amount] = button
                        }
                    }

                    self.updatePresetButtonSelection()

                    return cell
                },
                actionBlock: {}
            ))
        }

        // Custom donation option

        let applePayButtonIndex = IndexPath(row: section.items.count + 1, section: 0)
        let customValueTextField = self.customValueTextField
        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                customValueTextField.backgroundColor = Self.bubbleBackgroundColor
                customValueTextField.layer.cornerRadius = 12
                customValueTextField.layer.borderWidth = Self.bubbleBorderWidth
                customValueTextField.layer.borderColor = Self.bubbleBorderColor.cgColor

                customValueTextField.font = .ows_dynamicTypeBodyClamped
                customValueTextField.textColor = Theme.primaryTextColor

                cell.contentView.addSubview(customValueTextField)
                customValueTextField.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                customValueTextField.becomeFirstResponder()
                self?.tableView.scrollToRow(at: applePayButtonIndex, at: .bottom, animated: true)
            }
        ))

        // Donate with Apple Pay button

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let donateButton = PKPaymentButton(
                    paymentButtonType: .donate,
                    paymentButtonStyle: Theme.isDarkThemeEnabled ? .white : .black
                )
                if #available(iOS 12, *) { donateButton.cornerRadius = 12 }
                donateButton.addTarget(self, action: #selector(self.requestApplePayDonation), for: .touchUpInside)
                cell.contentView.addSubview(donateButton)
                donateButton.autoPinEdgesToSuperviewMargins()
                donateButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)

                return cell
            },
            actionBlock: {}
        ))

        // Other options button

        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let donateButton = OWSFlatButton()
                donateButton.setTitleColor(Theme.accentBlueColor)
                donateButton.setAttributedTitle(NSAttributedString.composed(of: [
                    NSLocalizedString(
                        "DONATION_VIEW_OTHER_WAYS",
                        comment: "Text explaining there are other ways to donate on the donation view."
                    ),
                    Special.noBreakSpace,
                    NSAttributedString.with(
                        image: #imageLiteral(resourceName: "open-20").withRenderingMode(.alwaysTemplate),
                        font: .ows_dynamicTypeBodyClamped
                    )
                ]).styled(
                    with: .font(.ows_dynamicTypeBodyClamped),
                    .color(Theme.accentBlueColor)
                ))
                donateButton.setPressedBlock { [weak self] in
                    self?.openDonateWebsite()
                }

                cell.contentView.addSubview(donateButton)
                donateButton.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {}
        ))
    }

    @objc
    func requestApplePayDonation() {
        guard let donationAmount = donationAmount else {
            presentToast(text: NSLocalizedString(
                "DONATION_VIEW_SELECT_AN_AMOUNT",
                comment: "Error text notifying the user they must select an amount on the donate to signal view"
            ), extraVInset: view.height - tableView.frame.maxY)
            return
        }

        guard !Stripe.isAmountTooSmall(donationAmount, in: currencyCode) else {
            presentToast(text: NSLocalizedString(
                "DONATION_VIEW_SELECT_A_LARGER_AMOUNT",
                comment: "Error text notifying the user they must select a large amount on the donate to signal view"
            ), extraVInset: view.height - tableView.frame.maxY)
            return
        }

        guard !Stripe.isAmountTooLarge(donationAmount, in: currencyCode) else {
            presentToast(text: NSLocalizedString(
                "DONATION_VIEW_SELECT_A_SMALLER_AMOUNT",
                comment: "Error text notifying the user they must select a smaller amount on the donate to signal view"
            ), extraVInset: view.height - tableView.frame.maxY)
            return
        }

        let request = PKPaymentRequest()
        request.paymentSummaryItems = [PKPaymentSummaryItem(
            label: NSLocalizedString(
                "DONATION_VIEW_DONATION_TO_SIGNAL",
                comment: "Text describing to the user that they're going to pay a donation to Signal"
            ),
            amount: donationAmount,
            type: .final
        )]
        request.merchantIdentifier = "merchant.org.signalfoundation"
        request.merchantCapabilities = .capability3DS
        request.countryCode = "US"
        request.currencyCode = currencyCode
        request.requiredShippingContactFields = [.emailAddress]
        request.supportedNetworks = Self.supportedNetworks

        let paymentController = PKPaymentAuthorizationController(paymentRequest: request)
        paymentController.delegate = self
        paymentController.present { presented in
            if !presented { owsFailDebug("Failed to present payment controller") }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard let donationAmount = donationAmount else {
            completion(.init(status: .failure, errors: [OWSAssertionError("Missing donation amount")]))
            return
        }
        Stripe.donate(amount: donationAmount, in: currencyCode, for: payment).done { [weak self] in
            completion(.init(status: .success, errors: nil))
            self?.state = .donatedSuccessfully
            ExperienceUpgradeManager.snoozeExperienceUpgradeWithSneakyTransaction(.donateMegaphone)
        }.catch { error in
            completion(.init(status: .failure, errors: [error]))
        }
    }
}

// MARK: -

private enum Symbol: Equatable {
    case before(String)
    case after(String)
    case currencyCode
}

private struct Presets {
    struct Preset {
        let symbol: Symbol
        let amounts: [UInt]
    }

    static let presets: [Currency.Code: Preset] = [
        "USD": Preset(symbol: .before("$"), amounts: [3, 5, 10, 20, 50, 100]),
        "AUD": Preset(symbol: .before("A$"), amounts: [5, 10, 15, 25, 65, 125]),
        "BRL": Preset(symbol: .before("R$"), amounts: [15, 25, 50, 100, 250, 525]),
        "GBP": Preset(symbol: .before("£"), amounts: [3, 5, 10, 15, 35, 70]),
        "CAD": Preset(symbol: .before("CA$"), amounts: [5, 10, 15, 25, 60, 125]),
        "CNY": Preset(symbol: .before("CN¥"), amounts: [20, 35, 65, 130, 320, 650]),
        "EUR": Preset(symbol: .before("€"), amounts: [3, 5, 10, 15, 40, 80]),
        "HKD": Preset(symbol: .before("HK$"), amounts: [25, 40, 80, 150, 400, 775]),
        "INR": Preset(symbol: .before("₹"), amounts: [100, 200, 300, 500, 1_000, 5_000]),
        "JPY": Preset(symbol: .before("¥"), amounts: [325, 550, 1_000, 2_200, 5_500, 11_000]),
        "KRW": Preset(symbol: .before("₩"), amounts: [3_500, 5_500, 11_000, 22_500, 55_500, 100_000]),
        "PLN": Preset(symbol: .after("zł"), amounts: [10, 20, 40, 75, 150, 375]),
        "SEK": Preset(symbol: .after("kr"), amounts: [25, 50, 75, 150, 400, 800]),
        "CHF": Preset(symbol: .currencyCode, amounts: [3, 5, 10, 20, 50, 100])
    ]

    static func symbol(for code: Currency.Code) -> Symbol {
        presets[code]?.symbol ?? .currencyCode
    }
}

// MARK: - CustomValueTextField

private protocol CustomValueTextFieldDelegate: AnyObject {
    func customValueTextFieldStateDidChange(_ textField: CustomValueTextField)
}

private class CustomValueTextField: UIView {
    private let placeholderLabel = UILabel()
    private let symbolLabel = UILabel()
    private let textField = UITextField()
    private let stackView = UIStackView()

    weak var delegate: CustomValueTextFieldDelegate?

    @discardableResult
    override func becomeFirstResponder() -> Bool { textField.becomeFirstResponder() }

    @discardableResult
    override func resignFirstResponder() -> Bool { textField.resignFirstResponder() }

    override var canBecomeFirstResponder: Bool { textField.canBecomeFirstResponder }
    override var canResignFirstResponder: Bool { textField.canResignFirstResponder }
    override var isFirstResponder: Bool { textField.isFirstResponder }

    init() {
        super.init(frame: .zero)
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.keyboardType = .decimalPad
        textField.textAlignment = .center
        textField.delegate = self

        symbolLabel.textAlignment = .center
        placeholderLabel.textAlignment = .center

        stackView.axis = .horizontal

        stackView.addArrangedSubview(placeholderLabel)
        stackView.addArrangedSubview(textField)

        addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        stackView.autoMatch(.width, to: .width, of: self, withMultiplier: 1, relation: .lessThanOrEqual)
        stackView.autoHCenterInSuperview()
        stackView.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)

        updateVisibility()
        setCurrencyCode(currencyCode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String? {
        set {
            textField.text = newValue
            updateVisibility()
        }
        get { textField.text }
    }

    var decimalNumber: NSDecimalNumber? {
        let number = NSDecimalNumber(string: valueString(for: text))
        guard number != NSDecimalNumber.notANumber else { return nil }
        return number
    }

    var font: UIFont? {
        set {
            textField.font = newValue
            placeholderLabel.font = newValue
            symbolLabel.font = newValue
        }
        get { textField.font }
    }

    var textColor: UIColor? {
        set {
            textField.textColor = newValue
            placeholderLabel.textColor = newValue
            symbolLabel.textColor = newValue
        }
        get { textField.textColor }
    }

    var placeholder: String? {
        set { placeholderLabel.text = newValue }
        get { placeholderLabel.text }
    }

    private lazy var symbol: Symbol = Presets.presets[currencyCode]?.symbol ?? .currencyCode
    private lazy var currencyCode = Stripe.defaultCurrencyCode

    func setCurrencyCode(_ currencyCode: Currency.Code) {
        self.symbol = Presets.symbol(for: currencyCode)
        self.currencyCode = currencyCode

        symbolLabel.removeFromSuperview()

        switch symbol {
        case .before(let symbol):
            symbolLabel.text = symbol
            stackView.insertArrangedSubview(symbolLabel, at: 0)
        case .after(let symbol):
            symbolLabel.text = symbol
            stackView.addArrangedSubview(symbolLabel)
        case .currencyCode:
            symbolLabel.text = currencyCode + " "
            stackView.insertArrangedSubview(symbolLabel, at: 0)
        }
    }

    func updateVisibility() {
        let shouldShowPlaceholder = text.isEmptyOrNil && !isFirstResponder
        placeholderLabel.isHiddenInStackView = !shouldShowPlaceholder
        symbolLabel.isHiddenInStackView = shouldShowPlaceholder
        textField.isHiddenInStackView = shouldShowPlaceholder
    }
}

extension CustomValueTextField: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateVisibility()
        delegate?.customValueTextFieldStateDidChange(self)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        updateVisibility()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn editingRange: NSRange, replacementString: String) -> Bool {
        let existingString = textField.text ?? ""

        let newString = (existingString as NSString).replacingCharacters(in: editingRange, with: replacementString)
        if let numberString = self.valueString(for: newString) {
            textField.text = numberString
            // Make a best effort to preserve cursor position
            if let newPosition = textField.position(
                from: textField.beginningOfDocument,
                offset: editingRange.location + max(0, numberString.count - existingString.count)
            ) {
                textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
            }
        } else {
            textField.text = ""
        }

        updateVisibility()
        delegate?.customValueTextFieldStateDidChange(self)

        return false
    }

    /// Converts an arbitrary string into a string representing a valid value
    /// for the current currency. If no valid value is represented, returns nil
    func valueString(for string: String?) -> String? {
        guard let string = string else { return nil }

        let isZeroDecimalCurrency = Stripe.zeroDecimalCurrencyCodes.contains(currencyCode)
        guard !isZeroDecimalCurrency else { return string.digitsOnly }

        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let components = string.components(separatedBy: decimalSeparator).compactMap { $0.digitsOnly.nilIfEmpty }

        guard let integralString = components.first else {
            if string.contains(decimalSeparator) {
                return "0" + decimalSeparator
            } else {
                return nil
            }
        }

        if let decimalString = components.dropFirst().joined().nilIfEmpty {
            return integralString + decimalSeparator + decimalString
        } else if string.starts(with: decimalSeparator) {
            return "0" + decimalSeparator + integralString
        } else if string.contains(decimalSeparator) {
            return integralString + decimalSeparator
        } else {
            return integralString
        }
    }
}

extension DonationViewController: CustomValueTextFieldDelegate {
    fileprivate func customValueTextFieldStateDidChange(_ textField: CustomValueTextField) {
        state = .customValueSelected
    }
}
