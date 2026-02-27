//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

public protocol TextApprovalViewControllerDelegate: AnyObject {

    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft?)

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController)

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode
}

// MARK: -

public class TextApprovalViewController: OWSViewController, BodyRangesTextViewDelegate {

    public weak var delegate: TextApprovalViewControllerDelegate?

    // MARK: - Properties

    private let initialMessageBody: MessageBody
    private let linkPreviewFetchState: LinkPreviewFetchState

    private let textView = BodyRangesTextView()
    private let footerView = ApprovalFooterView()

    private var approvalMode: ApprovalMode {
        guard let delegate else {
            return .send
        }
        return delegate.textApprovalMode(self)
    }

    // MARK: - Initializers

    public init(messageBody: MessageBody) {
        initialMessageBody = messageBody
        linkPreviewFetchState = LinkPreviewFetchState(
            db: DependenciesBridge.shared.db,
            linkPreviewFetcher: SUIEnvironment.shared.linkPreviewFetcher,
            linkPreviewSettingStore: DependenciesBridge.shared.linkPreviewSettingStore,
        )

        super.init()

        linkPreviewFetchState.onStateChange = { [weak self] in self?.updateLinkPreviewView() }
    }

    // MARK: - View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        if let title = delegate?.textApprovalCustomTitle(self) {
            navigationItem.title = title
        } else {
            navigationItem.title = OWSLocalizedString(
                "MESSAGE_APPROVAL_DIALOG_TITLE",
                comment: "Title for the 'message approval' dialog.",
            )
        }

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            guard let self else { return }
            self.delegate?.textApprovalDidCancel(self)
        }

        let stackView = UIStackView(arrangedSubviews: [linkPreviewView, textView])
        stackView.axis = .vertical
        stackView.spacing = 12
        view.addSubview(stackView)
        view.addSubview(footerView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        footerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            footerView.topAnchor.constraint(equalTo: stackView.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        textView.bodyRangesDelegate = self
        textView.backgroundColor = .Signal.background
        textView.textColor = .Signal.label
        textView.font = UIFont.dynamicTypeBody
        textView.setMessageBody(initialMessageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)
        textView.contentInset = .zero
        textView.textContainerInset = .zero

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
        let linkPreviewView = LinkPreviewView(state: .loading)
        linkPreviewView.isHidden = true
        linkPreviewView.cancelButton.addAction(
            UIAction { [weak self] _ in
                self?.didTapDeleteLinkPreview()
            },
            for: .primaryActionTriggered,
        )
        return linkPreviewView
    }()

    private func updateLinkPreviewText() {
        linkPreviewFetchState.update(textView.messageBodyForSending)
    }

    private func updateLinkPreviewView() {
        switch linkPreviewFetchState.currentState {
        case .none, .failed:
            linkPreviewView.isHidden = true

        case .loading, .loaded:
            linkPreviewView.configure(withState: linkPreviewFetchState.currentState)
            linkPreviewView.isHidden = false
        }
    }

    private func didTapDeleteLinkPreview() {
        AssertIsOnMainThread()

        linkPreviewFetchState.disable()
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
        updateLinkPreviewText()
    }

    public func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {}

    public func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        nil
    }

    public func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        nil
    }

    public func textViewMentionPickerPossibleAcis(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [Aci] {
        []
    }

    public func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        .composing(textViewColor: textView.textColor)
    }

    public func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        .default
    }

    // We want to invalidate the cache but reuse it within this same controller.
    private let mentionCacheInvalidationKey = UUID().uuidString

    public func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        mentionCacheInvalidationKey
    }
}

// MARK: -

extension TextApprovalViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        let linkPreviewDraft = linkPreviewFetchState.linkPreviewDraftIfLoaded
        delegate?.textApproval(self, didApproveMessage: textView.messageBodyForSending, linkPreviewDraft: linkPreviewDraft)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }

    public func approvalFooterDidBeginEditingText() {}
}
