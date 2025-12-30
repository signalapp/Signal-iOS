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
}

// MARK: -

public protocol ApprovalFooterDelegate: AnyObject {
    func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView)

    func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode

    func approvalFooterDidBeginEditingText()
}

// MARK: -

public class ApprovalFooterView: UIView {
    public weak var delegate: ApprovalFooterDelegate? {
        didSet {
            updateContents()
        }
    }

    private let backgroundView = UIView()
    private let topStrokeView = UIView()
    private let hStackView = UIStackView()
    private let vStackView = UIStackView()

    private var textFieldBackgroundView: UIView?

    public var textInput: String? {
        approvalTextMode == .none ? nil : textField.text
    }

    private var approvalMode: ApprovalMode {
        guard let delegate else {
            return .send
        }
        return delegate.approvalMode(self)
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

    override init(frame: CGRect) {
        super.init(frame: frame)

        autoresizingMask = .flexibleHeight
        translatesAutoresizingMaskIntoConstraints = false

        layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        // We extend our background view below the keyboard to avoid any gaps.
        addSubview(backgroundView)
        backgroundView.autoPinWidthToSuperview()
        backgroundView.autoPinEdge(toSuperviewEdge: .top)
        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -30)

        addSubview(topStrokeView)
        topStrokeView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        topStrokeView.autoSetDimension(.height, toSize: .hairlineWidth)

        hStackView.addArrangedSubviews([labelScrollView, proceedButton])
        hStackView.axis = .horizontal
        hStackView.spacing = 12
        hStackView.alignment = .center

        vStackView.addArrangedSubviews([textFieldContainer, hStackView])
        vStackView.axis = .vertical
        vStackView.spacing = 16
        vStackView.alignment = .fill
        addSubview(vStackView)
        vStackView.autoPinEdgesToSuperviewMargins()

        updateContents()

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        applyTheme()
    }

    @objc
    private func applyTheme() {
        backgroundView.backgroundColor = Theme.keyboardBackgroundColor
        topStrokeView.backgroundColor = UIColor.Signal.opaqueSeparator
        namesLabel.textColor = Theme.secondaryTextAndIconColor
        textFieldBackgroundView?.backgroundColor = textfieldBackgroundColor
    }

    private var textfieldBackgroundColor: UIColor {
        OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        return CGSize.zero
    }

    // MARK: public

    private var namesText: String? { namesLabel.text }

    public func setNamesText(_ newValue: String?, animated: Bool) {
        let changes = {
            self.namesLabel.text = newValue

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

    // MARK: private subviews

    lazy var labelScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false

        scrollView.addSubview(namesLabel)
        namesLabel.autoPinEdgesToSuperviewEdges()
        namesLabel.autoMatch(.height, to: .height, of: scrollView)

        return scrollView
    }()

    lazy var namesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.dynamicTypeBody

        label.setContentHuggingLow()

        return label
    }()

    lazy var textField: UITextField = {
        let textField = UITextField()
        textField.delegate = self
        textField.font = UIFont.dynamicTypeBody
        textField.setCompressionResistanceHigh()
        return textField
    }()

    lazy var textFieldContainer: UIView = {
        var containerView: UIView = UIView()
        var contentView: UIView = UIView()

            // When we stop using Xcode 16, change var to let and move this
            // block to the `else` of the iOS 26 availability if statement.
            ; {
                let view = UIView()
                view.backgroundColor = textfieldBackgroundColor
                view.layer.cornerRadius = 10
                view.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 7)

                self.textFieldBackgroundView = view

                containerView = view
                contentView = view
            }()

#if compiler(>=6.2)
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.cornerConfiguration = .capsule()
            glassEffectView.contentView.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 11)

            containerView = glassEffectView
            contentView = glassEffectView.contentView
        }
#endif

        // I am at a loss as to why the text field always shrinks to 0
        // height, but this makes sure there's vertical space for it.
        let heightLabel = UILabel()
        heightLabel.isUserInteractionEnabled = false
        heightLabel.font = textField.font
        heightLabel.text = " "
        contentView.addSubview(heightLabel)
        heightLabel.autoPinEdgesToSuperviewMargins()
        heightLabel.setCompressionResistanceVerticalHigh()

        contentView.addSubview(textField)
        textField.autoPinEdgesToSuperviewMargins()

        return containerView
    }()

    var proceedLoadingIndicator = UIActivityIndicatorView(style: .medium)
    lazy var proceedButton: OWSButton = {
        let button = OWSButton.sendButton(
            imageName: self.approvalMode.proceedButtonImageName ?? Theme.iconName(.arrowRight),
        ) { [weak self] in
            guard let self else { return }
            self.delegate?.approvalFooterDelegateDidRequestProceed(self)
        }

        button.addSubview(proceedLoadingIndicator)
        proceedLoadingIndicator.autoCenterInSuperview()
        proceedLoadingIndicator.isHidden = true
        proceedLoadingIndicator.color = .white

        return button
    }()

    func updateContents() {
        proceedButton.setImage(imageName: approvalMode.proceedButtonImageName)
        proceedButton.accessibilityLabel = approvalMode.proceedButtonAccessibilityLabel

        switch approvalTextMode {
        case .none:
            textFieldContainer.isHidden = true
            textField.resignFirstResponder()
        case .active(let placeholderText):
            textFieldContainer.isHidden = false
            textField.placeholder = placeholderText
        }

        if approvalMode == .loading {
            proceedLoadingIndicator.isHidden = false
            proceedLoadingIndicator.startAnimating()
        } else {
            proceedLoadingIndicator.stopAnimating()
            proceedLoadingIndicator.isHidden = true
        }
    }
}

// MARK: -

private extension ApprovalMode {
    var proceedButtonAccessibilityLabel: String? {
        switch self {
        case .next: return CommonStrings.nextButton
        case .send: return MessageStrings.sendButton
        case .select: return CommonStrings.doneButton
        case .loading: return nil
        }
    }

    var proceedButtonImageName: String? {
        switch self {
        case .next: return Theme.iconName(.arrowRight)
        case .send: return Theme.iconName(.arrowUp)
        case .select: return Theme.iconName(.checkmark)
        case .loading: return nil
        }
    }
}

// MARK: - UITextFieldDelegate

extension ApprovalFooterView: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        delegate?.approvalFooterDidBeginEditingText()
    }
}
