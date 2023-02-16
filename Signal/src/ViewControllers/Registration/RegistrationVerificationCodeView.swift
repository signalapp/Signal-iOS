//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - RegistrationVerificationCodeTextField

private protocol RegistrationVerificationCodeTextFieldDelegate: AnyObject {
    func textFieldDidDeletePrevious()
}

// Editing a code should feel seamless, as even though the UITextField only lets you edit a single
// digit at a time.  For deletes to work properly, we need to detect delete events that would affect
// the _previous_ digit.
private class RegistrationVerificationCodeTextField: UITextField {
    fileprivate weak var codeDelegate: RegistrationVerificationCodeTextFieldDelegate?

    override func deleteBackward() {
        var isDeletePrevious = false
        if let selectedTextRange = selectedTextRange {
            let cursorPosition = offset(from: beginningOfDocument, to: selectedTextRange.start)
            if cursorPosition == 0 {
                isDeletePrevious = true
            }
        }

        super.deleteBackward()

        if isDeletePrevious {
            codeDelegate?.textFieldDidDeletePrevious()
        }
    }
}

// MARK: - RegistrationVerificationCodeViewDelegate

protocol RegistrationVerificationCodeViewDelegate: AnyObject {
    func codeViewDidChange()
}

// MARK: - RegistrationVerificationCodeView

/// The ``RegistrationVerificationCodeView`` is a special "verification code" editor that should
/// feel like editing a single piece of text (ala UITextField) even though the individual digits of
/// the code are visually separated.
///
/// We use a separate ``UILabel`` for each digit, and move around a single ``UITextfield`` to let
/// the user edit the last/next digit.
class RegistrationVerificationCodeView: UIView {
    weak var delegate: RegistrationVerificationCodeViewDelegate?

