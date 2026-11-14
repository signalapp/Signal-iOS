//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationTwoFactorAuthenticatorCodePresenter

protocol RegistrationTwoFactorAuthenticatorCodePresenter: RegistrationTwoFactorAuthPresenter {
    func submitAuthenticatorCode(_ code: String)
}

// MARK: - RegistrationTwoFactorAuthenticatorCodeViewController

class RegistrationTwoFactorAuthenticatorCodeViewController: OWSViewController {

    private enum Constants {
        static let stackEdgeInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18)
        static let sectionSpacing: CGFloat = 8
        static let bodyLabelMargins: CGFloat = 20
        static let codeLength = 6
    }

    private weak var presenter: RegistrationTwoFactorAuthenticatorCodePresenter?

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.directionalLayoutMargins = Constants.stackEdgeInsets
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Constants.sectionSpacing
        return stackView
    }()

    private lazy var titleImageView: UIImageView = {
        let titleImageView = UIImageView(image: .twoFactorAuthenticator)
        titleImageView.translatesAutoresizingMaskIntoConstraints = false
        titleImageView.contentMode = .center
        return titleImageView
    }()

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_TWO_FACTOR_AUTH_TITLE",
                comment: "Title for the 2fa screens shown during registration.",
            ),
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }()

    private lazy var bodyLabel: UIView = {
        let bodyLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_TWO_FACTOR_AUTH_AUTHENTICATOR_CODE_BODY",
                comment: "Description for the screen asking the user to enter the 6-digit code from their authenticator app during registration.",
            ),
        )
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let bodyLabelContainer = UIView.transparentContainer()
        bodyLabelContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyLabelContainer.addSubview(bodyLabel)
        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: bodyLabelContainer.topAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: bodyLabelContainer.bottomAnchor),
            bodyLabel.centerXAnchor.constraint(equalTo: bodyLabelContainer.centerXAnchor),
            bodyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: bodyLabelContainer.leadingAnchor,
                constant: Constants.bodyLabelMargins,
            ),
            bodyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: bodyLabelContainer.trailingAnchor,
                constant: -Constants.bodyLabelMargins,
            ),
        ])
        return bodyLabelContainer
    }()

    private lazy var codeEntryView: NumericCodeEntryView = {
        let codeEntryView = NumericCodeEntryView(codeLength: Constants.codeLength)
        codeEntryView.translatesAutoresizingMaskIntoConstraints = false
        codeEntryView.didEnterCompleteCode = { [weak self] code in
            self?.presenter?.submitAuthenticatorCode(code)
        }
        return codeEntryView
    }()

    private lazy var codeEntryContainer = {
        let codeEntryContainer = UIView.transparentContainer()
        codeEntryContainer.translatesAutoresizingMaskIntoConstraints = false
        codeEntryContainer.addSubview(codeEntryView)
        NSLayoutConstraint.activate([
            codeEntryView.topAnchor.constraint(equalTo: codeEntryContainer.topAnchor),
            codeEntryView.bottomAnchor.constraint(equalTo: codeEntryContainer.bottomAnchor),
            codeEntryView.centerXAnchor.constraint(equalTo: codeEntryContainer.centerXAnchor),
            codeEntryView.leadingAnchor.constraint(greaterThanOrEqualTo: codeEntryContainer.leadingAnchor),
            codeEntryView.trailingAnchor.constraint(lessThanOrEqualTo: codeEntryContainer.trailingAnchor),
        ])
        return codeEntryContainer
    }()

    private lazy var cancelButton: UIView = {
        let cancelButton = UIButton(
            configuration: .mediumSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.presenter?.cancelTwoFactorAuth()
            },
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButtonContainer = UIView.transparentContainer()
        cancelButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        cancelButtonContainer.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: cancelButtonContainer.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: cancelButtonContainer.bottomAnchor),
            cancelButton.centerXAnchor.constraint(equalTo: cancelButtonContainer.centerXAnchor),
            cancelButton.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButtonContainer.leadingAnchor),
            cancelButton.trailingAnchor.constraint(lessThanOrEqualTo: cancelButtonContainer.trailingAnchor),
        ])
        return cancelButtonContainer
    }()

    private lazy var spacer: UIView = {
        let spacer = SpacerView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        return spacer
    }()

    init(presenter: RegistrationTwoFactorAuthenticatorCodePresenter) {
        self.presenter = presenter
        super.init()
        navigationItem.hidesBackButton = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        view.addSubview(stackView)
        let constraint = stackView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        constraint.priority = .defaultLow
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            constraint,
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        stackView.addArrangedSubviews([
            titleImageView,
            titleLabel,
            bodyLabel,
            codeEntryContainer,
            spacer,
            cancelButton,
        ])
        stackView.setCustomSpacing(16, after: titleImageView)
        stackView.setCustomSpacing(24, after: bodyLabel)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        codeEntryView.becomeFirstResponder()
    }

    @available(*, unavailable)
    override init() {
        owsFail("Not implemented.")
    }
}

