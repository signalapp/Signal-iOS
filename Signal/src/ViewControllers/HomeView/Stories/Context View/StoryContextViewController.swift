//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI
import BonMot
import Lottie

protocol StoryContextViewControllerDelegate: AnyObject {
    func storyContextViewControllerWantsTransitionToNextContext(
        _ storyContextViewController: StoryContextViewController,
        loadPositionIfRead: StoryContextViewController.LoadPosition
    )
    func storyContextViewControllerWantsTransitionToPreviousContext(
        _ storyContextViewController: StoryContextViewController,
        loadPositionIfRead: StoryContextViewController.LoadPosition
    )
    func storyContextViewController(_ storyContextViewController: StoryContextViewController, contextAfter context: StoryContext) -> StoryContext?
    func storyContextViewControllerDidPause(_ storyContextViewController: StoryContextViewController)
    func storyContextViewControllerDidResume(_ storyContextViewController: StoryContextViewController)
    func storyContextViewControllerShouldOnlyRenderMyStories(_ storyContextViewController: StoryContextViewController) -> Bool

    func storyContextViewControllerShouldBeMuted(_ storyContextViewController: StoryContextViewController) -> Bool
}

class StoryContextViewController: OWSViewController {
    let context: StoryContext

    weak var delegate: StoryContextViewControllerDelegate?

    private lazy var playbackProgressView = StoryPlaybackProgressView()

    private var items = [StoryItem]()
    var currentItem: StoryItem? {
        didSet {
            currentItemWasUpdated(messageDidChange: oldValue?.message.uniqueId != currentItem?.message.uniqueId)
        }
    }
    var currentItemMediaView: StoryItemMediaView?

    var allowsReplies: Bool {
        guard let currentItem = currentItem else {
            return false
        }
        return currentItem.message.localUserAllowedToReply
    }

    var loadMessage: StoryMessage?

    enum Action {
        case none
        case presentReplies
        case presentInfo
    }
    var action: Action = .none

    enum LoadPosition {
        case `default`
        case newest
        case oldest
    }
    private(set) var loadPositionIfRead: LoadPosition

    private(set) lazy var contextMenuGenerator = StoryContextMenuGenerator(presentingController: self, delegate: self)

