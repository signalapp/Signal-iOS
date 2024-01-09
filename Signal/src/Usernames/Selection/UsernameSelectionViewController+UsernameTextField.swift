//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

protocol DiscriminatorTextFieldDelegate: AnyObject {
    func didManuallyChangeDiscriminator()
}

extension UsernameSelectionViewController {
    class UsernameTextFieldWrapper: UIView {
        let textField: UsernameTextField

        init(username: ParsedUsername?) {
            textField = UsernameTextField(forUsername: username)

            super.init(frame: .zero)

            addSubview(textField)
            textField.autoPinEdgesToSuperviewMargins()

            layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 14)
            layer.cornerRadius = 10
        }

        required init?(coder: NSCoder) {
            owsFail("Not implemented!")
        }

        func updateFontsForCurrentPreferredContentSize() {
            textField.updateFontsForCurrentPreferredContentSize()
        }

        func setColorsForCurrentTheme() {
            backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white

            textField.setColorsForCurrentTheme()
        }
    }

    class UsernameTextField: OWSTextField {
        /// Presents state related to a username discriminator, such as the
        /// discriminator itself and state indicators such as a spinner.
        class DiscriminatorView: OWSStackView {
            private enum Constants {
                static let spacing: CGFloat = 16
                static let separatorWidth: CGFloat = 2
            }

            enum Mode {
                case empty
                case spinning
                case spinningWithDiscriminator(value: String)
                case discriminator(value: String)
            }

            // MARK: Init

            weak var delegate: (any DiscriminatorTextFieldDelegate)?

            /// The mode for which this view should be configured.
            var mode: Mode {
                didSet {
                    AssertIsOnMainThread()

                    configureForCurrentMode()
                }
            }

            fileprivate var isUsingCustomDiscriminator = false

            init(inMode mode: Mode) {
                self.mode = mode

                super.init(
                    name: "Username discriminator view",
                    arrangedSubviews: []
                )

                addArrangedSubviews([
                    spinnerView,
                    separatorView,
                    discriminatorContainer,
                ])

                spacing = Constants.spacing
                isLayoutMarginsRelativeArrangement = true
                layoutMargins.leading = Constants.spacing

                configureForCurrentMode()
            }

            @available(*, unavailable, message: "Use other constructor")
            required init(name: String, arrangedSubviews: [UIView]) {
                fatalError("Use other constructor")
            }

            // MARK: Views

            private lazy var spinnerView: UIActivityIndicatorView = {
                let spinner = UIActivityIndicatorView(style: .medium)

                spinner.startAnimating()

                return spinner
            }()

            private lazy var separatorView: UIView = {
                let lineView = UIView()

                lineView.backgroundColor = .ows_gray15
                lineView.layer.cornerRadius = Constants.separatorWidth / 2
                lineView.autoSetDimension(.width, toSize: Constants.separatorWidth)

                return lineView
            }()

            private lazy var discriminatorTextField: UITextField = {
                let textField = UITextField()
                textField.placeholder = "00"
                textField.delegate = self
                textField.keyboardType = .numberPad
                return textField
            }()
            // Set a minimum width for the view to the width of two characters
            // in the given Dynamic Type size so it doesn't change when rolling
            // new 2-digit discriminators.
            private lazy var discriminatorContainer: UILabel = {
                let label = UILabel()

                label.numberOfLines = 1
                label.text = "00"
                label.textColor = .clear
                label.isUserInteractionEnabled = true
                label.addSubview(discriminatorTextField)
                discriminatorTextField.autoPinEdgesToSuperviewEdges()

                return label
            }()

            // MARK: Configure views

            func setColorsForCurrentTheme() {
                separatorView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray15
                discriminatorTextField.textColor = Theme.primaryTextColor
            }

            func updateFontsForCurrentPreferredContentSize() {
                let discriminatorFont = UIFont.dynamicTypeBodyClamped
                discriminatorTextField.font = discriminatorFont
                discriminatorContainer.font = discriminatorFont
            }

            /// Configure which subviews to present based on the current mode.
            private func configureForCurrentMode() {
                AssertIsOnMainThread()

                switch mode {
                case .empty:
                    isHidden = true
                case .spinning:
                    isHidden = false
                    spinnerView.isHiddenInStackView = false
                    separatorView.isHiddenInStackView = true
                    discriminatorTextField.isHiddenInStackView = true
                case let .spinningWithDiscriminator(discriminatorValue):
                    isHidden = false
                    spinnerView.isHiddenInStackView = false
                    separatorView.isHiddenInStackView = false
                    discriminatorTextField.isHiddenInStackView = false
                    setDiscriminatorValue(to: discriminatorValue)
                case let .discriminator(discriminatorValue):
                    isHidden = false
                    spinnerView.isHiddenInStackView = true
                    separatorView.isHiddenInStackView = false
                    discriminatorTextField.isHiddenInStackView = false
                    setDiscriminatorValue(to: discriminatorValue)
                }
            }

            private func setDiscriminatorValue(to value: String) {
                discriminatorTextField.text = "\(value)"
            }

            // MARK: Getters

            var currentDiscriminatorString: String? {
                discriminatorTextField.text
            }

            /// Returns `currentDiscriminatorString` if a discriminator was manually
            /// set. Otherwise `nil`.
            var customDiscriminator: String? {
                isUsingCustomDiscriminator ? currentDiscriminatorString : nil
            }

            @discardableResult
            override func becomeFirstResponder() -> Bool {
                discriminatorTextField.becomeFirstResponder()
            }
        }

        /// The last-known reserved/confirmed discriminator. While showing a
        /// spinner for an in-progress reservation, we continue to show the
        /// last-known-good discriminator value.
        private var lastKnownGoodDiscriminator: String?

        let discriminatorView: DiscriminatorView = .init(inMode: .empty)

        init(forUsername username: ParsedUsername?) {
            if let username {
                lastKnownGoodDiscriminator = username.discriminator
                discriminatorView.mode = .discriminator(value: username.discriminator)
            } else {
                discriminatorView.mode = .empty
            }

            super.init(frame: .zero)

            if let username {
                text = username.nickname
            }

            placeholder = OWSLocalizedString(
                "USERNAME_SELECTION_TEXT_FIELD_PLACEHOLDER",
                comment: "The placeholder for a text field into which users can type their desired username."
            )

            returnKeyType = .next
            autocapitalizationType = .none
            autocorrectionType = .no
            spellCheckingType = .no
            accessibilityIdentifier = "username_textfield"

            rightView = discriminatorView
            rightViewMode = .always

            setColorsForCurrentTheme()
            updateFontsForCurrentPreferredContentSize()
        }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("Use other constructor!")
        }

        // MARK: - Configure views

        fileprivate func updateFontsForCurrentPreferredContentSize() {
            font = .dynamicTypeBodyClamped
            discriminatorView.updateFontsForCurrentPreferredContentSize()
        }

        fileprivate func setColorsForCurrentTheme() {
            textColor = Theme.primaryTextColor
            discriminatorView.setColorsForCurrentTheme()
        }

        /// Configure the text field for an in-progress reservation.
        func configureForSomethingPending() {
            if let customDiscriminator = discriminatorView.customDiscriminator {
                setDiscriminatorViewMode(to: .spinningWithDiscriminator(value: customDiscriminator))
            } else if let lastKnownGoodDiscriminator {
                setDiscriminatorViewMode(to: .spinningWithDiscriminator(value: lastKnownGoodDiscriminator))
            } else {
                setDiscriminatorViewMode(to: .spinning)
            }
        }

        /// Configure the text field for an error state.
        func configureForError() {
            if let customDiscriminator = discriminatorView.customDiscriminator {
                setDiscriminatorViewMode(to: .discriminator(value: customDiscriminator))
            } else if let lastKnownGoodDiscriminator {
                setDiscriminatorViewMode(to: .discriminator(value: lastKnownGoodDiscriminator))
            } else {
                setDiscriminatorViewMode(to: .empty)
            }
        }

        /// Configure the text field for a confirmed username. If `nil`,
        /// configures for the intentional absence of a username.
        func configure(forConfirmedUsername confirmedUsername: ParsedUsername?) {
            if confirmedUsername?.discriminator != discriminatorView.customDiscriminator {
                discriminatorView.isUsingCustomDiscriminator = false
            }

            if let confirmedUsername {
                lastKnownGoodDiscriminator = confirmedUsername.discriminator
                setDiscriminatorViewMode(to: .discriminator(value: confirmedUsername.discriminator))
            } else {
                lastKnownGoodDiscriminator = nil
                setDiscriminatorViewMode(to: .empty)
            }
        }

        private func setDiscriminatorViewMode(to mode: DiscriminatorView.Mode) {
            discriminatorView.mode = mode

            // Because the discriminator view's visible subviews may change
            // after setting the mode, we should re-layout ourselves to make
            // sure we size the overall view appropriately.
            setNeedsLayout()
        }

        // MARK: - Getters

        /// Returns the user-visible nickname contents with normalizations
        /// applied. Note that nicknames by definition do not contain the
        /// discriminator.
        ///
        /// - Returns
        /// The normalized contents of the text field. If the returned value
        /// would be empty, returns `nil` instead.
        var normalizedNickname: String? {
            return text?.lowercased().nilIfEmpty
        }

        /// Returns the current user-visible discriminator value. This value is
        /// for display purposes only, and cannot be assumed to be valid or
        /// confirmed.
        var currentDiscriminatorString: String? {
            discriminatorView.currentDiscriminatorString
        }
    }
}

// MARK: - UITextFieldDelegate

extension UsernameSelectionViewController.UsernameTextField.DiscriminatorView: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let oldValue = textField.text
        let shouldChangeCharacters = FormattedNumberField.textField(
            textField,
            shouldChangeCharactersIn: range,
            replacementString: string,
            allowedCharacters: .numbers,
            maxCharacters: 9,
            format: { $0 }
        )
        if textField.text != oldValue {
            isUsingCustomDiscriminator = true
            delegate?.didManuallyChangeDiscriminator()
        }
        return shouldChangeCharacters
    }
}
