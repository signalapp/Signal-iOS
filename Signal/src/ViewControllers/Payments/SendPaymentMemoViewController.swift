//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public protocol SendPaymentMemoViewDelegate: AnyObject {
    func didChangeMemo(memoMessage: String?)
}

// MARK: -

public class SendPaymentMemoViewController: OWSViewController {

    public weak var delegate: SendPaymentMemoViewDelegate?

    private let rootStack = UIStackView()

    private let memoTextField = UITextField()
    private let memoCharacterCountLabel = UILabel()

    public init(memoMessage: String?) {
        super.init()

        memoTextField.text = memoMessage
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_ADD_MEMO",
            comment: "Label for the 'add memo' ui in the 'send payment' UI.",
        )
        navigationItem.leftBarButtonItem = .cancelButton(poppingFrom: navigationController)
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.didTapDoneMemo()
        }

        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -16),
        ])

        updateContents()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        memoTextField.becomeFirstResponder()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        memoTextField.becomeFirstResponder()
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    private func updateContents() {
        AssertIsOnMainThread()

        rootStack.removeAllSubviews()

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        memoTextField.backgroundColor = .clear
        memoTextField.font = .dynamicTypeBodyClamped
        memoTextField.textColor = Theme.primaryTextColor
        let placeholder = NSAttributedString(
            string: OWSLocalizedString(
                "PAYMENTS_NEW_PAYMENT_MESSAGE_PLACEHOLDER",
                comment: "Placeholder for the new payment or payment request message.",
            ),
            attributes: [
                .foregroundColor: Theme.secondaryTextAndIconColor,
            ],
        )
        memoTextField.attributedPlaceholder = placeholder
        memoTextField.delegate = self
        memoTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        memoCharacterCountLabel.font = .dynamicTypeBodyClamped
        memoCharacterCountLabel.textColor = .Signal.tertiaryLabel

        memoCharacterCountLabel.setCompressionResistanceHorizontalHigh()
        memoCharacterCountLabel.setContentHuggingHorizontalHigh()

        let memoRow = UIStackView(arrangedSubviews: [
            memoTextField,
            memoCharacterCountLabel,
        ])
        memoRow.axis = .horizontal
        memoRow.spacing = 8
        memoRow.alignment = .center
        memoRow.isLayoutMarginsRelativeArrangement = true
        memoRow.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 14)
        let backgroundColor = OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true)
        let backgroundView = memoRow.addBackgroundView(withBackgroundColor: backgroundColor)
        backgroundView.layer.cornerRadius = 10

        updateMemoCharacterCount()

        rootStack.addArrangedSubviews([
            UIView.spacer(withHeight: SendPaymentHelper.minTopVSpacing),
            memoRow,
            UIView.vStretchingSpacer(),
        ])
    }

    override public func themeDidChange() {
        super.themeDidChange()

        updateContents()
    }

    // MARK: -

    fileprivate func updateMemoCharacterCount() {
        guard
            let strippedMemoMessage = memoTextField.text,
            !strippedMemoMessage.isEmpty
        else {
            // Use whitespace to reserve space in the layout
            // to avoid jitter.
            memoCharacterCountLabel.text = " "
            return
        }

        let format = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_MESSAGE_COUNT_FORMAT",
            comment: "Format for the 'message character count indicator' for the 'new payment or payment request' view. Embeds {{ %1$@ the number of characters in the message, %2$@ the maximum number of characters in the message }}.",
        )
        memoCharacterCountLabel.text = String(
            format: format,
            OWSFormat.formatInt(strippedMemoMessage.count),
            OWSFormat.formatInt(PaymentsImpl.maxPaymentMemoMessageLength),
        )
    }

    // MARK: - Events

    private func didTapDoneMemo() {
        let memoMessage = memoTextField.text?.ows_stripped()
        delegate?.didChangeMemo(memoMessage: memoMessage)
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        updateMemoCharacterCount()
    }
}

extension SendPaymentMemoViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString: String) -> Bool {
        // Truncate the replacement to fit.
        let left: String = ((textField.text ?? "") as NSString).substring(to: range.location)
        let right: String = ((textField.text ?? "") as NSString).substring(from: range.location + range.length)
        let maxReplacementLength = PaymentsImpl.maxPaymentMemoMessageLength - Int(left.count + right.count)
        let center = String(replacementString.prefix(maxReplacementLength))
        textField.text = (left + center + right)

        updateMemoCharacterCount()

        // Place the cursor after the truncated replacement.
        let positionAfterChange = left.utf16.count + center.utf16.count
        guard let position = textField.position(from: textField.beginningOfDocument, offset: positionAfterChange) else {
            owsFailDebug("Invalid position")
            return false
        }
        textField.selectedTextRange = textField.textRange(from: position, to: position)
        return false
    }
}