    required init(context: StoryContext, loadPositionIfRead: LoadPosition = .default, delegate: StoryContextViewControllerDelegate) {
        self.context = context
        self.loadPositionIfRead = loadPositionIfRead
        super.init()
        self.delegate = delegate
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetForPresentation() {
        pauseTime = nil
        lastTransitionTime = nil
        if let currentItemMediaView = currentItemMediaView {
            // Restart playback for the current item
            currentItemMediaView.reset()
            updateProgressState()
        } else {
            // If a specific message was specified to load to, present that first.
            if let loadMessage = loadMessage, let item = items.first(where: {
                $0.message.uniqueId == loadMessage.uniqueId
            }) {
                currentItem = item

            // Otherwise, if there's an unviewed story, we always want to present that first.
            } else if let firstUnviewedStory = items.first(where: {
                $0.message.localUserViewedTimestamp == nil
            }) {
                currentItem = firstUnviewedStory
            } else {
                switch loadPositionIfRead {
                case .newest:
                    currentItem = items.last
                case .oldest, .default:
                    currentItem = items.first
                }
            }

            // For subsequent loads, use the default position.
            loadPositionIfRead = .default
            loadMessage = nil

            switch action {
            case .none:
                break
            case .presentReplies:
                presentRepliesAndViewsSheet()
                action = .none
            case .presentInfo:
                presentInfoSheet()
                action = .none
            }
        }

        playbackProgressView.alpha = 1
        closeButton.alpha = 1
        repliesAndViewsButton.alpha = 1

        if onboardingOverlay.isDisplaying {
            pause(hideChrome: true)
        }
    }

    func updateMuteState() {
        currentItemMediaView?.updateMuteState()
    }

    func transitionToNextItem(nextContextLoadPositionIfRead: LoadPosition = .default) {
        guard let currentItem = currentItem,
              let currentItemIndex = items.firstIndex(of: currentItem),
              let itemAfter = items[safe: currentItemIndex.advanced(by: 1)] else {
                  delegate?.storyContextViewControllerWantsTransitionToNextContext(self, loadPositionIfRead: nextContextLoadPositionIfRead)
                  return
              }

        self.currentItem = itemAfter
    }

    func transitionToPreviousItem(previousContextLoadPositionIfRead: LoadPosition = .default) {
        guard let currentItem = currentItem,
              let currentItemIndex = items.firstIndex(of: currentItem),
              let itemBefore = items[safe: currentItemIndex.advanced(by: -1)] else {
                  delegate?.storyContextViewControllerWantsTransitionToPreviousContext(self, loadPositionIfRead: previousContextLoadPositionIfRead)
                  return
              }

        self.currentItem = itemBefore
    }

    private lazy var leftTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapLeft))
    private lazy var rightTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapRight))
    private lazy var pauseGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
    private lazy var zoomPinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchZoom))
    private lazy var zoomPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePinchZoom))

    private lazy var closeButton = OWSButton(imageName: "x-24", tintColor: .ows_white)

    private lazy var mediaViewContainer = UIView()

    private lazy var onboardingOverlay = StoryContextOnboardingOverlayView(delegate: self)

    private lazy var sendingIndicatorStackView = UIStackView()

    private lazy var repliesAndViewsButton = OWSButton()
    override func viewDidLoad() {
        super.viewDidLoad()

        view.layer.masksToBounds = true

        view.addGestureRecognizer(leftTapGestureRecognizer)
        view.addGestureRecognizer(rightTapGestureRecognizer)
        view.addGestureRecognizer(pauseGestureRecognizer)
        view.addGestureRecognizer(zoomPinchGestureRecognizer)
        view.addGestureRecognizer(zoomPanGestureRecognizer)

        leftTapGestureRecognizer.delegate = self
        rightTapGestureRecognizer.delegate = self
        pauseGestureRecognizer.delegate = self
        zoomPinchGestureRecognizer.delegate = self
        zoomPanGestureRecognizer.delegate = self
        pauseGestureRecognizer.minimumPressDuration = 0.2

        leftTapGestureRecognizer.require(toFail: pauseGestureRecognizer)
        rightTapGestureRecognizer.require(toFail: pauseGestureRecognizer)

        view.addSubview(mediaViewContainer)
        view.addSubview(onboardingOverlay)

        onboardingOverlay.autoPinEdges(toEdgesOf: mediaViewContainer)

        repliesAndViewsButton.block = { [weak self] in self?.presentRepliesAndViewsSheet() }
        repliesAndViewsButton.autoSetDimension(.height, toSize: 64)
        repliesAndViewsButton.setTitleColor(Theme.darkThemePrimaryColor, for: .normal)
        view.addSubview(repliesAndViewsButton)
        repliesAndViewsButton.autoPinEdge(.leading, to: .leading, of: mediaViewContainer)
        repliesAndViewsButton.autoPinEdge(.trailing, to: .trailing, of: mediaViewContainer)

        sendingIndicatorStackView.axis = .horizontal
        sendingIndicatorStackView.spacing = 13
        sendingIndicatorStackView.alignment = .center
        view.addSubview(sendingIndicatorStackView)
        sendingIndicatorStackView.autoPinEdges(toEdgesOf: repliesAndViewsButton)

        view.addSubview(playbackProgressView)
        playbackProgressView.autoPinEdge(.leading, to: .leading, of: mediaViewContainer, withOffset: OWSTableViewController2.defaultHOuterMargin)
        playbackProgressView.autoPinEdge(.trailing, to: .trailing, of: mediaViewContainer, withOffset: -OWSTableViewController2.defaultHOuterMargin)
        playbackProgressView.autoSetDimension(.height, toSize: 2)
        playbackProgressView.isUserInteractionEnabled = false

        if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
            // iPhone with notch or iPad (views/replies rendered below media, media is in a card)
            mediaViewContainer.layer.cornerRadius = 18
            mediaViewContainer.clipsToBounds = true
            onboardingOverlay.layer.cornerRadius = 18
            onboardingOverlay.clipsToBounds = true
            repliesAndViewsButton.autoPinEdge(.top, to: .bottom, of: mediaViewContainer)
            playbackProgressView.autoPinEdge(.bottom, to: .top, of: repliesAndViewsButton, withOffset: -OWSTableViewController2.defaultHOuterMargin)
        } else {
            // iPhone with home button (views/replies rendered on top of media, media is fullscreen)
            repliesAndViewsButton.autoPinEdge(.bottom, to: .bottom, of: mediaViewContainer)
            playbackProgressView.autoPinEdge(.bottom, to: .top, of: repliesAndViewsButton)
            mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .bottom)
        }

        applyConstraints()

        let spinner = UIActivityIndicatorView(style: .white)
        view.addSubview(spinner)
        spinner.autoCenterInSuperview()
        spinner.startAnimating()

        closeButton.block = { [weak self] in
            self?.dismiss(animated: true)
        }
        closeButton.setShadow()
        closeButton.imageEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 16)
        view.addSubview(closeButton)
        closeButton.autoSetDimensions(to: CGSize(square: 56))
        closeButton.autoPinEdge(toSuperviewSafeArea: .top)
        closeButton.autoPinEdge(toSuperviewSafeArea: .leading)

        loadStoryItems { [weak self] storyItems in
            // If there are no stories for this context, dismiss.
            guard !storyItems.isEmpty else {
                self?.dismiss(animated: true)
                return
            }

            UIView.animate(withDuration: 0.2) {
                spinner.alpha = 0
            } completion: { _ in
                spinner.stopAnimating()
                spinner.removeFromSuperview()
            }

            self?.items = storyItems
            self?.resetForPresentation()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Precompute if it should display before we mark anything viewed.
        onboardingOverlay.checkIfShouldDisplay()
    }

    /// This controller's view gets generated early to use for a zoom animation, which triggers
    /// viewWill- and viewDidAppear before presentation has really finished.
    /// The parent page controller calls this method when presentation actually finishes.
    func pageControllerDidAppear() {
        onboardingOverlay.showIfNeeded()
    }

    private static let maxItemsToRender = 100
    private func loadStoryItems(completion: @escaping ([StoryItem]) -> Void) {
        var storyItems = [StoryItem]()
        databaseStorage.asyncRead { [weak self] transaction in
            guard let self = self else { return }
            StoryFinder.enumerateStoriesForContext(self.context, transaction: transaction) { message, stop in
                if self.delegate?.storyContextViewControllerShouldOnlyRenderMyStories(self) == true && !message.authorAddress.isLocalAddress { return }
                guard let storyItem = self.buildStoryItem(for: message, transaction: transaction) else { return }
                storyItems.append(storyItem)
                if storyItems.count >= Self.maxItemsToRender { stop.pointee = true }
            }

            DispatchQueue.main.async {
                completion(storyItems)
            }
        }
    }

    private func buildStoryItem(for message: StoryMessage, transaction: SDSAnyReadTransaction) -> StoryItem? {
        let replyCount = InteractionFinder.countReplies(for: message, transaction: transaction)

        switch message.attachment {
        case .file(let attachmentId):
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for StoryMessage with timestamp \(message.timestamp)")
                return nil
            }
            if let attachment = attachment as? TSAttachmentPointer {
                return .init(message: message, numberOfReplies: replyCount, attachment: .pointer(attachment))
            } else if let attachment = attachment as? TSAttachmentStream {
                return .init(message: message, numberOfReplies: replyCount, attachment: .stream(attachment))
            } else {
                owsFailDebug("Unexpected attachment type \(type(of: attachment))")
                return nil
            }
        case .text(let attachment):
            return .init(message: message, numberOfReplies: replyCount, attachment: .text(attachment))
        }
    }

    private func currentItemWasUpdated(messageDidChange: Bool) {
        if let currentItem = currentItem {
            if currentItemMediaView == nil {
                let itemView = StoryItemMediaView(item: currentItem, delegate: self)
                self.currentItemMediaView = itemView
                mediaViewContainer.addSubview(itemView)
                itemView.autoPinEdgesToSuperviewEdges()
            }
            currentItemMediaView?.updateItem(currentItem)

            if currentItem.message.sendingState != .sent {
                updateSendingIndicator(currentItem)
            } else {
                updateRepliesAndViewsButton(currentItem)
            }
        } else {
            repliesAndViewsButton.isHidden = true
            sendingIndicatorStackView.isHidden = true
        }

        if messageDidChange {
            ensureSubsequentItemsDownloaded()
            updateProgressState()
        }
    }

    private func updateSendingIndicator(_ currentItem: StoryItem) {
        repliesAndViewsButton.isHidden = true
        sendingIndicatorStackView.gestureRecognizers?.removeAll()
        sendingIndicatorStackView.removeAllSubviews()

        switch currentItem.message.sendingState {
        case .pending, .sending:
            sendingIndicatorStackView.isHidden = false

            let sendingSpinner = AnimationView(name: "indeterminate_spinner_20")
            sendingSpinner.contentMode = .scaleAspectFit
            sendingSpinner.loopMode = .loop
            sendingSpinner.backgroundBehavior = .pauseAndRestore
            sendingSpinner.autoSetDimension(.width, toSize: 20)
            sendingSpinner.play()

            let sendingLabel = UILabel()
            sendingLabel.font = .ows_dynamicTypeBody
            sendingLabel.textColor = Theme.darkThemePrimaryColor
            sendingLabel.textAlignment = .center
            sendingLabel.text = NSLocalizedString("STORY_SENDING", comment: "Text indicating that the story is currently sending")
            sendingLabel.setContentHuggingHigh()

            let leadingSpacer = UIView.hStretchingSpacer()
            let trailingSpacer = UIView.hStretchingSpacer()

            sendingIndicatorStackView.addArrangedSubviews([
                leadingSpacer,
                sendingSpinner,
                sendingLabel,
                trailingSpacer
            ])

            leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)
        case .failed:
            sendingIndicatorStackView.isHidden = false

            sendingIndicatorStackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(askToResendFailedMessage)))

            let failedIcon = UIImageView()
            failedIcon.contentMode = .scaleAspectFit
            failedIcon.setTemplateImageName("error-20", tintColor: .ows_accentRed)
            failedIcon.autoSetDimension(.width, toSize: 20)
            sendingIndicatorStackView.addArrangedSubview(failedIcon)

            let failedLabel = UILabel()
            failedLabel.font = .ows_dynamicTypeBody
            failedLabel.textColor = Theme.darkThemePrimaryColor
            failedLabel.textAlignment = .center
            failedLabel.text = currentItem.message.hasSentToAnyRecipients
                ? NSLocalizedString("STORY_SEND_PARTIALLY_FAILED_TAP_FOR_DETAILS", comment: "Text indicating that the story send has partially failed")
                : NSLocalizedString("STORY_SEND_FAILED_TAP_FOR_DETAILS", comment: "Text indicating that the story send has failed")
            failedLabel.setContentHuggingHigh()
            sendingIndicatorStackView.addArrangedSubview(failedLabel)

            let leadingSpacer = UIView.hStretchingSpacer()
            let trailingSpacer = UIView.hStretchingSpacer()

            sendingIndicatorStackView.addArrangedSubviews([
                leadingSpacer,
                failedIcon,
                failedLabel,
                trailingSpacer
            ])

            leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)
        case .sent:
            sendingIndicatorStackView.isHidden = true
        case .sent_OBSOLETE, .delivered_OBSOLETE:
            owsFailDebug("Unexpected legacy sending state")
        }
    }

    @objc
    private func askToResendFailedMessage() {
        guard
            let message = currentItem?.message,
            let thread = databaseStorage.read(block: { context.thread(transaction: $0) })
        else { return }
        pause()
        StoryUtil.askToResend(message, in: thread, from: self) { [weak self] in
            self?.play()
        }
    }

    private func updateRepliesAndViewsButton(_ currentItem: StoryItem) {
        sendingIndicatorStackView.isHidden = true

        if currentItem.message.localUserAllowedToReply {
            repliesAndViewsButton.isHidden = false

            let repliesAndViewsButtonText: String

            var leadingIcon: UIImage?
            var trailingIcon: UIImage?

            switch currentItem.message.direction {
            case .incoming:
                if case .groupId = context {
                    if currentItem.numberOfReplies == 0 {
                        leadingIcon = #imageLiteral(resourceName: "reply-outline-20")
                        repliesAndViewsButtonText = NSLocalizedString(
                            "STORY_REPLY_TO_GROUP_BUTTON",
                            comment: "Button for replying to a group story with no existing replies.")
                    } else {
                        trailingIcon = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "chevron-left-20") : #imageLiteral(resourceName: "chevron-right-20")
                        let format = NSLocalizedString(
                            "STORY_REPLIES_COUNT_%d",
                            tableName: "PluralAware",
                            comment: "Button for replying to a story with N existing replies.")
                        repliesAndViewsButtonText = String.localizedStringWithFormat(format, currentItem.numberOfReplies)
                    }
                } else {
                    leadingIcon = #imageLiteral(resourceName: "reply-outline-20")
                    repliesAndViewsButtonText = NSLocalizedString(
                        "STORY_REPLY_BUTTON",
                        comment: "Button for replying to a story with no existing replies.")
                }
            case .outgoing:
                if receiptManager.areReadReceiptsEnabled() {
                    trailingIcon = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "chevron-left-20") : #imageLiteral(resourceName: "chevron-right-20")
                    if case .groupId = context {
                        let format = NSLocalizedString(
                            "STORY_VIEWS_AND_REPLIES_COUNT_%d_%d",
                            tableName: "PluralAware",
                            comment: "Button for viewing the replies and views for a story sent to a group")
                        repliesAndViewsButtonText = String.localizedStringWithFormat(format, currentItem.message.remoteViewCount, currentItem.numberOfReplies)
                    } else {
                        let format = NSLocalizedString(
                            "STORY_VIEWS_COUNT_%d",
                            tableName: "PluralAware",
                            comment: "Button for viewing the views for a story sent to a private list")
                        repliesAndViewsButtonText = String.localizedStringWithFormat(format, currentItem.message.remoteViewCount)
                    }
                } else if case .groupId = context, currentItem.numberOfReplies > 0 {
                    trailingIcon = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "chevron-left-20") : #imageLiteral(resourceName: "chevron-right-20")
                    let format = NSLocalizedString(
                        "STORY_REPLIES_COUNT_%d",
                        tableName: "PluralAware",
                        comment: "Button for replying to a story with N existing replies.")
                    repliesAndViewsButtonText = String.localizedStringWithFormat(format, currentItem.numberOfReplies)
                } else {
                    repliesAndViewsButtonText = NSLocalizedString(
                        "STORY_VIEWS_OFF",
                        comment: "Text indicating that the user has views turned off"
                    )
                }
            }

            repliesAndViewsButton.semanticContentAttribute = .unspecified

            if let leadingIcon = leadingIcon {
                repliesAndViewsButton.setImage(leadingIcon.asTintedImage(color: Theme.darkThemePrimaryColor), for: .normal)
                repliesAndViewsButton.imageEdgeInsets = UIEdgeInsets(top: 2, leading: 0, bottom: 0, trailing: 16)
            } else if let trailingIcon = trailingIcon {
                repliesAndViewsButton.setImage(trailingIcon.asTintedImage(color: Theme.darkThemePrimaryColor), for: .normal)
                repliesAndViewsButton.semanticContentAttribute = CurrentAppContext().isRTL ? .forceLeftToRight : .forceRightToLeft
                repliesAndViewsButton.imageEdgeInsets = UIEdgeInsets(top: 3, leading: 0, bottom: 0, trailing: 0)
            } else {
                repliesAndViewsButton.setImage(nil, for: .normal)
                repliesAndViewsButton.contentHorizontalAlignment = .center
            }

            let semiboldStyle = StringStyle(.font(.systemFont(ofSize: 17, weight: .semibold)))
            repliesAndViewsButton.setAttributedTitle(
                repliesAndViewsButtonText.styled(
                    with: .font(.systemFont(ofSize: 17)),
                    .color(Theme.darkThemePrimaryColor),
                    .xmlRules([.style("bold", semiboldStyle)])),
                for: .normal)
        } else {
            repliesAndViewsButton.isHidden = true
        }
    }

    private var pauseTime: CFTimeInterval?
    private var lastTransitionTime: CFTimeInterval?
    private func updateProgressState() {
        lastTransitionTime = CACurrentMediaTime()
    }

    @objc
    func displayLinkStep(_ displayLink: CADisplayLink) {
        AssertIsOnMainThread()
        playbackProgressView.numberOfItems = items.count
        if let currentItemView = currentItemMediaView, let idx = items.firstIndex(of: currentItemView.item) {
            // When we present a story, mark it as viewed if it's not already, as long as it's downloaded.
            if !currentItemView.item.isPendingDownload, currentItemView.item.message.localUserViewedTimestamp == nil {
                databaseStorage.write { transaction in
                    currentItemView.item.message.markAsViewed(at: Date.ows_millisecondTimestamp(), circumstance: .onThisDevice, transaction: transaction)
                }
            }

            currentItemView.updateTimestampText()

            if currentItemView.item.isPendingDownload {
                // Don't progress stories that are pending download.
                lastTransitionTime = CACurrentMediaTime()
                playbackProgressView.itemState = .init(index: idx, value: 0)
            } else if let lastTransitionTime = lastTransitionTime {
                let currentTime: CFTimeInterval
                if let elapsedTime = currentItemView.elapsedTime {
                    currentTime = lastTransitionTime + elapsedTime
                } else {
                    currentTime = displayLink.targetTimestamp
                }

                let value = currentTime.inverseLerp(
                    lastTransitionTime,
                    (lastTransitionTime + currentItemView.duration),
                    shouldClamp: true
                )
                playbackProgressView.itemState = .init(index: idx, value: value)

                if value >= 1 {
                    transitionToNextItem()
                }
            } else {
                playbackProgressView.itemState = .init(index: idx, value: 0)
            }
        } else {
            playbackProgressView.itemState = .init(index: 0, value: 0)
        }
    }

    private static let subsequentItemsToLoad = 3
    private func ensureSubsequentItemsDownloaded() {
        guard let currentItem = currentItem, let currentItemIdx = items.firstIndex(of: currentItem) else { return }

        let endingIdx = min((items.count - 1), currentItemIdx + Self.subsequentItemsToLoad)
        var subsequentItems = items[currentItemIdx...endingIdx]
        var context = context

        DispatchQueue.sharedBackground.async {
            // If the current context has less than 3 unloaded items, try the next context until we reach the end or the limit
            while subsequentItems.count < Self.subsequentItemsToLoad {
                guard let nextContext = self.delegate?.storyContextViewController(self, contextAfter: context) else { break }

                Self.databaseStorage.read { transaction in
                    StoryFinder.enumerateUnviewedIncomingStoriesForContext(self.context, transaction: transaction) { message, stop in
                        if self.delegate?.storyContextViewControllerShouldOnlyRenderMyStories(self) == true && !message.authorAddress.isLocalAddress { return }
                        guard let storyItem = self.buildStoryItem(for: message, transaction: transaction) else { return }
                        subsequentItems.append(storyItem)
                        if subsequentItems.count >= Self.subsequentItemsToLoad { stop.pointee = true }
                    }
                }

                context = nextContext
            }

            subsequentItems.forEach { $0.startAttachmentDownloadIfNecessary() }
        }
    }

    private lazy var iPhoneConstraints = [
        mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .top),
        mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .leading),
        mediaViewContainer.autoPinEdge(toSuperviewSafeArea: .trailing)
    ]

    private lazy var iPadConstraints: [NSLayoutConstraint] = {
        var constraints = mediaViewContainer.autoCenterInSuperview()

        // Prefer to be as big as possible.
        let heightConstraint = mediaViewContainer.autoMatch(.height, to: .height, of: view)
        heightConstraint.priority = .defaultHigh
        constraints.append(heightConstraint)

        let widthConstraint = mediaViewContainer.autoMatch(.width, to: .width, of: view)
        widthConstraint.priority = .defaultHigh
        constraints.append(widthConstraint)

        let maxWidthConstraint = mediaViewContainer.autoMatch(
            .width,
            to: .width,
            of: view,
            withOffset: 0,
            relation: .lessThanOrEqual
        )
        constraints.append(maxWidthConstraint)

        return constraints
    }()

    private lazy var iPadLandscapeConstraints = [
        mediaViewContainer.autoMatch(
            .height,
            to: .height,
            of: view,
            withMultiplier: 0.75,
            relation: .lessThanOrEqual
        )
    ]
    private lazy var iPadPortraitConstraints = [
        mediaViewContainer.autoMatch(
            .height,
            to: .height,
            of: view,
            withMultiplier: 0.65,
            relation: .lessThanOrEqual
        )
    ]

    private func applyConstraints() {
        NSLayoutConstraint.deactivate(iPhoneConstraints)
        NSLayoutConstraint.deactivate(iPadConstraints)
        NSLayoutConstraint.deactivate(iPadPortraitConstraints)
        NSLayoutConstraint.deactivate(iPadLandscapeConstraints)

        if UIDevice.current.isIPad {
            NSLayoutConstraint.activate(iPadConstraints)
            if UIDevice.current.orientation.isLandscape {
                NSLayoutConstraint.activate(iPadLandscapeConstraints)
            } else {
                NSLayoutConstraint.activate(iPadPortraitConstraints)
            }
        } else {
            NSLayoutConstraint.activate(iPhoneConstraints)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.applyConstraints()
        } completion: { _ in
            self.applyConstraints()
        }
    }

    private var isPinchZooming = false

    @objc
    private func handlePinchZoom() {
        func beginIfNecessary(with sender: UIGestureRecognizer) {
            guard !isPinchZooming else { return }
            isPinchZooming = true
            pause(hideChrome: true)

            let touchPoint = sender.location(in: mediaViewContainer)
            mediaViewContainer.setAnchorPointAndMaintainPosition(CGPoint(
                x: touchPoint.x / mediaViewContainer.width,
                y: touchPoint.y / mediaViewContainer.height
            ))
        }

        func endIfNecessary() {
            guard isPinchZooming else { return }

            let endableStates: [UIGestureRecognizer.State] = [
                .possible,
                .ended,
                .cancelled,
                .failed
            ]

            guard endableStates.contains(zoomPanGestureRecognizer.state)
                    && endableStates.contains(zoomPinchGestureRecognizer.state) else { return }

            isPinchZooming = false

            UIView.animate(withDuration: 0.35) {
                self.mediaViewContainer.transform = .identity
                self.mediaViewContainer.setAnchorPointAndMaintainPosition(CGPoint(x: 0.5, y: 0.5))
            } completion: { _ in
                self.play()
            }
        }

        func update() {
            mediaViewContainer.transform = .scale(zoomPinchGestureRecognizer.scale)
                .translate(zoomPanGestureRecognizer.translation(in: mediaViewContainer))
        }

        for gesture in [zoomPanGestureRecognizer, zoomPinchGestureRecognizer] {
            switch gesture.state {
            case .possible:
                break
            case .began:
                beginIfNecessary(with: gesture)
            case .changed:
                update()
            case .ended, .cancelled, .failed:
                endIfNecessary()
            @unknown default:
                break
            }
        }
    }
}