    public init() {
        super.init(frame: .zero)

        createSubviews()

        updateViewState()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let digitCount = 6
    private var digitLabels = [UILabel]()
    private var digitStrokes = [UIView]()

    private let cellFont: UIFont = UIFont.ows_dynamicTypeLargeTitle1Clamped
    private let interCellSpacing: CGFloat = 8
    private let segmentSpacing: CGFloat = 24
    private let strokeWidth: CGFloat = 3

    private var cellSize: CGSize {
        let vMargin: CGFloat = 4
        let cellHeight: CGFloat = cellFont.lineHeight + vMargin * 2
        let cellWidth: CGFloat = cellHeight * 2 / 3
        return CGSize(width: cellWidth, height: cellHeight)
    }

    override var intrinsicContentSize: CGSize {
        let totalWidth = (CGFloat(digitCount) * (cellSize.width + interCellSpacing)) + segmentSpacing
        let totalHeight = strokeWidth + cellSize.height
        return CGSize(width: totalWidth, height: totalHeight)
    }

    // We use a single text field to edit the "current" digit.
    // The "current" digit is usually the "last"
    fileprivate let textfield = RegistrationVerificationCodeTextField()
    private var currentDigitIndex = 0
    private var textfieldConstraints = [NSLayoutConstraint]()

    // The current complete text - the "model" for this view.
    private var digitText = ""

    var isComplete: Bool {
        return digitText.count == digitCount
    }
    var verificationCode: String {
        return digitText
    }

    private func createSubviews() {
        textfield.textAlignment = .left
        textfield.delegate = self
        textfield.codeDelegate = self

        textfield.textColor = Theme.primaryTextColor
        textfield.font = UIFont.ows_dynamicTypeLargeTitle1Clamped
        textfield.keyboardType = .numberPad
        textfield.textContentType = .oneTimeCode

        var digitViews = [UIView]()
        (0..<digitCount).forEach { (_) in
            let (digitView, digitLabel, digitStroke) = makeCellView(text: "", hasStroke: true)

            digitLabels.append(digitLabel)
            digitStrokes.append(digitStroke)
            digitViews.append(digitView)
        }

        digitViews.insert(UIView.spacer(withWidth: segmentSpacing), at: 3)

        let stackView = UIStackView(arrangedSubviews: digitViews)
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = interCellSpacing
        addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        stackView.autoHCenterInSuperview()

        self.addSubview(textfield)
    }

    private func makeCellView(text: String, hasStroke: Bool) -> (UIView, UILabel, UIView) {
        let digitView = UIView()

        let digitLabel = UILabel()
        digitLabel.text = text
        digitLabel.font = cellFont
        digitLabel.textColor = Theme.primaryTextColor
        digitLabel.textAlignment = .center
        digitView.addSubview(digitLabel)
        digitLabel.autoCenterInSuperview()

        let strokeColor = (hasStroke ? Theme.secondaryTextAndIconColor : UIColor.clear)
        let strokeView = digitView.addBottomStroke(color: strokeColor, strokeWidth: strokeWidth)
        strokeView.layer.cornerRadius = strokeWidth / 2

        digitView.autoSetDimensions(to: cellSize)
        return (digitView, digitLabel, strokeView)
    }

    private func digit(at index: Int) -> String {
        guard index < digitText.count else {
            return ""
        }
        return digitText.substring(from: index).substring(to: 1)
    }

    // Ensure that all labels are displaying the correct
    // digit (if any) and that the UITextField has replaced
    // the "current" digit.
    private func updateViewState() {
        currentDigitIndex = min(digitCount - 1,
                                digitText.count)

        (0..<digitCount).forEach { (index) in
            let digitLabel = digitLabels[index]
            digitLabel.text = digit(at: index)
            digitLabel.isHidden = index == currentDigitIndex
        }

        NSLayoutConstraint.deactivate(textfieldConstraints)
        textfieldConstraints.removeAll()

        let digitLabelToReplace = digitLabels[currentDigitIndex]
        textfield.text = digit(at: currentDigitIndex)
        textfieldConstraints.append(textfield.autoAlignAxis(.horizontal, toSameAxisOf: digitLabelToReplace))
        textfieldConstraints.append(textfield.autoAlignAxis(.vertical, toSameAxisOf: digitLabelToReplace))

        // Move cursor to end of text.
        let newPosition = textfield.endOfDocument
        textfield.selectedTextRange = textfield.textRange(from: newPosition, to: newPosition)
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        return textfield.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        return textfield.resignFirstResponder()
    }

    func setHasError(_ hasError: Bool) {
        let backgroundColor = (hasError ? UIColor.ows_accentRed : Theme.secondaryTextAndIconColor)
        for digitStroke in digitStrokes {
            digitStroke.backgroundColor = backgroundColor
        }
    }

    func set(verificationCode: String) {
        digitText = verificationCode

        updateViewState()

        self.delegate?.codeViewDidChange()
    }
}

// MARK: -

extension RegistrationVerificationCodeView: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString newString: String) -> Bool {
        var oldText = ""
        if let textFieldText = textField.text {
            oldText = textFieldText
        }
        let left = oldText.substring(to: range.location)
        let right = oldText.substring(from: range.location + range.length)
        let unfiltered = left + newString + right
        let characterSet = CharacterSet(charactersIn: "0123456789")
        let filtered = unfiltered.components(separatedBy: characterSet.inverted).joined()
        let filteredAndTrimmed = filtered.substring(to: 1)
        textField.text = filteredAndTrimmed

        digitText = digitText.substring(to: currentDigitIndex) + filteredAndTrimmed

        updateViewState()

        self.delegate?.codeViewDidChange()

        // Inform our caller that we took care of performing the change.
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.delegate?.codeViewDidChange()

        return false
    }
}

// MARK: - RegistrationVerificationCodeTextFieldDelegate

extension RegistrationVerificationCodeView: RegistrationVerificationCodeTextFieldDelegate {
    public func textFieldDidDeletePrevious() {
        if digitText.isEmpty { return }
        digitText = digitText.substring(to: currentDigitIndex - 1)

        updateViewState()
    }
}
