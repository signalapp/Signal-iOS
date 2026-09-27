//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// Outgoing message approval can be a multi-step process.
public enum ApprovalMode: UInt {
    // This is the final step of approval; continuing will send.
    case send
    // This is not the final step of approval; continuing will not send.
    case next
    // This is the final step of approval; but it does not send it just selects.
    case select
    // This step is not yet ready to proceed.
    case loading

    fileprivate var proceedButtonAccessibilityLabel: String? {
        switch self {
        case .next: CommonStrings.nextButton
        case .send: MessageStrings.sendButton
        case .select: CommonStrings.doneButton
        case .loading: nil
        }
    }

    fileprivate var proceedButtonImage: UIImage {
        switch self {
        case .next, .loading: Theme.iconImage(.arrowRight)
        case .send: Theme.iconImage(.arrowUp)
        case .select: Theme.iconImage(.checkmark)
        }
    }
}

public protocol ApprovalFooterDelegate: AnyObject {
    func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView)

    func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode

    func approvalFooterDidBeginEditingText()
}

public class ApprovalFooterView: UIView, UITextFieldDelegate {
    public weak var delegate: ApprovalFooterDelegate? {
        didSet {
            updateContents()
        }
    }

    private var textFieldBackgroundView: UIView?

    public var textInput: String? {
        approvalTextMode == .none ? nil : textField.text
    }

    private var approvalMode: ApprovalMode {
        delegate?.approvalMode(self) ?? .send
    }

    public enum ApprovalTextMode: Equatable {
        case none
        case active(placeholderText: String)
    }

    public var approvalTextMode: ApprovalTextMode = .none {
        didSet {
            if oldValue != approvalTextMode {
                updateContents()
            }
        }
    }

    public var isAllowedToProceed = true {
        didSet { proceedButton.isEnabled = isAllowedToProceed }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        autoresizingMask = .flexibleHeight
        preservesSuperviewLayoutMargins = true
        directionalLayoutMargins.top = 10
        directionalLayoutMargins.bottom = 10

        if #unavailable(iOS 26) {
            let backgroundView = UIView()
            backgroundView.backgroundColor = .Signal.secondaryBackground
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(backgroundView)
            NSLayoutConstraint.activate([
                backgroundView.topAnchor.constraint(equalTo: topAnchor),
                backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                // We extend our background view below the keyboard to avoid any gaps.
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 30),
            ])