extension StoryContextViewController: UIGestureRecognizerDelegate {
    @objc
    func didTapLeft() {
        guard currentItemMediaView?.willHandleTapGesture(leftTapGestureRecognizer) != true else { return }
        CurrentAppContext().isRTL
            ? transitionToNextItem(nextContextLoadPositionIfRead: .oldest)
            : transitionToPreviousItem(previousContextLoadPositionIfRead: .newest)
    }

    @objc
    func didTapRight() {
        guard currentItemMediaView?.willHandleTapGesture(rightTapGestureRecognizer) != true else { return }
        CurrentAppContext().isRTL
            ? transitionToPreviousItem(previousContextLoadPositionIfRead: .newest)
            : transitionToNextItem(nextContextLoadPositionIfRead: .oldest)
    }

    func willHandleInteractivePanGesture(_ gestureRecognizer: UIPanGestureRecognizer) -> Bool {
        return currentItemMediaView?.willHandlePanGesture(gestureRecognizer) == true
    }

    @objc
    func handleLongPress() {
        switch pauseGestureRecognizer.state {
        case .began:
            pause(hideChrome: true)
        case .ended:
            play()
        default:
            break
        }
    }

    func pause(hideChrome: Bool = false) {
        guard pauseTime == nil else { return }
        pauseTime = CACurrentMediaTime()
        delegate?.storyContextViewControllerDidPause(self)
        currentItemMediaView?.pause(hideChrome: hideChrome) {
            if hideChrome {
                self.playbackProgressView.alpha = 0
                self.closeButton.alpha = 0
                self.repliesAndViewsButton.alpha = 0
            }
        }
    }

