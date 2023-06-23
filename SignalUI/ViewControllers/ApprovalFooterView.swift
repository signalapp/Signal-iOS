//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

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

    private var textfieldBackgroundView: UIView?

    public var textInput: String? {
        approvalTextMode == .none ? nil : textfield.text
    }

    private var approvalMode: ApprovalMode {
        guard let delegate = delegate else {
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
        topStrokeView.autoSetDimension(.height, toSize: CGHairlineWidth())

        hStackView.addArrangedSubviews([labelScrollView, proceedButton])
        hStackView.axis = .horizontal
        hStackView.spacing = 12
        hStackView.alignment = .center

        vStackView.addArrangedSubviews([textfieldStack, hStackView])
        vStackView.axis = .vertical
        vStackView.spacing = 16
        vStackView.alignment = .fill
        addSubview(vStackView)
        vStackView.autoPinEdgesToSuperviewMargins()

        updateContents()

        let textfieldBackgroundView = textfieldStack.addBackgroundView(withBackgroundColor: textfieldBackgroundColor)
        textfieldBackgroundView.layer.cornerRadius = 10
        self.textfieldBackgroundView = textfieldBackgroundView

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        applyTheme()
    }

    @objc
    private func applyTheme() {
        backgroundView.backgroundColor = Theme.keyboardBackgroundColor
        topStrokeView.backgroundColor = Theme.hairlineColor
        namesLabel.textColor = Theme.secondaryTextAndIconColor
        textfieldBackgroundView?.backgroundColor = textfieldBackgroundColor
    }

    private var textfieldBackgroundColor: UIColor {
        OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
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

    lazy var textfield: TextFieldWithPlaceholder = {
        let textfield = TextFieldWithPlaceholder()
        textfield.delegate = self
        textfield.font = UIFont.dynamicTypeBody
        return textfield
    }()

    lazy var textfieldStack: UIStackView = {
        let textfieldStack = UIStackView(arrangedSubviews: [textfield])
        textfieldStack.axis = .vertical
        textfieldStack.alignment = .fill
        textfieldStack.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 7)
        textfieldStack.isLayoutMarginsRelativeArrangement = true
        return textfieldStack
    }()

    var proceedLoadingIndicator = UIActivityIndicatorView(style: .medium)
    lazy var proceedButton: OWSButton = {
		let button = OWSButton.sendButton(
            imageName: self.approvalMode.proceedButtonImageName ?? Theme.iconName(.arrowRight)
		) { [weak self] in
            guard let self = self else { return }
            self.delegate?.approvalFooterDelegateDidRequestProceed(self)
        }

        button.addSubview(proceedLoadingIndicator)
        proceedLoadingIndicator.autoCenterInSuperview()
        proceedLoadingIndicator.isHidden = true

        return button
    }()

    func updateContents() {
        proceedButton.setImage(imageName: approvalMode.proceedButtonImageName)
        proceedButton.accessibilityLabel = approvalMode.proceedButtonAccessibilityLabel

        switch approvalTextMode {
        case .none:
            textfieldStack.isHidden = true
            textfield.resignFirstResponder()
        case .active(let placeholderText):
            textfieldStack.isHidden = false
            textfield.placeholderText = placeholderText
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

fileprivate extension ApprovalMode {
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

// MARK: -

extension ApprovalFooterView: TextFieldWithPlaceholderDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        delegate?.approvalFooterDidBeginEditingText()
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
}
