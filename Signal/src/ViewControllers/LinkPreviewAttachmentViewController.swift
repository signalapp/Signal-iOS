//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol LinkPreviewAttachmentViewControllerDelegate: AnyObject {
    func linkPreviewAttachmentViewController(
        _ viewController: LinkPreviewAttachmentViewController,
        didFinishWith linkPreview: OWSLinkPreviewDraft,
    )
}

class LinkPreviewAttachmentViewController: InteractiveSheetViewController {

    weak var delegate: LinkPreviewAttachmentViewControllerDelegate?

    private let linkPreviewFetchState: LinkPreviewFetchState

    init(_ linkPreview: OWSLinkPreviewDraft? = nil) {
        self.linkPreviewFetchState = LinkPreviewFetchState(
            db: DependenciesBridge.shared.db,
            linkPreviewFetcher: SUIEnvironment.shared.linkPreviewFetcher,
            linkPreviewSettingStore: DependenciesBridge.shared.linkPreviewSettingStore,
            onlyParseIfEnabled: false,
            linkPreviewDraft: linkPreview,
        )
        super.init()
        self.linkPreviewFetchState.onStateChange = { [weak self] in self?.updateLinkPreview(animated: true) }
    }

    private let linkPreviewPanel = LinkPreviewPanel()

    private static let textFieldHeight: CGFloat = 40

    private let textField: UITextField = {
        let textField = UITextField()
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.font = .dynamicTypeBodyClamped
        textField.adjustsFontForContentSizeCategory = true
        textField.keyboardType = .URL
        textField.textColor = .Signal.label
        textField.textContentType = .URL
        textField.attributedPlaceholder = NSAttributedString(
            string: OWSLocalizedString(
                "STORY_COMPOSER_URL_FIELD_PLACEHOLDER",
                comment: "Placeholder text for URL input field in Text Story composer UI.",
            ),
            attributes: [.foregroundColor: UIColor.Signal.secondaryLabel],
        )
        textField.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return textField
    }()

    private lazy var textFieldContainer: UIView = {
        let view = PillView()
        view.backgroundColor = .Signal.tertiaryFill
        view.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.textFieldHeight),

            textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            textField.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }()

    private lazy var doneButton: UIButton = {
        let button = UIButton(
            configuration: .tintedRoundMedia(image: Theme.iconImage(.checkmark), size: Self.textFieldHeight),
            primaryAction: UIAction { [weak self] _ in
                self?.doneButtonPressed()
            },
        )
        button.accessibilityLabel = CommonStrings.doneButton
        return button
    }()

    private lazy var inputFieldContainer: UIView = {
        let stackView = UIStackView(arrangedSubviews: [textFieldContainer, doneButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        return stackView
    }()

    private var bottomContentMarginConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        super.allowsExpansion = false

        overrideUserInterfaceStyle = .dark

        contentView.preservesSuperviewLayoutMargins = true
        contentView.superview?.preservesSuperviewLayoutMargins = true

        let stackView = UIStackView(arrangedSubviews: [linkPreviewPanel, inputFieldContainer])
        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        let bottomEdgeConstraint = contentView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 12)
        bottomEdgeConstraint.priority = .defaultLow
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.safeAreaLayoutGuide.bottomAnchor),
            bottomEdgeConstraint,
        ])

        // Bottom margin is flexible so that text field is positioned above the onscreen keyboard.
        bottomContentMarginConstraint = bottomEdgeConstraint

        textField.addAction(
            UIAction { [weak self] _ in self?.textDidChange() },
            for: .editingChanged,
        )

        if let initialLinkPreview = linkPreviewFetchState.linkPreviewDraftIfLoaded {
            textField.text = initialLinkPreview.urlString
        }

        updateLinkPreview(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Resize the view to it's final bounds so that resizing
        // isn't animated with keyboard.
        if let windowBounds = CurrentAppContext().mainWindow?.bounds {
            UIView.performWithoutAnimation {
                self.view.bounds = windowBounds
                self.updateSheetHeight()
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
            }
        }

        textField.becomeFirstResponder()
        startObservingKeyboardNotifications()
    }

    override var canBecomeFirstResponder: Bool { true }

    private var _sheetHeight: CGFloat = 0
    private func updateSheetHeight() {
        guard let sheetView = contentView.superview else { return }

        let sheetSize = sheetView.systemLayoutSizeFitting(
            .init(width: maxWidth, height: view.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        if _sheetHeight != sheetSize.height {
            _sheetHeight = sheetSize.height
            if _sheetHeight > 0 {
                minimizedHeight = _sheetHeight
            } else {
                minimizedHeight = InteractiveSheetViewController.Constants.defaultMinHeight
            }
        }
    }

    private func textDidChange() {
        let text = textField.text ?? ""
        linkPreviewFetchState.update(
            MessageBody(text: text, ranges: .empty),
            prependSchemeIfNeeded: true,
        )
    }

    private func doneButtonPressed() {
        guard case .draft(let linkPreview) = linkPreviewPanel.state else { return }
        delegate?.linkPreviewAttachmentViewController(self, didFinishWith: linkPreview)
    }

    // MARK: - Keyboard Handling

    private func startObservingKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotification(_:)),
            name: UIResponder.keyboardDidHideNotification,
            object: nil,
        )
    }

    @objc
    private func handleKeyboardNotification(_ notification: Notification) {
        guard
            let bottomContentMarginConstraint,
            let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        let keyboardFrame = view.convert(endFrame, from: nil)
        let viewFrame = view.bounds

        let keyboardHeight: CGFloat
        if keyboardFrame.minY >= viewFrame.maxY {
            // Offscreen
            keyboardHeight = 0
        } else if keyboardFrame.maxY < viewFrame.maxY {
            // Floating
            keyboardHeight = 0
        } else {
            keyboardHeight = keyboardFrame.height
        }

        let constraintValue = keyboardHeight + 12

        guard bottomContentMarginConstraint.constant != constraintValue else { return }

        let layoutUpdateBlock = {
            bottomContentMarginConstraint.constant = constraintValue
            self.updateSheetHeight()
        }
        if
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve)
        {
            let animator = UIViewPropertyAnimator(
                duration: animationDuration,
                curve: animationCurve,
            )
            animator.addAnimations(layoutUpdateBlock)
            animator.startAnimation()
        } else {
            UIView.performWithoutAnimation {
                layoutUpdateBlock()
            }
        }
    }

    // MARK: - Link Preview fetching

    private func updateLinkPreview(animated: Bool) {
        let newState: LinkPreviewPanel.State
        switch (linkPreviewFetchState.currentState, linkPreviewFetchState.currentUrl) {
        case (.none, _):
            newState = .placeholder
        case (.loading, _):
            newState = .loading
        case (.loaded(let linkPreviewDraft), _):
            newState = .draft(linkPreviewDraft)
        case (.failed, .some(let linkPreviewUrl)):
            newState = .draft(OWSLinkPreviewDraft(url: linkPreviewUrl, title: nil, isForwarded: false))
        case (.failed, .none):
            owsFailDebug("Must have linkPreviewUrl in the .failed state.")
            newState = .placeholder
        }
        linkPreviewPanel.setState(newState, animated: animated)

        let isDoneEnabled: Bool
        if case .draft = newState {
            isDoneEnabled = true
        } else {
            isDoneEnabled = false
        }
        doneButton.isEnabled = isDoneEnabled

        updateSheetHeight()
    }

    private class LinkPreviewPanel: UIView {

        enum State: Equatable {
            case placeholder
            case loading
            case draft(OWSLinkPreviewDraft)
            case error
        }

        private var _internalState: State = .placeholder
        var state: State {
            get { _internalState }
            set { setState(newValue, animated: false) }
        }

        func setState(_ state: State, animated: Bool) {
            guard _internalState != state else { return }
            _internalState = state
            updateContentViewForCurrentState(animated: animated)
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            NSLayoutConstraint.autoSetPriority(.defaultLow + 10) {
                autoSetDimension(.height, toSize: 100)
            }
            updateContentViewForCurrentState(animated: false)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - Layout

        private lazy var placeholderView: UIView = {
            let icon = UIImageView(image: UIImage(imageLiteralResourceName: "link"))
            icon.tintColor = .Signal.secondaryLabel
            icon.setContentHuggingHigh()

            let label = UILabel()
            label.font = .dynamicTypeSubheadlineClamped
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byWordWrapping
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .Signal.secondaryLabel
            label.text = OWSLocalizedString(
                "STORY_COMPOSER_LINK_PREVIEW_PLACEHOLDER",
                comment: "Displayed in text story composer when user is about to attach a link with preview",
            )

            let stackView = UIStackView(arrangedSubviews: [icon, label])
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = 8
            return stackView
        }()

        private lazy var activityIndicatorView = UIActivityIndicatorView(style: .large)
        private lazy var loadingView: UIView = {
            let view = UIView()
            view.addSubview(activityIndicatorView)
            activityIndicatorView.autoCenterInSuperview()
            activityIndicatorView.tintColor = .Signal.label
            return view
        }()

        private var linkPreviewView: TextAttachmentView.LinkPreviewView?

        private lazy var errorView: UIView = {
            let exclamationMark = UIImageView(image: UIImage(imageLiteralResourceName: "error-circle"))
            exclamationMark.tintColor = .Signal.warningLabel
            exclamationMark.setContentHuggingHigh()

            let label = UILabel()
            label.font = .dynamicTypeSubheadlineClamped
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byWordWrapping
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .Signal.warningLabel
            label.text = OWSLocalizedString(
                "STORY_COMPOSER_LINK_PREVIEW_ERROR",
                comment: "Displayed when failed to fetch link preview in Text Story composer.",
            )

            let stackView = UIStackView(arrangedSubviews: [exclamationMark, label])
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = 8
            return stackView
        }()

        private var contentViews = Set<UIView>()

        private func loadContentView(forState state: State) -> UIView {
            if let linkPreviewView {
                linkPreviewView.removeFromSuperview()
                contentViews.remove(linkPreviewView)
                self.linkPreviewView = nil
            }

            let view: UIView = {
                switch state {
                case .placeholder:
                    return placeholderView
                case .loading:
                    return loadingView
                case .draft(let linkPreviewDraft):
                    let state: LinkPreviewState
                    if let callLink = CallLink(url: linkPreviewDraft.url) {
                        state = LinkPreviewCallLink(previewType: .draft(linkPreviewDraft), callLink: callLink)
                    } else {
                        state = LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft)
                    }
                    return TextAttachmentView.LinkPreviewView(
                        linkPreview: state,
                        isDraft: true,
                    )
                case .error:
                    return errorView
                }
            }()
            guard !contentViews.contains(view) else { return view }

            view.isHidden = true
            contentViews.insert(view)
            addSubview(view)
            view.autoPinWidthToSuperview()
            view.autoVCenterInSuperview()
            view.autoPinHeightToSuperview(relation: .lessThanOrEqual)
            return view
        }

        private func updateContentViewForCurrentState(animated: Bool) {
            let viewToMakeVisible = loadContentView(forState: state)
            viewToMakeVisible.setIsHidden(false, animated: animated)
            if case .draft = state {
                linkPreviewView = viewToMakeVisible as? TextAttachmentView.LinkPreviewView
            } else if case .loading = state {
                activityIndicatorView.startAnimating()
            }

            let viewsToHide = contentViews.subtracting([viewToMakeVisible])
            viewsToHide.forEach { $0.setIsHidden(true, animated: animated) }
        }
    }
}