    func play() {
        if let lastTransitionTime = lastTransitionTime, let pauseTime = pauseTime {
            let pauseDuration = CACurrentMediaTime() - pauseTime
            self.lastTransitionTime = lastTransitionTime + pauseDuration
            self.pauseTime = nil
        }
        currentItemMediaView?.play {
            self.playbackProgressView.alpha = 1
            self.closeButton.alpha = 1
            self.repliesAndViewsButton.alpha = 1
        }
        delegate?.storyContextViewControllerDidResume(self)
    }

    func presentRepliesAndViewsSheet() {
        guard let currentItem = currentItem, currentItem.message.localUserAllowedToReply else {
            owsFailDebug("Unexpectedly attempting to present reply sheet")
            return
        }

        switch self.context {
        case .groupId:
            switch currentItem.message.direction {
            case .outgoing:
                let groupRepliesAndViewsVC = StoryGroupRepliesAndViewsSheet(storyMessage: currentItem.message)
                groupRepliesAndViewsVC.dismissHandler = { [weak self] in self?.play() }
                groupRepliesAndViewsVC.focusedTab = currentItem.numberOfReplies > 0 ? .replies : .views
                self.pause()
                self.present(groupRepliesAndViewsVC, animated: true)
            case .incoming:
                let groupReplyVC = StoryGroupReplySheet(storyMessage: currentItem.message)
                groupReplyVC.dismissHandler = { [weak self] in self?.play() }
                self.pause()
                self.present(groupReplyVC, animated: true)
            }
        case .authorUuid:
            owsAssertDebug(
                !currentItem.message.authorAddress.isSystemStoryAddress,
                "Should be impossible to reply to system stories"
            )
            let directReplyVC = StoryDirectReplySheet(storyMessage: currentItem.message)
            directReplyVC.dismissHandler = { [weak self] in self?.play() }
            self.pause()
            self.present(directReplyVC, animated: true)
        case .privateStory:
            let privateViewsVC = StoryPrivateViewsSheet(storyMessage: currentItem.message)
            privateViewsVC.dismissHandler = { [weak self] in self?.play() }
            self.pause()
            self.present(privateViewsVC, animated: true)
        case .none:
            owsFailDebug("Unexpected context")
        }
    }

