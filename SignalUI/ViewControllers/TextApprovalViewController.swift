//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol TextApprovalViewControllerDelegate: AnyObject {

    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?)

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController)

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode
}

// MARK: -

final public class TextApprovalViewController: OWSViewController, BodyRangesTextViewDelegate {

    public weak var delegate: TextApprovalViewControllerDelegate?

    // MARK: - Properties

    private let initialMessageBody: MessageBody
    private let linkPreviewFetchState: LinkPreviewFetchState

    private let textView = BodyRangesTextView()
    private let footerView = ApprovalFooterView()

    private var approvalMode: ApprovalMode {
        guard let delegate = delegate else {
            return .send
        }
        return delegate.textApprovalMode(self)
    }

    // MARK: - Initializers

    public init(messageBody: MessageBody) {
        self.initialMessageBody = messageBody
        self.linkPreviewFetchState = LinkPreviewFetchState(
            db: DependenciesBridge.shared.db,
            linkPreviewFetcher: SUIEnvironment.shared.linkPreviewFetcher,
            linkPreviewSettingStore: DependenciesBridge.shared.linkPreviewSettingStore
        )

        super.init()

        self.linkPreviewFetchState.onStateChange = { [weak self] in self?.updateLinkPreviewView() }
    }

    // MARK: - View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        if let title = delegate?.textApprovalCustomTitle(self) {
            self.navigationItem.title = title
        } else {
            self.navigationItem.title = OWSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE",
                                                          comment: "Title for the 'message approval' dialog.")
        }

        self.navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            guard let self else { return }
            self.delegate?.textApprovalDidCancel(self)
        }

        footerView.delegate = self

        // Don't allow interactive dismissal.
        isModalInPresentation = true
    }

    private func updateSendButton() {
        guard
            !textView.isEmpty,
            let recipientsDescription = delegate?.textApprovalRecipientsDescription(self)
        else {
            footerView.isHidden = true
            return
        }
        footerView.setNamesText(recipientsDescription, animated: false)
        footerView.isHidden = false
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateSendButton()
        updateLinkPreviewText()

        textView.becomeFirstResponder()
    }

    // MARK: - Link Previews

    private lazy var linkPreviewView: LinkPreviewView = {
        let linkPreviewView = LinkPreviewView(draftDelegate: self)
        linkPreviewView.isHidden = true
        return linkPreviewView
    }()

    private func updateLinkPreviewText() {
        linkPreviewFetchState.update(textView.messageBodyForSending)
    }

    private func updateLinkPreviewView() {
        switch linkPreviewFetchState.currentState {
        case .none, .failed:
            linkPreviewView.isHidden = true
        case .loading:
            linkPreviewView.configureForNonCVC(state: LinkPreviewLoading(linkType: .preview), isDraft: true)
            linkPreviewView.isHidden = false
        case .loaded(let linkPreviewDraft):
            let state: LinkPreviewState
            if let callLink = CallLink(url: linkPreviewDraft.url) {
                state = LinkPreviewCallLink(previewType: .draft(linkPreviewDraft), callLink: callLink)
            } else {
                state = LinkPreviewDraft(linkPreviewDraft: linkPreviewDraft)
            }
            linkPreviewView.configureForNonCVC(state: state, isDraft: true)
            linkPreviewView.isHidden = false
        }
    }

    // MARK: - Create Views

    public override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        let stackView = UIStackView(arrangedSubviews: [linkPreviewView, textView, footerView])
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        // Text View
        textView.bodyRangesDelegate = self
        textView.backgroundColor = Theme.backgroundColor
        textView.textColor = Theme.primaryTextColor
        textView.font = UIFont.dynamicTypeBody
        textView.setMessageBody(self.initialMessageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)
        textView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
        updateLinkPreviewText()
    }

    public func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        return nil
    }

    public func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        return nil
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [SignalServiceAddress] {
        return []
    }

    public func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composing(textViewColor: textView.textColor)
    }

    public func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        return .default
    }

    // We want to invalidate the cache but reuse it within this same controller.
    private let mentionCacheInvalidationKey = UUID().uuidString

    public func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return mentionCacheInvalidationKey
    }
}

// MARK: -

extension TextApprovalViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        let linkPreviewDraft = linkPreviewFetchState.linkPreviewDraftIfLoaded
        delegate?.textApproval(self, didApproveMessage: self.textView.messageBodyForSending, linkPreviewDraft: linkPreviewDraft)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }

    public func approvalFooterDidBeginEditingText() {}
}

// MARK: -

extension TextApprovalViewController: LinkPreviewViewDraftDelegate {
    public func linkPreviewDidCancel() {
        linkPreviewFetchState.disable()
    }
}
