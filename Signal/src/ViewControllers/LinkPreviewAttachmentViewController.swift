//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalUI
import UIKit

protocol LinkPreviewAttachmentViewControllerDelegate: AnyObject {
    func linkPreviewAttachmentViewController(_ viewController: LinkPreviewAttachmentViewController,
                                             didFinishWith linkPreview: OWSLinkPreviewDraft)
}

class LinkPreviewAttachmentViewController: InteractiveSheetViewController {

    weak var delegate: LinkPreviewAttachmentViewControllerDelegate?

    init(_ linkPreview: OWSLinkPreviewDraft?) {
        super.init()
        self.linkPreview = linkPreview
        self.currentPreviewUrl = linkPreview?.url
    }

    convenience required init() {
        self.init(nil)
    }

    private let linkPreviewPanel = LinkPreviewPanel()

    private let textField: UITextField = {
        let textField = UITextField()
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.font = .ows_dynamicTypeBodyClamped
        textField.keyboardAppearance = .dark
        textField.keyboardType = .URL
        textField.textColor = .ows_gray05
        textField.textContentType = .URL
        textField.attributedPlaceholder = NSAttributedString(
            string: NSLocalizedString("STORY_COMPOSER_URL_FIELD_PLACEHOLDER",
                                      value: "Type or paste a URL",
                                      comment: "Placeholder text for URL input field in Text Story composer UI."),
            attributes: [ .foregroundColor: UIColor.ows_gray25 ])
        return textField
    }()
    private lazy var textFieldContainer: UIView = {
        let view = PillView()
        view.backgroundColor = .ows_gray80
        view.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        view.addSubview(textField)
        textField.autoPinEdgesToSuperviewMargins()
        return view
    }()
    private let doneButton: UIButton = {
        let button = RoundMediaButton(image: UIImage(imageLiteralResourceName: "check-24"),
                                      backgroundStyle: .solid(.ows_accentBlue))
        button.layoutMargins = .zero
        button.contentEdgeInsets = UIEdgeInsets(margin: 10)
        button.setContentHuggingHigh()
        return button
    }()
    private lazy var inputFieldContainer: UIView = {
        let stackView = UIStackView(arrangedSubviews: [ textFieldContainer, doneButton ])
        stackView.axis = .horizontal
        stackView.spacing = 10
        return stackView
    }()
    private var bottomContentMarginConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        contentView.preservesSuperviewLayoutMargins = true
        contentView.superview?.preservesSuperviewLayoutMargins = true

        let stackView = UIStackView(arrangedSubviews: [ linkPreviewPanel, inputFieldContainer ])
        stackView.axis = .vertical
        stackView.spacing = 24
        contentView.addSubview(stackView)
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

