//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
protocol SendPaymentMemoViewDelegate: AnyObject {
    func didChangeMemo(memoMessage: String?)
}

class SendPaymentMemoViewController: OWSViewController, UITextFieldDelegate {
    weak var delegate: SendPaymentMemoViewDelegate?

    private lazy var memoTextField: UITextField = {
        let textField = UITextField()
        textField.font = .dynamicTypeBodyClamped
        textField.textColor = .Signal.label
        textField.rightViewMode = .always
        textField.rightView = memoCharacterCountLabel
        textField.placeholder = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_MESSAGE_PLACEHOLDER",
            comment: "Placeholder for the new payment or payment request message.",
        )
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var memoCharacterCountLabel: UILabel = {
        let label = UILabel()
        label.text = " "
        label.font = .dynamicTypeBodyClamped.monospaced()
        label.textColor = .Signal.tertiaryLabel
        return label
    }()

    init(memoMessage: String?) {
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

        view.backgroundColor = .Signal.groupedBackground

        let memoFieldContainer = UIView()
        memoFieldContainer.backgroundColor = .Signal.secondaryGroupedBackground
        memoFieldContainer.directionalLayoutMargins = .init(
            hMargin: OWSTableViewController2.cellHInnerMargin,
            vMargin: OWSTableViewController2.cellVInnerMargin,
        )
        if #available(iOS 26, *) {
            memoFieldContainer.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            memoFieldContainer.layer.cornerRadius = 10
        }
        memoFieldContainer.addSubview(memoTextField)
        memoTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            memoTextField.topAnchor.constraint(equalTo: memoFieldContainer.layoutMarginsGuide.topAnchor),
            memoTextField.leadingAnchor.constraint(equalTo: memoFieldContainer.layoutMarginsGuide.leadingAnchor),
            memoTextField.trailingAnchor.constraint(equalTo: memoFieldContainer.layoutMarginsGuide.trailingAnchor),
            memoTextField.bottomAnchor.constraint(equalTo: memoFieldContainer.layoutMarginsGuide.bottomAnchor),
        ])

        addStaticContentStackView(
            arrangedSubviews: [.spacer(withHeight: 16), memoFieldContainer, .vStretchingSpacer()],
            isScrollable: true,
            shouldAvoidKeyboard: true,
        )

        updateMemoCharacterCount()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        memoTextField.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        memoTextField.becomeFirstResponder()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    // MARK: -

    fileprivate func updateMemoCharacterCount() {
        defer {
            memoCharacterCountLabel.sizeToFit()
        }

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
        memoCharacterCountLabel.text = String.nonPluralLocalizedStringWithFormat(
            format,
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

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString: String) -> Bool {
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
