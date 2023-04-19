//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI

@objc
public protocol SendPaymentMemoViewDelegate {
    func didChangeMemo(memoMessage: String?)
}

// MARK: -

@objc
public class SendPaymentMemoViewController: OWSViewController {

    @objc
    public weak var delegate: SendPaymentMemoViewDelegate?

    private let rootStack = UIStackView()

    private let memoTextField = UITextField()
    private let memoCharacterCountLabel = UILabel()

    public required init(memoMessage: String?) {
        super.init()

        memoTextField.text = memoMessage
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        createContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        memoTextField.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        memoTextField.becomeFirstResponder()
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    private func createContents() {
        navigationItem.title = NSLocalizedString("PAYMENTS_NEW_PAYMENT_ADD_MEMO",
                                                 comment: "Label for the 'add memo' ui in the 'send payment' UI.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(didTapCancelMemo),
                                                           accessibilityIdentifier: "memo.cancel")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self,
                                                            action: #selector(didTapDoneMemo),
                                                            accessibilityIdentifier: "memo.done")

        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        rootStack.isLayoutMarginsRelativeArrangement = true
        view.addSubview(rootStack)
        rootStack.autoPinEdge(toSuperviewMargin: .leading)
        rootStack.autoPinEdge(toSuperviewMargin: .trailing)
        rootStack.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        rootStack.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        updateContents()
    }

    private func updateContents() {
        AssertIsOnMainThread()

        rootStack.removeAllSubviews()

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        memoTextField.backgroundColor = .clear
        memoTextField.font = .dynamicTypeBodyClamped
        memoTextField.textColor = Theme.primaryTextColor
        let placeholder = NSAttributedString(string: NSLocalizedString("PAYMENTS_NEW_PAYMENT_MESSAGE_PLACEHOLDER",
                                                                       comment: "Placeholder for the new payment or payment request message."),
                                             attributes: [
                                                .foregroundColor: Theme.secondaryTextAndIconColor
                                             ])
        memoTextField.attributedPlaceholder = placeholder
        memoTextField.delegate = self
        memoTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        memoCharacterCountLabel.font = .dynamicTypeBodyClamped
        memoCharacterCountLabel.textColor = Theme.ternaryTextColor

        memoCharacterCountLabel.setCompressionResistanceHorizontalHigh()
        memoCharacterCountLabel.setContentHuggingHorizontalHigh()

        let memoRow = UIStackView(arrangedSubviews: [
            memoTextField,
            memoCharacterCountLabel
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
            UIView.vStretchingSpacer()
        ])
    }

    public override func themeDidChange() {
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

        let format = NSLocalizedString("PAYMENTS_NEW_PAYMENT_MESSAGE_COUNT_FORMAT",
                                       comment: "Format for the 'message character count indicator' for the 'new payment or payment request' view. Embeds {{ %1$@ the number of characters in the message, %2$@ the maximum number of characters in the message }}.")
        memoCharacterCountLabel.text = String(format: format,
                                              OWSFormat.formatInt(strippedMemoMessage.count),
                                              OWSFormat.formatInt(PaymentsImpl.maxPaymentMemoMessageLength))
    }

    // MARK: - Events

    @objc
    func didTapCancelMemo() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    func didTapDoneMemo() {
        let memoMessage = memoTextField.text?.ows_stripped()
        delegate?.didChangeMemo(memoMessage: memoMessage)
        navigationController?.popViewController(animated: true)
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        updateMemoCharacterCount()
    }
}

// MARK: 

extension SendPaymentMemoViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString: String) -> Bool {
        // Truncate the replacement to fit.
        let left: String = (textField.text ?? "").substring(to: range.location)
        let right: String = (textField.text ?? "").substring(from: range.location + range.length)
        let maxReplacementLength = PaymentsImpl.maxPaymentMemoMessageLength - Int(left.count + right.count)
        let center = replacementString.substring(to: maxReplacementLength)
        textField.text = (left + center + right)

        updateMemoCharacterCount()

        // Place the cursor after the truncated replacement.
        let positionAfterChange = left.count + center.count
        guard let position = textField.position(from: textField.beginningOfDocument, offset: positionAfterChange) else {
            owsFailDebug("Invalid position")
            return false
        }
        textField.selectedTextRange = textField.textRange(from: position, to: position)
        return false
    }
}