        // Bottom margin is flexible so that text field is positioned above the onscreen keyboard.
        bottomContentMarginConstraint = contentView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 12)
        bottomContentMarginConstraint?.priority = .defaultLow
        bottomContentMarginConstraint?.isActive = true

        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        doneButton.addTarget(self, action: #selector(doneButtonPressed), for: .touchUpInside)

        if let linkPreview = linkPreview {
            textField.text = linkPreview.urlString
            linkPreviewPanel.setState(.draft(linkPreview), animated: false)
        }

        updateUIOnLinkPreviewStateChange()
   }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Resize the view to it's final bounds so that resizing
        // isn't animated with keyboard.
        UIView.performWithoutAnimation {
            self.view.bounds = UIScreen.main.bounds
            self.updateSheetHeight()
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }

        textField.becomeFirstResponder()
        startObservingKeyboardNotifications()
    }

    override var canBecomeFirstResponder: Bool { true }

    override var sheetBackgroundColor: UIColor { .ows_gray95 }

    private var sheetHeight: CGFloat = 0
    private func updateSheetHeight() {
        guard let sheetView = contentView.superview else { return }

        let sheetSize = sheetView.systemLayoutSizeFitting(.init(width: maxWidth, height: .greatestFiniteMagnitude),
                                                          withHorizontalFittingPriority: .required,
                                                          verticalFittingPriority: .fittingSizeLevel)
        if sheetHeight != sheetSize.height {
            sheetHeight = sheetSize.height
            heightConstraint.constant = sheetHeight
        }
    }

    override var minHeight: CGFloat {
        guard sheetHeight > 0 else { return super.minHeight }
        return sheetHeight
    }

    override var maximizedHeight: CGFloat {
        guard sheetHeight > 0 else { return super.maximizedHeight }
        return sheetHeight
    }

    private func updateUIOnLinkPreviewStateChange() {
        doneButton.isEnabled = linkPreview != nil
        updateSheetHeight()
    }

    @objc
    private func textDidChange() {
        updateLinkPreviewIfNecessary()
    }

    @objc
    private func doneButtonPressed() {
        guard let linkPreview = linkPreview else { return }
        delegate?.linkPreviewAttachmentViewController(self, didFinishWith: linkPreview)
    }

    // MARK: - Keyboard Handling

    private func startObservingKeyboardNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleKeyboardNotification(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleKeyboardNotification(_:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleKeyboardNotification(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    @objc
    private func handleKeyboardNotification(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let beginFrame = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        guard beginFrame.height != endFrame.height || beginFrame.minY == UIScreen.main.bounds.height else { return }

        let layoutUpdateBlock = {
            self.bottomContentMarginConstraint?.constant = endFrame.height + 12
            self.updateSheetHeight()
        }
        if
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve)
        {
            UIView.beginAnimations("sheetResize", context: nil)
            UIView.setAnimationBeginsFromCurrentState(true)
            UIView.setAnimationCurve(animationCurve)
            UIView.setAnimationDuration(animationDuration)
            layoutUpdateBlock()
            view.setNeedsLayout()
            view.layoutIfNeeded()
            UIView.commitAnimations()
        } else {
            UIView.performWithoutAnimation {
                layoutUpdateBlock()
            }
        }
    }

    // MARK: - Link Preview fetching

    private var linkPreview: OWSLinkPreviewDraft?

    private var currentPreviewUrl: URL? {
        didSet {
            guard currentPreviewUrl != oldValue else { return }
            guard let previewUrl = currentPreviewUrl else { return }

            linkPreviewManager.fetchLinkPreview(for: previewUrl).done(on: .main) { [weak self] draft in
                guard let self = self else { return }
                guard self.currentPreviewUrl == previewUrl else { return }
                self.displayLinkPreview(draft)
            }.catch(on: .main) { [weak self] error in
                guard let self = self else { return }
                guard self.currentPreviewUrl == previewUrl else { return }
                self.clearLinkPreview(withError: error)
            }
        }
    }

    private func updateLinkPreviewIfNecessary() {
        guard let trimmedText = textField.text?.ows_stripped(), !trimmedText.isEmpty else {
            clearLinkPreview()
            return
        }
        guard let previewUrl = linkPreviewManager.findFirstValidUrl(in: trimmedText) else { return clearLinkPreview() }
        currentPreviewUrl = previewUrl
    }

    private func displayLinkPreview(_ linkPreview: OWSLinkPreviewDraft) {
        self.linkPreview = linkPreview
        linkPreviewPanel.setState(.draft(linkPreview), animated: true)
        updateUIOnLinkPreviewStateChange()
    }

    private func clearLinkPreview(withError error: Error? = nil) {
        currentPreviewUrl = nil
        linkPreview = nil
        if let error = error, case LinkPreviewError.fetchFailure = error {
            linkPreviewPanel.setState(.error, animated: true)
        } else {
            linkPreviewPanel.setState(.placeholder, animated: true)
        }
        updateUIOnLinkPreviewStateChange()
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
            updateContentViewForCurrentState(animated: false)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 100) }

        // MARK: - Layout

        private lazy var placeholderView: UIView = {
            let icon = UIImageView(image: UIImage(imageLiteralResourceName: "link-diagonal"))
            icon.tintColor = .ows_gray45
            icon.setContentHuggingHigh()

            let label = UILabel()
            label.font = .ows_dynamicTypeBody2Clamped
            label.lineBreakMode = .byWordWrapping
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .ows_gray45
            label.text = NSLocalizedString("STORY_COMPOSER_LINK_PREVIEW_PLACEHOLDER",
                                           value: "Share a link with viewers of your story",
                                           comment: "Displayed in text story composer when user is about to attach a link with preview")

            let stackView = UIStackView(arrangedSubviews: [ icon, label ])
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = 8
            return stackView
        }()

        private lazy var activityIndicatorView = UIActivityIndicatorView(style: .whiteLarge)
        private lazy var loadingView: UIView = {
            let view = UIView()
            view.addSubview(activityIndicatorView)
            activityIndicatorView.autoCenterInSuperview()
            return view
        }()

        private var linkPreviewView: TextAttachmentView.LinkPreviewView?

        private lazy var errorView: UIView = {
            let exclamationMark = UIImageView(image: UIImage(imageLiteralResourceName: "error-outline-24"))
            exclamationMark.tintColor = .ows_gray15
            exclamationMark.setContentHuggingHigh()

            let label = UILabel()
            label.font = .ows_dynamicTypeBody2Clamped
            label.lineBreakMode = .byWordWrapping
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .ows_gray05
            label.text = NSLocalizedString("STORY_COMPOSER_LINK_PREVIEW_ERROR",
                                           value: "Couldn't load link. Check your connection and try again.",
                                           comment: "Displayed when failed to fetch link preview in Text Story composer.")

            let stackView = UIStackView(arrangedSubviews: [ exclamationMark, label ])
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = 8
            return stackView
        }()

        private var contentViews = Set<UIView>()

        private func loadContentView(forState state: State) -> UIView {
            if let linkPreviewView = linkPreviewView {
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
                    return TextAttachmentView.LinkPreviewView(linkPreview: LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft))
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
            }

            let viewsToHide = contentViews.subtracting([viewToMakeVisible])
            viewsToHide.forEach { $0.setIsHidden(true, animated: animated) }
        }
    }
}
