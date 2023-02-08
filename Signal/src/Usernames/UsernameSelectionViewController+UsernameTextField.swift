//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension UsernameSelectionViewController {
    class UsernameTextField: OWSTextField {
        /// Presents state related to a username discriminator, such as the
        /// discriminator itself and state indicators such as a spinner.
        private class DiscriminatorView: OWSStackView {
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

            /// The mode for which this view should be configured.
            var mode: Mode {
                didSet {
                    AssertIsOnMainThread()

                    configureForCurrentMode()
                }
            }

            init(inMode mode: Mode) {
                self.mode = mode

                super.init(
                    name: "Username discriminator view",
                    arrangedSubviews: []
                )

                addArrangedSubviews([
                    spinnerView,
                    separatorView,
                    discriminatorLabel
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
                let spinner: UIActivityIndicatorView = {
                    if #available(iOS 13, *) {
                        return .init(style: .medium)
                    } else {
                        return .init(style: .white)
                    }
                }()

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

            private lazy var discriminatorLabel: UILabel = {
                let label = UILabel()

                label.numberOfLines = 1

                return label
            }()

            // MARK: Configure views

            func setColorsForCurrentTheme() {
                separatorView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray15
                discriminatorLabel.textColor = Theme.primaryTextColor
            }

            func updateFontsForCurrentPreferredContentSize() {
                discriminatorLabel.font = .ows_dynamicTypeBodyClamped
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
                    discriminatorLabel.isHiddenInStackView = true
                case let .spinningWithDiscriminator(discriminatorValue):
                    isHidden = false
                    spinnerView.isHiddenInStackView = false
                    separatorView.isHiddenInStackView = false
                    discriminatorLabel.isHiddenInStackView = false
                    setDiscriminatorValue(to: discriminatorValue)
                case let .discriminator(discriminatorValue):
                    isHidden = false
                    spinnerView.isHiddenInStackView = true
                    separatorView.isHiddenInStackView = false
                    discriminatorLabel.isHiddenInStackView = false
                    setDiscriminatorValue(to: discriminatorValue)
                }
            }

            private func setDiscriminatorValue(to value: String) {
                discriminatorLabel.text = "\(ParsedUsername.separator)\(value)"
            }

            // MARK: Getters

            var currentDiscriminatorString: String? {
                discriminatorLabel.text
            }
        }

        /// The last-known reserved/confirmed discriminator. While showing a
        /// spinner for an in-progress reservation, we continue to show the
        /// last-known-good discriminator value.
        private var lastKnownGoodDiscriminator: String?

        private let discriminatorView: DiscriminatorView = .init(inMode: .empty)

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

            returnKeyType = .default
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

        func updateFontsForCurrentPreferredContentSize() {
            font = .ows_dynamicTypeBodyClamped
            discriminatorView.updateFontsForCurrentPreferredContentSize()
        }

        func setColorsForCurrentTheme() {
            textColor = Theme.primaryTextColor
            discriminatorView.setColorsForCurrentTheme()
        }

        /// Configure the text field for an in-progress reservation.
        func configureForReservationInProgress() {
            if let lastKnownGoodDiscriminator {
                setDiscriminatorViewMode(to: .spinningWithDiscriminator(value: lastKnownGoodDiscriminator))
            } else {
                setDiscriminatorViewMode(to: .spinning)
            }
        }

        /// Configure the text field for an error state.
        func configureForError() {
            if let lastKnownGoodDiscriminator {
                setDiscriminatorViewMode(to: .discriminator(value: lastKnownGoodDiscriminator))
            } else {
                setDiscriminatorViewMode(to: .empty)
            }
        }

        /// Configure the text field for a confirmed username. If `nil`,
        /// configures for the intentional absence of a username.
        func configure(forConfirmedUsername confirmedUsername: ParsedUsername?) {
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