    func presentInfoSheet() {
        guard let currentItem = currentItem else { return }

        let vc = StoryInfoSheet(storyMessage: currentItem.message)
        vc.dismissHandler = { [weak self] in self?.play() }
        pause()
        present(vc, animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let isMultiTouchGesture = gestureRecognizer == zoomPinchGestureRecognizer || gestureRecognizer == zoomPanGestureRecognizer

        if gestureRecognizer.numberOfTouches > 1 {
            // Only allow pinch-zoom on downloaded image attachments
            guard case .stream = currentItem?.attachment else { return false }

            return isMultiTouchGesture
        } else if isMultiTouchGesture {
            return false
        }

        let nextFrameWidth = mediaViewContainer.width * 0.8
        let previousFrameWidth = mediaViewContainer.width * 0.2

        let leftFrameWidth: CGFloat
        let rightFrameWidth: CGFloat
        if CurrentAppContext().isRTL {
            leftFrameWidth = nextFrameWidth
            rightFrameWidth = previousFrameWidth
        } else {
            leftFrameWidth = previousFrameWidth
            rightFrameWidth = nextFrameWidth
        }

        let touchLocation = gestureRecognizer.location(in: view)
        if gestureRecognizer == leftTapGestureRecognizer {
            var leftFrame = mediaViewContainer.frame
            leftFrame.width = leftFrameWidth
            return leftFrame.contains(touchLocation)
        } else if gestureRecognizer == rightTapGestureRecognizer {
            var rightFrame = mediaViewContainer.frame
            rightFrame.width = rightFrameWidth
            rightFrame.x += leftFrameWidth
            return rightFrame.contains(touchLocation)
        } else {
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        [zoomPanGestureRecognizer, zoomPinchGestureRecognizer].contains(gestureRecognizer)
            && [zoomPanGestureRecognizer, zoomPinchGestureRecognizer].contains(otherGestureRecognizer)
    }
}

extension StoryContextViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard var currentItem = currentItem else { return }
        guard !databaseChanges.storyMessageRowIds.isEmpty else { return }

        databaseStorage.asyncRead { transaction in
            var newItems = self.items
            var shouldGoToNextContext = false
            for (idx, item) in self.items.enumerated().reversed() {
                guard let id = item.message.id, databaseChanges.storyMessageRowIds.contains(id) else { continue }
                if let message = StoryMessage.anyFetch(uniqueId: item.message.uniqueId, transaction: transaction) {
                    if let newItem = self.buildStoryItem(for: message, transaction: transaction) {
                        newItems[idx] = newItem

                        if item.message.uniqueId == currentItem.message.uniqueId {
                            currentItem = newItem
                        }

                        continue
                    }
                }

                newItems.remove(at: idx)
                if item.message.uniqueId == currentItem.message.uniqueId {
                    shouldGoToNextContext = true
                    break
                }
            }
            DispatchQueue.main.async {
                if shouldGoToNextContext, let delegate = self.delegate {
                    delegate.storyContextViewControllerWantsTransitionToNextContext(self, loadPositionIfRead: .default)
                } else if shouldGoToNextContext {
                    self.presentingViewController?.dismiss(animated: true)
                } else {
                    self.items = newItems
                    self.currentItem = currentItem
                }
            }
        }
    }