// MARK: - NumericCodeEntryView

/// A row of boxes, one per digit, backed by a single invisible text field.
/// This allows editing, pasting, and one-time code autofill to behave like a normal
/// text field.
private class NumericCodeEntryView: UIView, UITextFieldDelegate {

    private enum Constants {
        static let boxSize = CGSize(width: 40, height: 50)
        static let boxSpacing: CGFloat = 8
        static let boxCornerRadius: CGFloat = 10
        static let cursorSize = CGSize(width: 2, height: 24)
        static let highlightBorderWidth: CGFloat = 2
    }

    var didEnterCompleteCode: ((String) -> Void)?

    private lazy var textField: UITextField = {
        let textField = NumericCodeTextField()
        textField.keyboardType = .numberPad
        textField.textContentType = .oneTimeCode
        // Transparent text color allows the user to still type in text
        // and fire the delegate methods, but the rendering of the
        // text is handled by the boxStack
        textField.textColor = .clear
        textField.tintColor = .clear
        // This also allows advertising a single accessibility element for entering
        // a code instead of one element per digit
        textField.accessibilityLabel = OWSLocalizedString(
            "ONBOARDING_TWO_FACTOR_AUTH_AUTHENTICATOR_CODE_FIELD_LABEL",
            comment: "Accessibility label for the field where the user enters the code from their authenticator app",
        )
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapBoxes))
        tapGesture.delegate = self
        textField.addGestureRecognizer(tapGesture)
        return textField
    }()

    private lazy var boxStack: UIStackView = {
        let boxStack = UIStackView()
        boxStack.axis = .horizontal
        boxStack.spacing = Constants.boxSpacing
        boxStack.isUserInteractionEnabled = false
        boxStack.translatesAutoresizingMaskIntoConstraints = false
        return boxStack
    }()

    private lazy var cursorView: UIView = {
        let cursorView = UIView()
        cursorView.backgroundColor = .Signal.label
        cursorView.isUserInteractionEnabled = false
        cursorView.isHidden = true
        return cursorView
    }()

    private let codeLength: Int
    private var cursorIndex: Int?
    private var digitLabels = [UILabel]()
    private var boxViews = [UIView]()

    init(codeLength: Int) {
        self.codeLength = codeLength
        super.init(frame: .zero)

        addSubview(textField)
        addSubview(boxStack)

        for _ in 0..<codeLength {
            let box = UIView()
            box.backgroundColor = .Signal.secondaryFill
            box.layer.cornerRadius = Constants.boxCornerRadius
            box.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.font = UIFont.dynamicTypeTitle2Clamped
            label.textColor = .Signal.label
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)

            NSLayoutConstraint.activate([
                box.widthAnchor.constraint(equalToConstant: Constants.boxSize.width),
                box.heightAnchor.constraint(equalToConstant: Constants.boxSize.height),
                label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            ])

            boxStack.addArrangedSubview(box)
            boxViews.append(box)
            digitLabels.append(label)
        }

        addSubview(cursorView)

        // Make box view and text field the full size of the view.
        // The box view has user interaction disabled, so this results
        // in any taps in the view being routed to the UITextVield
        NSLayoutConstraint.activate([
            boxStack.topAnchor.constraint(equalTo: topAnchor),
            boxStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            boxStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            boxStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textField.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        textField.resignFirstResponder()
    }

    private var code: String { textField.text ?? "" }

    // MARK: User Interaction

    /// Tapping a filled box selects its digit so typing replaces it; tapping
    /// an empty box moves the caret to the end of the code.
    @objc
    private func didTapBoxes(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let tappedIndex = boxViews.indices.min { lhs, rhs in
            abs(boxViews[lhs].frame.midX - location.x) < abs(boxViews[rhs].frame.midX - location.x)
        } ?? 0
        // Defer so this runs after the text field's own caret placement.
        DispatchQueue.main.async { [self] in
            if tappedIndex < code.count {
                setSelection(NSRange(location: tappedIndex, length: 1))
            } else {
                setSelection(NSRange(location: code.count, length: 0))
            }
        }
    }

    // MARK: Selection

    private var selectedRange: NSRange? {
        guard let range = textField.selectedTextRange else { return nil }
        return NSRange(
            location: textField.offset(from: textField.beginningOfDocument, to: range.start),
            length: textField.offset(from: range.start, to: range.end),
        )
    }

    private func setSelection(_ range: NSRange) {
        guard
            let start = textField.position(from: textField.beginningOfDocument, offset: range.location),
            let end = textField.position(from: start, offset: range.length)
        else { return }
        textField.selectedTextRange = textField.textRange(from: start, to: end)
        updateCursor()
    }

    // MARK: Rendering

    @objc
    private func textDidChange() {
        // Keep only digits, up to the code length.
        let sanitized = String(code.asciiDigitsOnly.prefix(codeLength))
        if sanitized != code {
            textField.text = sanitized
        }

        let digits = Array(code)
        for (index, label) in digitLabels.enumerated() {
            label.text = index < digits.count ? String(digits[index]) : nil
        }
        updateCursor()

        if digits.count == codeLength {
            didEnterCompleteCode?(code)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateCursor()
    }

    /// Updates the cursor caret and the highlighted boxes to reflect the text field's
    /// selection. A caret is only drawn inside the next empty box - i.e. when it sits
    /// at the end of an incomplete code.
    private func updateCursor() {
        let selection = textField.isFirstResponder ? selectedRange : nil

        let highlightedRange = selection.flatMap { $0.length > 0 ? $0 : nil }
        // Would be nice to use the dynamic color here, but alas borderColor needs a CGColor
        let highlightColor = UIColor.Signal.accent.resolvedColor(with: traitCollection).cgColor
        for (index, box) in boxViews.enumerated() {
            let isHighlighted = highlightedRange.map { NSLocationInRange(index, $0) } ?? false
            box.layer.borderWidth = isHighlighted ? Constants.highlightBorderWidth : 0
            box.layer.borderColor = highlightColor
        }

        guard
            (textField.text?.count ?? 0) < codeLength,
            let selection,
            selection.length == 0,
            selection.location < boxViews.count
        else {
            cursorIndex = nil
            cursorView.layer.removeAllAnimations()
            cursorView.isHidden = true
            return
        }

        cursorIndex = selection.location
        cursorView.isHidden = false
        setNeedsLayout()

        // Blink the caret
        cursorView.layer.removeAllAnimations()
        cursorView.alpha = 1
        UIView.animate(
            withDuration: 0.5,
            delay: 0.5,
            options: [.repeat, .autoreverse, .curveEaseInOut],
            animations: { self.cursorView.alpha = 0 },
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let cursorIndex else { return }
        // The boxes are positioned by the stack's own layout pass, which
        // otherwise runs after this one.
        boxStack.layoutIfNeeded()
        let box = boxViews[cursorIndex]
        let boxFrame = box.convert(box.bounds, to: self)
        let cursorX = cursorIndex < code.count
            ? boxFrame.minX - Constants.boxSpacing / 2
            : boxFrame.midX
        cursorView.frame = CGRect(
            x: cursorX - Constants.cursorSize.width / 2,
            y: boxFrame.midY - Constants.cursorSize.height / 2,
            width: Constants.cursorSize.width,
            height: Constants.cursorSize.height,
        )
    }

    // MARK: UITextFieldDelegate

    @objc
    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateCursor()
    }

    @objc
    func textFieldDidEndEditing(_ textField: UITextField) {
        updateCursor()
    }

    @objc
    func textFieldDidChangeSelection(_ textField: UITextField) {
        updateCursor()
    }

    @objc(textField:shouldChangeCharactersInRange:replacementString:)
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        // Ignore input with no digits so it can't replace a selected digit.
        if !string.isEmpty, string.asciiDigitsOnly.isEmpty {
            return false
        }

        // Typing into a full code would push its last digit off the end.
        // Pastes are still allowed through and truncated afterwards.
        if string.count == 1, range.length == 0, code.count >= codeLength {
            return false
        }

        let nextIndex: Int
        if string.count > 1 {
            textField.text = string
            nextIndex = string.count
        } else if let swiftRange = Range(range, in: code) {
            textField.text = code.replacingCharacters(in: swiftRange, with: string)
            nextIndex = range.location + string.count
        } else {
            return true
        }

        // Similar to didTapBoxes above, defer setSelection until after the
        // text field's own caret placement executes.  Otherwise, this selection
        // applies, but the UITextField textFieldDidChangeSelection will overwrite
        // it with it's internal understanding of the cursor position.
        // The alternative is to return `true` from this method and update the
        // the text via
        DispatchQueue.main.async { [self] in
            if nextIndex < code.count {
                setSelection(NSRange(location: nextIndex, length: 1))
            } else {
                setSelection(NSRange(location: code.count, length: 0))
            }
        }
        textDidChange()
        return false
    }
}

// MARK: UIGestureRecognizerDelegate

extension NumericCodeEntryView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        true
    }
}

// MARK: - NumericCodeTextField

/// A text field that draws no caret or selection UI of its own, since
/// NumericCodeEntryView renders those on its boxes.
private class NumericCodeTextField: OWSTextField {
    override func caretRect(for position: UITextPosition) -> CGRect {
        .zero
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        []
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationTwoFactorAuthenticatorCodePresenter: RegistrationTwoFactorAuthenticatorCodePresenter {
    func submitAuthenticatorCode(_ code: String) {
        print("code: \(code)")
    }

    func cancelTwoFactorAuth() { }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationTwoFactorAuthenticatorCodePresenter()
    return UINavigationController(
        rootViewController: RegistrationTwoFactorAuthenticatorCodeViewController(presenter: presenter),
    )
}

#endif