            // Hairline stroke at the top.
            let topStrokeView = UIView()
            topStrokeView.backgroundColor = .Signal.opaqueSeparator
            topStrokeView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(topStrokeView)
            NSLayoutConstraint.activate([
                topStrokeView.topAnchor.constraint(equalTo: topAnchor),
                topStrokeView.leadingAnchor.constraint(equalTo: leadingAnchor),
                topStrokeView.trailingAnchor.constraint(equalTo: trailingAnchor),
                topStrokeView.heightAnchor.constraint(equalToConstant: hairlineWidth),
            ])
        }

        let bottomRow = UIStackView(arrangedSubviews: [labelScrollView, proceedButton])
        bottomRow.spacing = 12
        bottomRow.alignment = .center

        let vStack = UIStackView(arrangedSubviews: [textFieldContainer, bottomRow])
        vStack.axis = .vertical
        vStack.spacing = 16
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        updateContents()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        return CGSize.zero
    }

    // MARK: Public

    public var namesText: String? {
        get { namesLabel.text }
        set { setNamesText(newValue, animated: false) }
    }

    public func setNamesText(_ newValue: String?, animated: Bool) {
        let text: String
        let textColor: UIColor
        if let recipientList = newValue?.nilIfEmpty {
            text = recipientList
            textColor = .Signal.label
        } else {
            text = OWSLocalizedString(
                "CONVERSATION_PICKER_CHOOSE_RECIPIENT",
                comment: "Displayed at the bottom of chat picker in gray if no chats are selected.",
            )
            textColor = .Signal.secondaryLabel
        }
        let changes = {
            self.namesLabel.text = text
            self.namesLabel.textColor = textColor

            self.layoutIfNeeded()

            let offset = max(0, self.labelScrollView.contentSize.width - self.labelScrollView.bounds.width)
            let trailingEdge = CGPoint(x: offset, y: 0)

            self.labelScrollView.setContentOffset(trailingEdge, animated: false)
        }

        if animated {
            UIView.animate(withDuration: 0.1, animations: changes)
        } else {
            changes()
        }
    }

    // MARK: Private subviews

    private lazy var labelScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        namesLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(namesLabel)

        NSLayoutConstraint.activate([
            namesLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            namesLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            namesLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            namesLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            namesLabel.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        return scrollView
    }()

    private lazy var namesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.dynamicTypeBody
        return label
    }()

    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.delegate = self
        textField.textColor = .Signal.label
        textField.tintColor = .Signal.label
        textField.font = UIFont.dynamicTypeBody
        return textField
    }()

    private lazy var textFieldContainer: UIView = {
        let containerView: UIView
        let contentView: UIView
        if #available(iOS 26, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.cornerConfiguration = .capsule()
            glassEffectView.directionalLayoutMargins = .init(hMargin: 16, vMargin: 11)

            containerView = glassEffectView
            contentView = glassEffectView.contentView
        } else {
            let view = UIView()
            view.backgroundColor = .Signal.tertiaryBackground
            view.layer.cornerRadius = 10
            view.directionalLayoutMargins = .init(hMargin: 8, vMargin: 7)

            self.textFieldBackgroundView = view

            containerView = view
            contentView = view
        }

        textField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor),
            textField.leadingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.trailingAnchor),
            textField.bottomAnchor.constraint(equalTo: containerView.layoutMarginsGuide.bottomAnchor),
        ])

        return containerView
    }()

    private var proceedLoadingIndicator: UIActivityIndicatorView?

    private lazy var proceedButton: UIButton = {
        var buttonConfig: UIButton.Configuration = if #available(iOS 26, *) { .prominentGlass() } else { .borderedProminent() }
        buttonConfig.baseForegroundColor = .white // `updateContents()` temporarily changes this.
        buttonConfig.baseBackgroundColor = .Signal.accent
        buttonConfig.cornerStyle = .capsule
        buttonConfig.contentInsets = .init(margin: 8) // 40 dp button given 24 dp icons
        buttonConfig.image = approvalMode.proceedButtonImage // also updated in `updateContents()`.

        let button = UIButton(
            configuration: buttonConfig,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.approvalFooterDelegateDidRequestProceed(self)
            },
        )
        button.isEnabled = isAllowedToProceed
        button.setContentHuggingHigh()
        button.setCompressionResistanceHigh()
        return button
    }()

    public func updateContents() {
        proceedButton.configuration?.image = approvalMode.proceedButtonImage
        proceedButton.accessibilityLabel = approvalMode.proceedButtonAccessibilityLabel

        switch approvalTextMode {
        case .none:
            textFieldContainer.isHidden = true
            textField.resignFirstResponder()
        case .active(let placeholderText):
            textFieldContainer.isHidden = false
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholderText,
                attributes: [.foregroundColor: UIColor.Signal.secondaryLabel],
            )
        }

        if approvalMode == .loading {
            // Show spinning activity indicator centered in the blue "Proceed" button.
            // To hide button icon when activity indicator is visible set it's color to `clear`.
            // Do not set `image` to nil because that would invalidate button size.

            if proceedLoadingIndicator == nil {
                let activityIndicator = UIActivityIndicatorView(style: .medium)
                activityIndicator.isHidden = true
                activityIndicator.color = .white
                activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                proceedButton.addSubview(activityIndicator)
                NSLayoutConstraint.activate([
                    activityIndicator.centerXAnchor.constraint(equalTo: proceedButton.centerXAnchor),
                    activityIndicator.centerYAnchor.constraint(equalTo: proceedButton.centerYAnchor),
                ])

                proceedLoadingIndicator = activityIndicator
            }
            proceedButton.configuration?.baseForegroundColor = .clear
            proceedLoadingIndicator?.isHidden = false
            proceedLoadingIndicator?.startAnimating()
        } else {
            proceedButton.configuration?.baseForegroundColor = .white
            proceedLoadingIndicator?.stopAnimating()
            proceedLoadingIndicator?.isHidden = true
        }
    }

    // MARK: - UITextFieldDelegate

    public func textFieldDidBeginEditing(_ textField: UITextField) {
        delegate?.approvalFooterDidBeginEditingText()
    }
}