    func databaseChangesDidUpdateExternally() {}

    func databaseChangesDidReset() {}
}

extension StoryContextViewController: StoryItemMediaViewDelegate {

    func contextMenuConfiguration(for contextMenuButton: DelegatingContextMenuButton) -> ContextMenuConfiguration? {
        guard let item = currentItem else {
            return nil
        }
        let attachment: StoryThumbnailView.Attachment
        switch item.attachment {
        case .pointer(let pointer):
            attachment = .file(pointer)
        case .stream(let stream):
            attachment = .file(stream)
        case .text(let textAttachment):
            attachment = .text(textAttachment)
        }
        return .init(
            identifier: nil,
            actionProvider: { [weak self, weak contextMenuButton] _ in
                guard
                    let self  = self,
                    let contextMenuButton = contextMenuButton
                else {
                    return .init([])
                }
                return Self.databaseStorage.read {
                    return ContextMenu(self.contextMenuGenerator.contextMenuActions(
                        for: item.message,
                        in: self.context.thread(transaction: $0),
                        attachment: attachment,
                        sourceView: contextMenuButton,
                        transaction: $0
                    ))
                }
            }
        )
    }

    func storyItemMediaViewWantsToPlay(_ storyItemMediaView: StoryItemMediaView) {
        play()
    }

    func storyItemMediaViewWantsToPause(_ storyItemMediaView: StoryItemMediaView) {
        pause()
    }

    func storyItemMediaViewShouldBeMuted(_ storyItemMediaView: StoryItemMediaView) -> Bool {
        return delegate?.storyContextViewControllerShouldBeMuted(self) ?? false
    }

    func contextMenuWillDisplay(from contextMenuButton: DelegatingContextMenuButton) {
        pause()
    }

    func contextMenuDidDismiss(from contextMenuButton: ContextMenuButton) {
        guard !contextMenuGenerator.isDisplayingFollowup else {
            return
        }
        play()
    }
}

extension StoryContextViewController: StoryContextMenuDelegate {

    func storyContextMenuWillNavigateToConversation(_ completion: @escaping () -> Void) {
        // Dismiss the viewer before navigating.
        self.dismiss(animated: true, completion: completion)
    }

    func storyContextMenuWillDelete(_ completion: @escaping () -> Void) {
        // Go to the next item after deleting.
        self.transitionToNextItem()
        completion()
    }

    func storyContextMenuDidUpdateHiddenState(_ message: StoryMessage, isHidden: Bool) -> Bool {
        // Go to the next context after hiding or unhiding; the current context is no longer
        // a part of this view session as its hide state is now opposite.
        self.delegate?.storyContextViewControllerWantsTransitionToNextContext(self, loadPositionIfRead: .default)
        // Return true so we show a toast confirming the hide action.
        return true
    }

    func storyContextMenuDidFinishDisplayingFollowups() {
        play()
    }
}

extension StoryContextViewController: StoryContextOnboardingOverlayViewDelegate {

    func storyContextOnboardingOverlayWillDisplay(_: StoryContextOnboardingOverlayView) {
        pause(hideChrome: true)
    }

    func storyContextOnboardingOverlayDidDismiss(_: StoryContextOnboardingOverlayView) {
        play()
    }
}

private extension UIView {
    func setAnchorPointAndMaintainPosition(_ newAnchorPoint: CGPoint) {
        layer.position = CGPoint(
            x: layer.position.x + (newAnchorPoint.x * width) - (layer.anchorPoint.x * width),
            y: layer.position.y + (newAnchorPoint.y * height) - (layer.anchorPoint.y * height)
        )
        layer.anchorPoint = newAnchorPoint
    }
}
