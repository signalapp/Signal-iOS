//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SwiftUI
import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI

// MARK: - GroupCallViewController

// TODO: Eventually add 1:1 call support to this view
// and replace CallViewController
final class GroupCallViewController: UIViewController {

    // MARK: Properties

    private let call: SignalCall
    private let groupCall: GroupCall
    private let ringRtcCall: SignalRingRTC.GroupCall
    private lazy var callControlsConfirmationToastManager = CallControlsConfirmationToastManager(
        presentingContainerView: callControlsConfirmationToastContainerView
    )
    private lazy var bottomSheet: CallDrawerSheet = {
        let dataSource: any CallDrawerSheetDataSource = switch groupCall.concreteType {
        case .groupThread(let groupThreadCall):
            GroupCallSheetDataSource(groupCall: groupThreadCall)
        case .callLink(let callLinkCall):
            GroupCallSheetDataSource(groupCall: callLinkCall)
        }
        return CallDrawerSheet(
            call: call,
            callSheetDataSource: dataSource,
            callService: callService,
            confirmationToastManager: callControlsConfirmationToastManager,
            callControlsDelegate: self,
            sheetPanDelegate: self,
            callDrawerDelegate: self
        )
    }()
    private lazy var fullscreenLocalMemberAddOnsView = SupplementalCallControlsForFullscreenLocalMember(
        call: call,
        groupCall: groupCall,
        callService: callService
    )
    private lazy var callControlsConfirmationToastContainerView = UIView()
    private var callService: CallService { AppEnvironment.shared.callService }
    private var incomingCallControls: IncomingCallControls?
    private lazy var callHeader = CallHeader(groupCall: groupCall, delegate: self)
    private lazy var notificationView = GroupCallNotificationView(groupCall: groupCall)

    /// A UIStackView which allows taps on its subviews, but passes taps outside of those or in explicitly ignored views through to the parent.
    private class PassthroughStackView: UIStackView {
        var ignoredViews: WeakArray<UIView> = []

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // super.hitTest will return the deepest view hit, so if it's
            // just `self`, the highest view, that means a subview wasn't hit.
            let hitView = super.hitTest(point, with: event)
            if let hitView, hitView == self || ignoredViews.contains(hitView) {
                return nil
            }
            return hitView
        }
    }

    /// A container view which allows taps on the child view's subviews, but
    /// passes through taps on the child view itself.
    ///
    /// - Add the child view using `add(passthroughView:)`
    /// - Pins the child view edges to this view's edges
    /// - Used with a `UIHostingController`, it passes touches on the background
    /// through while still allowing interaction with the SwiftUI content
    private class PassthroughContainerView: UIView {
        private weak var passthroughView: UIView?

        func add(passthroughView: UIView) {
            self.passthroughView = passthroughView
            self.addSubview(passthroughView)
            passthroughView.autoPinEdgesToSuperviewEdges()
        }

        private var previousHit: (timestamp: TimeInterval, point: CGPoint, view: UIView?)?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            var view = super.hitTest(point, with: event)

            let isSameEventAsPreviousHitTest = previousHit?.timestamp == event?.timestamp && previousHit?.point == point
            let previousHitWasNotPassedThrough = previousHit?.view != nil

            if
                view == passthroughView,
                !(isSameEventAsPreviousHitTest && previousHitWasNotPassedThrough)
            {
                view = nil
            }
            self.previousHit = event.map { ($0.timestamp, point, view) }
            return view
        }
    }

    private let bottomVStack = PassthroughStackView()
    private let videoOverflowContainer = UIView()
    private let raisedHandsToastContainer = UIView()
    private lazy var raisedHandsToast = RaisedHandsToast(call: self.groupCall)

    private var approvalRequestActionsSubscription: AnyCancellable?
    private lazy var callLinkApprovalViewModel: CallLinkApprovalViewModel = {
        let viewModel = CallLinkApprovalViewModel()

        approvalRequestActionsSubscription = viewModel.performRequestAction
            .sink { [weak self] (action, request) in
                guard let self else { return }
                switch action {
                case .approve:
                    self.ringRtcCall.approveUser(request.aci.rawUUID)
                case .deny:
                    self.ringRtcCall.denyUser(request.aci.rawUUID)
                case .viewDetails:
                    self.presentApprovalRequestDetails(approvalRequest: request)
                }
            }

        return viewModel
    }()

    /// The `UIHostingController` with the approval request views in a stack.
    private lazy var approvalStack = UIHostingController(rootView: VStack {
        Spacer()
        ApprovalRequestStack(
            viewModel: self.callLinkApprovalViewModel,
            didTapMore: { [weak self] requests in
                self?.presentBulkApprovalSheet()
            },
            didChangeHeight: { [weak self] height in
                self?.approvalStackHeightConstraint?.constant = height
                self?.updateCallUI(shouldAnimateViewFrames: true)
            }
        )
    })
    /// A view used in `bottomVStack` that takes the height of the approval stack. Does not actually hold any content.
    private let approvalStackHeightView = UIView()

    private lazy var callLinkLobbyToastLabel = UILabel()
    private lazy var callLinkLobbyToast: UIView = {
        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        backgroundView.layer.cornerRadius = 10
        backgroundView.clipsToBounds = true
        backgroundView.contentView.addSubview(callLinkLobbyToastLabel)
        backgroundView.contentView.layoutMargins = .init(margin: 12)
        callLinkLobbyToastLabel.autoPinEdgesToSuperviewMargins()
        callLinkLobbyToastLabel.font = .dynamicTypeFootnote
        callLinkLobbyToastLabel.textColor = .white
        callLinkLobbyToastLabel.textAlignment = .center
        callLinkLobbyToastLabel.numberOfLines = 0

        return backgroundView
    }()

    private lazy var videoGrid: GroupCallVideoGrid = {
        let result = GroupCallVideoGrid(call: call, groupCall: groupCall)
        result.memberViewErrorPresenter = self
        return result
    }()

    private lazy var videoOverflow: GroupCallVideoOverflow = {
        let result = GroupCallVideoOverflow(call: call, groupCall: groupCall, delegate: self)
        result.memberViewErrorPresenter = self
        return result
    }()

    private lazy var speakerView: CallMemberView = {
        let result = CallMemberView(type: .remoteInGroup(.speaker))
        result.errorPresenter = self
        return result
    }()

    private lazy var localMemberView: CallMemberView = {
        let result = CallMemberView(type: .local)
        result.errorPresenter = self
        result.animatableLocalMemberViewDelegate = self
        return result
    }()

    private var didUserEverSwipeToSpeakerView: Bool
    private var didUserEverSwipeToScreenShare: Bool
    private let swipeToastView = GroupCallSwipeToastView()

    private let speakerPage = UIView()

    private let scrollView = UIScrollView()

    private enum Page {
        case grid, speaker
    }

    private var page: Page = .grid {
        didSet {
            guard page != oldValue else { return }
            videoOverflow.reloadData()
            updateCallUI(shouldAnimateViewFrames: true)
            ImpactHapticFeedback.impactOccurred(style: .light)
        }
    }

    private let incomingReactionsView = IncomingReactionsView()

    private var isCallMinimized = false {
        didSet {
            speakerView.isCallMinimized = isCallMinimized
            scheduleBottomSheetTimeoutIfNecessary()
        }
    }

    private var isAutoScrollingToScreenShare = false
    private var isAnyRemoteDeviceScreenSharing = false {
        didSet {
            guard oldValue != isAnyRemoteDeviceScreenSharing else { return }

            // Scroll to speaker view when presenting begins.
            if isAnyRemoteDeviceScreenSharing {
                isAutoScrollingToScreenShare = true
                scrollView.setContentOffset(CGPoint(x: 0, y: speakerPage.frame.origin.y), animated: true)
            }
        }
    }

    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTouchRootView))
    private lazy var bottomVStackTopConstraint = self.bottomVStack.autoPinEdge(.bottom, to: .top, of: self.view)
    private lazy var videoOverflowTrailingConstraint = videoOverflow.autoPinEdge(toSuperviewEdge: .trailing)
    private var approvalStackHeightConstraint: NSLayoutConstraint?

    private lazy var bottomSheetStateManager: GroupCallBottomSheetStateManager = {
        return GroupCallBottomSheetStateManager(delegate: self)
    }()

    private var hasUnresolvedSafetyNumberMismatch = false
    private var hasDismissed = false

    private var membersAtJoin: Set<SignalServiceAddress>?

    private static let keyValueStore = KeyValueStore(collection: "GroupCallViewController")
    private static let didUserSwipeToSpeakerViewKey = "didUserSwipeToSpeakerView"
    private static let didUserSwipeToScreenShareKey = "didUserSwipeToScreenShare"

    /// When the local member view (which is displayed picture-in-picture) is
    /// tapped, it expands. If the frame is expanded, its enlarged frame is
    /// stored here. If the pip is not in the expanded state, this value is nil.
    private var expandedPipFrame: CGRect?

    /// Whether the local member view pip has an animation currently in progress.
    private var isPipAnimationInProgress = false

    /// Whether a relayout needs to occur after the pip animation completes.
    /// This is true when we suspended an attempted relayout triggered during
    /// the pip animation.
    private var shouldRelayoutAfterPipAnimationCompletes = false
    private var postAnimationUpdateMemberViewFramesSize: CGSize?

    private lazy var reactionsBurstView: ReactionsBurstView = {
        ReactionsBurstView(burstAligner: self.incomingReactionsView)
    }()
    private lazy var reactionsSink: ReactionsSink = {
        ReactionsSink(reactionReceivers: [
            self.incomingReactionsView,
            self.reactionsBurstView
        ])
    }()
    private lazy var callControlsOverflowView: CallControlsOverflowView = {
        return CallControlsOverflowView(
            call: self.call,
            reactionSender: self.ringRtcCall,
            reactionsSink: self.reactionsSink,
            raiseHandSender: self.ringRtcCall,
            emojiPickerSheetPresenter: self.bottomSheet,
            callControlsOverflowPresenter: self
        )
    }()

    private var callControlsOverflowBottomConstraint: NSLayoutConstraint?
    private var callControlsConfirmationToastContainerViewBottomConstraint: NSLayoutConstraint?

    static func load(call: SignalCall, groupCall: GroupCall, tx: SDSAnyReadTransaction) -> GroupCallViewController {
        let didUserEverSwipeToSpeakerView = keyValueStore.getBool(
            didUserSwipeToSpeakerViewKey,
            defaultValue: false,
            transaction: tx.asV2Read
        )
        let didUserEverSwipeToScreenShare = keyValueStore.getBool(
            didUserSwipeToScreenShareKey,
            defaultValue: false,
            transaction: tx.asV2Read
        )

        let phoneNumberSharingMode = SSKEnvironment.shared.udManagerRef.phoneNumberSharingMode(tx: tx.asV2Read).orDefault

        return GroupCallViewController(
            call: call,
            groupCall: groupCall,
            didUserEverSwipeToSpeakerView: didUserEverSwipeToSpeakerView,
            didUserEverSwipeToScreenShare: didUserEverSwipeToScreenShare,
            phoneNumberSharingMode: phoneNumberSharingMode
        )
    }

    init(
        call: SignalCall,
        groupCall: GroupCall,
        didUserEverSwipeToSpeakerView: Bool,
        didUserEverSwipeToScreenShare: Bool,
        phoneNumberSharingMode: PhoneNumberSharingMode
    ) {
        // TODO: Eventually unify UI for group and individual calls

        self.call = call
        self.groupCall = groupCall
        self.ringRtcCall = groupCall.ringRtcCall
        self.didUserEverSwipeToSpeakerView = didUserEverSwipeToSpeakerView
        self.didUserEverSwipeToScreenShare = didUserEverSwipeToScreenShare

        super.init(nibName: nil, bundle: nil)

        groupCall.addObserver(self)
        groupCall.addObserver(AppEnvironment.shared.callLinkProfileKeySharingManager)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didCompleteAnySpamChallenge),
            name: SpamChallengeResolver.didCompleteAnyChallenge,
            object: nil
        )

        self.callLinkLobbyToastLabel.text = switch phoneNumberSharingMode {
        case .everybody:
            OWSLocalizedString(
                "CALL_LINK_LOBBY_SHARING_INFO_PHONE_NUMBER_SHARING_ON",
                comment: "Text that appears on a toast in a call lobby before joining a call link informing the user what information will be shared with other call members when they have phone number sharing turned on."
            )
        case .nobody:
            OWSLocalizedString(
                "CALL_LINK_LOBBY_SHARING_INFO_PHONE_NUMBER_SHARING_OFF",
                comment: "Text that appears on a toast in a call lobby before joining a call link informing the user what information will be shared with other call members when they have phone number sharing turned off."
            )
        }
    }

    static func presentLobby(forGroupId groupId: GroupIdentifier, videoMuted: Bool = false) {
        self._presentLobby { viewController in
            let result = await self._prepareLobby(from: viewController, shouldAskForCameraPermission: !videoMuted) {
                let callService = AppEnvironment.shared.callService!
                return callService.buildAndConnectGroupCall(for: groupId, isVideoMuted: videoMuted)
            }
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                // Dismiss the group call tooltip
                SSKEnvironment.shared.preferencesRef.setWasGroupCallTooltipShown(tx: tx)
            }
            return result
        }
    }

    static func presentLobby(
        for callLink: CallLink,
        callLinkStateRetrievalStrategy: CallService.CallLinkStateRetrievalStrategy = .fetch
    ) {
        self._presentLobby { viewController in
            do {
                return try await self._prepareLobby(from: viewController, shouldAskForCameraPermission: true) {
                    let callService = AppEnvironment.shared.callService!
                    return try await callService.buildAndConnectCallLinkCall(
                        callLink: callLink,
                        callLinkStateRetrievalStrategy: callLinkStateRetrievalStrategy
                    )
                }
            } catch {
                Logger.warn("Call link lobby presentation failed with error \(error)")
                return {
                    OWSActionSheets.showActionSheet(
                        title: CallStrings.callLinkErrorSheetTitle,
                        message: OWSLocalizedString(
                            "CALL_LINK_JOIN_CALL_FAILURE_SHEET_DESCRIPTION",
                            comment: "Description of sheet presented when joining call from call link sheet fails."
                        )
                    )
                }
            }
        }
    }

    private static func _presentLobby(
        prepareLobby: @escaping @MainActor (UIViewController) async -> (() -> Void)?
    ) {
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFail("Can't start a call if there's no view controller")
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: frontmostViewController,
            canCancel: false,
            presentationDelay: 0.25,
            asyncBlock: { modal in
                let presentLobby = await prepareLobby(frontmostViewController)
                modal.dismissIfNotCanceled(completionIfNotCanceled: presentLobby ?? {})
            }
        )
    }

    private static func _prepareLobby(
        from viewController: UIViewController,
        shouldAskForCameraPermission: Bool,
        buildAndStartConnecting: () async throws -> (SignalCall, GroupCall)?
    ) async rethrows -> (() -> Void)? {
        guard await CallStarter.prepareToStartCall(from: viewController, shouldAskForCameraPermission: shouldAskForCameraPermission) else {
            return nil
        }

        guard let (call, groupCall) = try await buildAndStartConnecting() else {
            owsFailDebug("Can't show lobby if the call can't start")
            return nil
        }

        let vc = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return GroupCallViewController.load(call: call, groupCall: groupCall, tx: tx)
        }

        return {
            vc.modalTransitionStyle = .crossDissolve
            AppEnvironment.shared.windowManagerRef.startCall(viewController: vc)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    override func loadView() {
        view = UIView()
        view.clipsToBounds = true

        view.backgroundColor = .ows_black

        scrollView.delegate = self
        view.addSubview(scrollView)
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = false
        scrollView.autoPinEdgesToSuperviewEdges()

        view.addSubview(callHeader)
        callHeader.autoPinWidthToSuperview()
        callHeader.autoPinEdge(toSuperviewEdge: .top)

        view.addSubview(notificationView)
        notificationView.autoPinEdgesToSuperviewEdges()

        view.addSubview(self.bottomVStack)
        self.bottomVStack.autoPinWidthToSuperview()
        self.bottomVStack.axis = .vertical
        self.bottomVStack.spacing = Constants.bottomVStackSpacing
        self.bottomVStack.preservesSuperviewLayoutMargins = true
        self.bottomVStack.alignment = .center
        self.bottomVStack.ignoredViews.append(fullscreenLocalMemberAddOnsView)

        switch groupCall.concreteType {
        case .groupThread:
            break
        case .callLink:
            // Lobby text
            self.bottomVStack.addArrangedSubview(self.callLinkLobbyToast)
            self.callLinkLobbyToast.autoPinWidthToSuperviewMargins()

            // Approvals
            self.addChild(self.approvalStack)

            let passthroughView = PassthroughContainerView()
            passthroughView.add(passthroughView: self.approvalStack.view)
            self.view.addSubview(passthroughView)
            self.approvalStack.view.backgroundColor = .clear
            self.approvalStack.didMove(toParent: self)

            // If passthroughView changed height to match the height of its content,
            // the SwiftUI content would jump around as the UIView's height changes,
            // so instead, make it taller than it needs, and pin its bottom to a
            // placeholder view that adjusts height based on the content.
            self.bottomVStack.addArrangedSubview(self.approvalStackHeightView)
            self.approvalStackHeightConstraint = self.approvalStackHeightView
                .autoSetDimension(.height, toSize: 0)
            self.pinWidthWithBottomSheetMaxWidth(passthroughView)
            passthroughView.autoHCenterInSuperview()
            passthroughView.autoSetDimension(.height, toSize: 300)
            passthroughView.autoPinEdge(.bottom, to: .bottom, of: self.approvalStackHeightView)
        }

        videoOverflowContainer.addSubview(self.videoOverflow)
        self.bottomVStack.addArrangedSubview(videoOverflowContainer)
        self.bottomVStack.ignoredViews.append(videoOverflowContainer)
        self.videoOverflowContainer.autoPinWidthToSuperview()
        self.videoOverflow.autoPinHeightToSuperview()
        self.videoOverflow.autoPinEdge(toSuperviewEdge: .leading)

        self.bottomVStack.insertArrangedSubview(raisedHandsToastContainer, at: 0)
        self.bottomVStack.ignoredViews.append(raisedHandsToastContainer)

        raisedHandsToastContainer.layoutMargins = .init(margin: 0)
        raisedHandsToastContainer.preservesSuperviewLayoutMargins = true
        raisedHandsToastContainer.isHiddenInStackView = true

        raisedHandsToastContainer.addSubview(raisedHandsToast)
        self.pinWidthWithBottomSheetMaxWidth(raisedHandsToastContainer)

        raisedHandsToast.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)
        raisedHandsToast.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        raisedHandsToast.horizontalPinConstraint = raisedHandsToast.autoPinEdge(toSuperviewMargin: .leading)
        raisedHandsToast.delegate = self

        scrollView.addSubview(videoGrid)
        scrollView.addSubview(speakerPage)

        view.addSubview(incomingReactionsView)
        incomingReactionsView.autoPinEdge(.leading, to: .leading, of: view, withOffset: 22)
        incomingReactionsView.autoPinEdge(.bottom, to: .top, of: self.bottomVStack, withOffset: -16)
        incomingReactionsView.widthAnchor.constraint(equalToConstant: IncomingReactionsView.Constants.viewWidth).isActive = true
        incomingReactionsView.heightAnchor.constraint(equalToConstant: IncomingReactionsView.viewHeight).isActive = true

        scrollView.addSubview(swipeToastView)
        swipeToastView.autoPinEdge(.bottom, to: .bottom, of: videoGrid, withOffset: -22)
        swipeToastView.autoHCenterInSuperview()
        swipeToastView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        swipeToastView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

        view.addSubview(callControlsConfirmationToastContainerView)
        callControlsConfirmationToastContainerView.autoHCenterInSuperview()
        view.addSubview(callControlsOverflowView)
        callControlsOverflowView.isHidden = true
        if UIDevice.current.isIPad {
            callControlsOverflowView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        } else {
            callControlsOverflowView.autoPinEdge(
                .trailing,
                to: .trailing,
                of: view,
                withOffset: -12
            )
        }

        self.callControlsConfirmationToastContainerViewBottomConstraint = callControlsConfirmationToastContainerView.autoPinEdge(
            .bottom,
            to: .bottom,
            of: self.view,
            withOffset: callControlsConfirmationToastContainerViewBottomConstraintConstant
        )
        self.callControlsOverflowBottomConstraint = self.callControlsOverflowView.autoPinEdge(
            .bottom,
            to: .bottom,
            of: self.view,
            withOffset: callControlsOverflowBottomConstraintConstant
        )

        view.addSubview(reactionsBurstView)
        reactionsBurstView.autoPinEdgesToSuperviewEdges()

        view.addGestureRecognizer(tapGesture)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(otherUsersProfileChanged(notification:)),
            name: UserProfileNotifications.otherUsersProfileDidChange,
            object: nil
        )
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let wasOnSpeakerPage = self.page == .speaker

        coordinator.animate(alongsideTransition: { _ in
            self.updateCallUI(size: size)
            self.videoGrid.reloadData()
            self.videoOverflow.reloadData()
            self.scrollView.contentOffset = wasOnSpeakerPage ? CGPoint(x: 0, y: size.height) : .zero
        }, completion: nil)
    }

    private var hasAppeared = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard !hasAppeared else { return }
        hasAppeared = true

        callService.sendInitialPhoneOrientationNotification()

        if let splitViewSnapshot = SignalApp.shared.snapshotSplitViewController(afterScreenUpdates: false) {
            view.superview?.insertSubview(splitViewSnapshot, belowSubview: view)
            splitViewSnapshot.autoPinEdgesToSuperviewEdges()

            view.transform = .scale(1.5)
            view.alpha = 0

            UIView.animate(withDuration: 0.2, animations: {
                self.view.alpha = 1
                self.view.transform = .identity
            }) { _ in
                splitViewSnapshot.removeFromSuperview()
            }
        }
    }

    private var isReadyToHandleObserver = false
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        self.isReadyToHandleObserver = true

        updateCallUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if hasUnresolvedSafetyNumberMismatch && CurrentAppContext().isAppForegroundAndActive() {
            // If we're not active yet, this will be handled by the `didBecomeActive` callback.
            resolveSafetyNumberMismatch()
        }
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        super.present(viewControllerToPresent, animated: flag, completion: completion)
        scheduleBottomSheetTimeoutIfNecessary()
    }

    private var bottomSheetIsPresented: Bool {
        bottomSheet.presentingViewController != nil
    }

    private func presentBottomSheet() {
        guard !bottomSheetIsPresented else { return }
        bottomSheet.setBottomSheetMinimizedHeight()
        present(self.bottomSheet, animated: true)
    }

    private func dismissBottomSheet(animated: Bool = true) {
        guard bottomSheetIsPresented else { return }
        bottomSheet.dismiss(animated: animated)
    }

    @objc
    private func didBecomeActive() {
        if hasUnresolvedSafetyNumberMismatch {
            resolveSafetyNumberMismatch()
        }
    }

    @objc
    private func didCompleteAnySpamChallenge() {
        AppEnvironment.shared.callLinkProfileKeySharingManager.sendProfileKeyToParticipants(ofCall: self.groupCall)
        self.ringRtcCall.resendMediaKeys()
    }

    // MARK: Call members

    private func updateScrollViewFrames(size: CGSize? = nil) {
        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        if !self.hasAtLeastTwoOthers {
            videoGrid.frame = .zero
            videoGrid.isHidden = true
            speakerPage.frame = CGRect(
                x: 0,
                y: 0,
                width: size.width,
                height: size.height
            )
            scrollView.contentSize = size
            scrollView.contentOffset = .zero
            scrollView.isScrollEnabled = false
        } else {
            let wasVideoGridHidden = videoGrid.isHidden
            let hasOverflowMembersInGridView = videoGrid.maxItems < ringRtcCall.remoteDeviceStates.count
            let overflowGridHeight = hasOverflowMembersInGridView ? videoOverflow.height + 27 : 0

            scrollView.isScrollEnabled = true
            videoGrid.isHidden = false
            let height: CGFloat
            let offset: CGFloat
            switch bottomSheetStateManager.bottomSheetState {
            case .callControlsAndOverflow, .callControls, .callInfo, .transitioning:
                offset = self.bottomSheet.minimizedHeight
            case .hidden:
                offset = 16
            }
            height = size.height - view.safeAreaInsets.top - offset - overflowGridHeight
            videoGrid.frame = CGRect(
                x: 0,
                y: view.safeAreaInsets.top,
                width: size.width,
                height: height
            )
            speakerPage.frame = CGRect(
                x: 0,
                y: size.height,
                width: size.width,
                height: size.height
            )
            scrollView.contentSize = CGSize(width: size.width, height: size.height * 2)

            if wasVideoGridHidden {
                scrollView.contentOffset = .zero
            }
        }
    }

    func updateVideoOverflowTrailingConstraint() {
        var trailingConstraintConstant = -(GroupCallVideoOverflow.itemHeight * ReturnToCallViewController.inherentPipSize.aspectRatio + 4)
        if view.width + trailingConstraintConstant > videoOverflow.contentSize.width {
            trailingConstraintConstant += 16
        }
        videoOverflowTrailingConstraint.constant = trailingConstraintConstant
        view.layoutIfNeeded()
    }

    @discardableResult
    private func pinWidthWithBottomSheetMaxWidth(_ view: UIView) -> [NSLayoutConstraint] {
        let maxWidthConstraint = view.autoSetDimension(
            .width,
            toSize: bottomSheet.maxWidth,
            relation: .lessThanOrEqual
        )
        let edgesConstraints = view.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
        let edgesConstraints2 = view.autoPinWidthToSuperviewMargins(relation: .equal)
        edgesConstraints2.forEach { $0.priority = .defaultHigh }
        return [maxWidthConstraint] + edgesConstraints + edgesConstraints2
    }

    private var addOnsConstraints: [NSLayoutConstraint]?
    private func constrainAddOnsOutsideBottomVStack() {
        addOnsConstraints.map(fullscreenLocalMemberAddOnsView.removeConstraints(_:))
        addOnsConstraints = [
            fullscreenLocalMemberAddOnsView.autoPinLeadingToSuperviewMargin(),
            fullscreenLocalMemberAddOnsView.autoPinTrailingToSuperviewMargin(),
            fullscreenLocalMemberAddOnsView.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: Constants.flipCamButtonTrailingToSuperviewEdgePadding),
        ]
    }
    private func constrainAddOnsInsideBottomVStack() {
        addOnsConstraints.map(fullscreenLocalMemberAddOnsView.removeConstraints(_:))
        addOnsConstraints = pinWidthWithBottomSheetMaxWidth(fullscreenLocalMemberAddOnsView)
    }
    private func updateAddOnsViewPosition() {
        let canFitNextToDrawer = view.width >= bottomSheet.maxWidth + view.layoutMargins.totalWidth + view.layoutMargins.trailing + 48

        if canFitNextToDrawer {
            guard fullscreenLocalMemberAddOnsView.superview != view else { return }

            bottomVStack.removeArrangedSubview(fullscreenLocalMemberAddOnsView)
            view.addSubview(fullscreenLocalMemberAddOnsView)
            constrainAddOnsOutsideBottomVStack()
        } else {
            guard fullscreenLocalMemberAddOnsView.superview != bottomVStack else { return }

            fullscreenLocalMemberAddOnsView.removeFromSuperview()
            if
                case .callLink = groupCall.concreteType,
                let toastIndex = bottomVStack.arrangedSubviews.firstIndex(of: callLinkLobbyToast) {
                bottomVStack.insertArrangedSubview(fullscreenLocalMemberAddOnsView, at: toastIndex)
            } else {
                bottomVStack.addArrangedSubview(fullscreenLocalMemberAddOnsView)
            }
            constrainAddOnsInsideBottomVStack()
        }
    }

    private var shouldHideAddOnsView: Bool {
        !groupCall.isJustMe || (groupCall.isJustMe && call.isOutgoingVideoMuted) || hasDismissed
    }

    private func updateBottomVStackItems() {
        let hasRaisedHands = !self.raisedHandsToast.raisedHands.isEmpty
        self.raisedHandsToastContainer.isHiddenInStackView = !hasRaisedHands
        self.fullscreenLocalMemberAddOnsView.isHiddenInStackView = self.shouldHideAddOnsView
        self.updateAddOnsViewPosition()

        /// If there are no approval requests, `callLinkApprovalViewModel`'s height
        /// will be zero, but we don't want to hide it because the approval view
        /// itself is pinned to it, and we want it to retain its position when
        /// the last item animates out.
        let hasApprovalRequests: Bool = switch self.groupCall.concreteType {
        case .groupThread: false
        case .callLink: !self.callLinkApprovalViewModel.requests.isEmpty
        }

        let hasOverflowMembers = self.videoOverflow.hasOverflowMembers
        if hasOverflowMembers {
            // Move video overflow to bottom
            if self.bottomVStack.arrangedSubviews.last != self.videoOverflowContainer {
                self.bottomVStack.removeArrangedSubview(self.videoOverflowContainer)
                self.bottomVStack.addArrangedSubview(self.videoOverflowContainer)
            }
        } else {
            // Move video overflow to top
            if self.bottomVStack.arrangedSubviews.first != self.videoOverflowContainer {
                self.bottomVStack.removeArrangedSubview(self.videoOverflowContainer)
                self.bottomVStack.insertArrangedSubview(self.videoOverflowContainer, at: 0)
            }
        }

        enum Item { case raisedHands, approvals }
        func setSpacing(_ spacing: CGFloat, after item: Item) {
            let view: UIView = switch item {
            case .raisedHands: self.raisedHandsToastContainer
            case .approvals: self.approvalStackHeightView
            }
            self.bottomVStack.setCustomSpacing(spacing, after: view)
        }

        let overflowNeedsPadding = hasOverflowMembers && self.page == .grid
        switch (overflowNeedsPadding, hasRaisedHands, hasApprovalRequests) {
        case (false, _, true):
            setSpacing(Constants.bottomVStackSpacing, after: .raisedHands)
            setSpacing(Constants.bottomVStackSpacing, after: .approvals)
        case (false, _, false):
            setSpacing(Constants.bottomVStackSpacing, after: .raisedHands)
            setSpacing(0, after: .approvals)
        case (true, _, true):
            setSpacing(Constants.bottomVStackSpacing, after: .raisedHands)
            setSpacing(Constants.videoOverflowExtraSpacing, after: .approvals)
        case (true, true, false):
            setSpacing(Constants.videoOverflowExtraSpacing, after: .raisedHands)
            setSpacing(0, after: .approvals)
        case (true, false, false):
            // Raised hands view is hidden
            setSpacing(0, after: .approvals)
        }
    }

    private enum Constants {
        static let spacingTopRaiseHandToastToBottomLocalPip: CGFloat = 12
        static let flipCamButtonTrailingToSuperviewEdgePadding: CGFloat = 34
        static let bottomVStackSpacing: CGFloat = 8
        static let videoOverflowExtraSpacing: CGFloat = 24
    }

    private func updateMemberViewFrames(
        size: CGSize? = nil,
        shouldRepositionBottomVStack: Bool = true
    ) {
        guard !isPipAnimationInProgress else {
            // Wait for the pip to reach its new size before re-laying out.
            // Otherwise the pip snaps back to its size at the start of the
            // animation, effectively undoing it. When the animation is
            // complete, we'll call `updateMemberViewFrames`.
            self.shouldRelayoutAfterPipAnimationCompletes = true
            self.postAnimationUpdateMemberViewFramesSize = size
            return
        }

        view.layoutIfNeeded()

        let size = size ?? view.frame.size

        let yMax: CGFloat
        if shouldRepositionBottomVStack {
            switch bottomSheetStateManager.bottomSheetState {
            case .callControlsAndOverflow, .callControls, .callInfo, .transitioning:
                yMax = size.height - bottomSheet.minimizedHeight - 16
            case .hidden:
                yMax = size.height - 32
            }
            bottomVStackTopConstraint.constant = yMax
        } else {
            yMax = bottomVStackTopConstraint.constant
        }

        updateVideoOverflowTrailingConstraint()

        localMemberView.applyChangesToCallMemberViewAndVideoView { view in
            view.removeFromSuperview()
        }

        speakerView.applyChangesToCallMemberViewAndVideoView { view in
            view.removeFromSuperview()
        }
        if groupCall.isJustMe {
            localMemberView.applyChangesToCallMemberViewAndVideoView { view in
                speakerPage.addSubview(view)
                view.frame = CGRect(origin: .zero, size: size)
            }
        } else {
            speakerView.applyChangesToCallMemberViewAndVideoView { view in
                speakerPage.addSubview(view)
                view.autoPinEdgesToSuperviewEdges()
            }

            localMemberView.applyChangesToCallMemberViewAndVideoView { aView in
                view.insertSubview(aView, belowSubview: callControlsConfirmationToastContainerView)
            }

            let pipSize = CallMemberView.pipSize(
                expandedPipFrame: self.expandedPipFrame,
                remoteDeviceCount: ringRtcCall.remoteDeviceStates.count
            )

            let y: CGFloat
            if nil != expandedPipFrame {
                // Special case necessary because when the pip is
                // expanded, the pip height does not follow along
                // with that of the video overflow, which is tiny.
                if self.raisedHandsToastContainer.isHiddenInStackView || (self.videoOverflow.hasOverflowMembers && self.page == .grid) {
                    // Bottom of pip should align with bottom of overflow (whether the overflow is hidden or not).
                    y = yMax - pipSize.height
                } else {
                    // Bottom of pip should align with top of raised hand toast, plus padding.
                    y = yMax - pipSize.height - raisedHandsToastContainer.height - Constants.spacingTopRaiseHandToastToBottomLocalPip
                }
            } else {
                let overflowY = videoOverflow.convert(videoOverflow.bounds.origin, to: self.view).y
                let overflowPipHeightDifference = pipSize.height - videoOverflow.height
                y = overflowY - overflowPipHeightDifference
            }
            localMemberView.applyChangesToCallMemberViewAndVideoView { view in
                view.frame = CGRect(
                    x: size.width - pipSize.width - 16,
                    y: y,
                    width: pipSize.width,
                    height: pipSize.height
                )
            }
            flipCameraTooltipManager.presentTooltipIfNecessary(
                fromView: self.view,
                widthReferenceView: self.view,
                tailReferenceView: localMemberView,
                tailDirection: .down,
                isVideoMuted: call.isOutgoingVideoMuted
            )
        }
    }

    // MARK: Other UI

    private func updateSwipeToastView() {
        let isSpeakerViewAvailable = self.hasAtLeastTwoOthers
        guard isSpeakerViewAvailable else {
            swipeToastView.isHidden = true
            return
        }

        if isAnyRemoteDeviceScreenSharing {
            if didUserEverSwipeToScreenShare {
                swipeToastView.isHidden = true
                return
            }
        } else if didUserEverSwipeToSpeakerView {
            swipeToastView.isHidden = true
            return
        }

        swipeToastView.alpha = 1.0 - (scrollView.contentOffset.y / view.height)
        swipeToastView.text = isAnyRemoteDeviceScreenSharing
            ? OWSLocalizedString(
                "GROUP_CALL_SCREEN_SHARE_TOAST",
                comment: "Toast view text informing user about swiping to screen share"
            )
            : OWSLocalizedString(
                "GROUP_CALL_SPEAKER_VIEW_TOAST",
                comment: "Toast view text informing user about swiping to speaker view"
            )

        if scrollView.contentOffset.y >= view.height {
            swipeToastView.isHidden = true

            if isAnyRemoteDeviceScreenSharing {
                if !isAutoScrollingToScreenShare {
                    didUserEverSwipeToScreenShare = true
                    SSKEnvironment.shared.databaseStorageRef.asyncWrite { writeTx in
                        Self.keyValueStore.setBool(true, key: Self.didUserSwipeToScreenShareKey, transaction: writeTx.asV2Write)
                    }
                }
            } else {
                didUserEverSwipeToSpeakerView = true
                SSKEnvironment.shared.databaseStorageRef.asyncWrite { writeTx in
                    Self.keyValueStore.setBool(true, key: Self.didUserSwipeToSpeakerViewKey, transaction: writeTx.asV2Write)
                }
            }

        } else if swipeToastView.isHidden {
            swipeToastView.alpha = 0
            swipeToastView.isHidden = false
            UIView.animate(withDuration: 0.2, delay: 3.0, options: []) {
                self.swipeToastView.alpha = 1
            }
        }
    }

    private var flipCameraTooltipManager = FlipCameraTooltipManager(db: DependenciesBridge.shared.db)

    private var hasShownCallControls = false

    private func updateCallUI(
        size: CGSize? = nil,
        shouldAnimateViewFrames: Bool = false,
        bottomSheetChangedStateFrom oldBottomSheetState: BottomSheetState? = nil
    ) {
        let isFullScreen = groupCall.isJustMe
        localMemberView.configure(
            call: call,
            isFullScreen: isFullScreen
        )

        localMemberView.applyChangesToCallMemberViewAndVideoView { view in
            // In the context of `isCallInPip`, the "pip" refers to when the entire call is in a pip
            // (ie, minimized in the app). This is not to be confused with the local member view pip
            // (ie, when the call is full screen and the local user is displayed in a pip).
            // The following line disallows having a [local member] pip within a [call] pip.
            view.isHidden = !isJustMe && AppEnvironment.shared.windowManagerRef.isCallInPip
        }

        if let speakerState = ringRtcCall.remoteDeviceStates.sortedBySpeakerTime.first {
            speakerView.configure(
                call: call,
                remoteGroupMemberDeviceState: speakerState
            )
        } else {
            speakerView.clearConfiguration()
        }

        guard !isCallMinimized else { return }

        if
            case .groupThread(let groupThreadCall) = groupCall.concreteType,
            groupThreadCall.groupCallRingState.isIncomingRing
        {
            dismissBottomSheet(animated: false)
            createIncomingCallControlsIfNeeded().isHidden = false
            // These views aren't visible at this point, but we need them to be configured anyway.
            updateMemberViewFrames(size: size)
            updateScrollViewFrames(size: size)
            return
        } else if !self.hasShownCallControls {
            self.presentBottomSheet()
            self.hasShownCallControls = true
        }

        if let incomingCallControls, !incomingCallControls.isHidden {
            // We were showing the incoming call controls, but now we don't want to.
            // To make sure all views transition properly, pretend we were showing the regular controls all along.
            presentBottomSheet()

            incomingCallControls.isHidden = true
        }

        self.callControlDisplayStateDidChange(
            oldState: oldBottomSheetState ?? self.bottomSheetStateManager.bottomSheetState,
            newState: self.bottomSheetStateManager.bottomSheetState,
            size: size,
            shouldAnimateViewFrames: shouldAnimateViewFrames
        )

        // Update constraints that hug call controls sheet
        callControlsOverflowBottomConstraint?.constant = callControlsOverflowBottomConstraintConstant
        callControlsConfirmationToastContainerViewBottomConstraint?.constant = callControlsConfirmationToastContainerViewBottomConstraintConstant

        if groupCall.isJustMe {
            flipCameraTooltipManager.dismissTooltip()
        }

        updateSwipeToastView()
    }

    private var callControlsOverflowBottomConstraintConstant: CGFloat {
        -self.bottomSheet.minimizedHeight - 12
    }

    private var callControlsConfirmationToastContainerViewBottomConstraintConstant: CGFloat {
        return -self.bottomSheet.minimizedHeight - 16
    }

    private func callControlDisplayStateDidChange(
        oldState: BottomSheetState,
        newState: BottomSheetState,
        size: CGSize?,
        shouldAnimateViewFrames: Bool
    ) {
        func updateFrames(controlsAreHidden: Bool, shouldRepositionBottomVStack: Bool = true) {
            let raisedHandsToastWasAlreadyHidden = self.raisedHandsToastContainer.isHidden

            let action: () -> Void = {
                self.updateBottomVStackItems()
                self.updateMemberViewFrames(
                    size: size,
                    shouldRepositionBottomVStack: shouldRepositionBottomVStack
                )
                self.updateScrollViewFrames(size: size)
            }
            let completion: () -> Void = {
                if
                    self.raisedHandsToast.raisedHands.isEmpty,
                    !raisedHandsToastWasAlreadyHidden
                {
                    self.raisedHandsToast.wasHidden()
                }
            }

            if shouldAnimateViewFrames {
                let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)
                animator.addAnimations(action)
                animator.addCompletion { _ in
                    completion()
                }
                animator.startAnimation()
            } else {
                action()
                completion()
            }
        }

        switch oldState {
        case .callControlsAndOverflow:
            switch newState {
            case .callControlsAndOverflow:
                updateFrames(controlsAreHidden: false)
            case .callControls:
                self.callControlsOverflowView.animateOut()
                updateFrames(controlsAreHidden: false)
            case .hidden:
                // This can happen if you tap the root view fast enough in succession.
                animateCallControls(
                    hideCallControls: true,
                    size: size
                )
                self.callControlsOverflowView.animateOut()
            case .callInfo, .transitioning:
                self.callControlsOverflowView.animateOut()
            }
        case .callControls:
            switch newState {
            case .callControlsAndOverflow:
                self.callControlsOverflowView.animateIn()
                updateFrames(controlsAreHidden: false)
            case .callControls:
                updateFrames(controlsAreHidden: false)
            case .hidden:
                animateCallControls(
                    hideCallControls: true,
                    size: size
                )
            case .callInfo, .transitioning:
                break
            }
        case .hidden:
            switch newState {
            case .callControlsAndOverflow:
                owsFailDebug("Impossible bottomSheetStateManager.bottomSheetState transition")
                // But if you must...
                animateCallControls(
                    hideCallControls: false,
                    size: size
                )
                self.callControlsOverflowView.animateIn()
            case .callControls, .callInfo, .transitioning:
                animateCallControls(
                    hideCallControls: false,
                    size: size
                )
            case .hidden:
                updateFrames(controlsAreHidden: true)
            }
        case .callInfo, .transitioning:
            switch newState {
            case .callControlsAndOverflow:
                self.callControlsOverflowView.animateIn()
            case .callControls:
                updateFrames(controlsAreHidden: false, shouldRepositionBottomVStack: false)
            case .callInfo, .transitioning:
                updateFrames(controlsAreHidden: true, shouldRepositionBottomVStack: false)
            case .hidden:
                owsFailDebug("Impossible bottomSheetStateManager.bottomSheetState transition")
            }
        }
    }

    private func animateCallControls(
        hideCallControls: Bool,
        size: CGSize?
    ) {
        if hideCallControls {
            dismissBottomSheet()
        } else {
            bottomSheet.setBottomSheetMinimizedHeight()
            presentBottomSheet()
        }
        bottomSheet.transitionCoordinator?.animateAlongsideTransition(in: view, animation: { _ in
            self.callHeader.alpha = hideCallControls ? 0 : 1

            self.updateBottomVStackItems()
            self.updateMemberViewFrames(size: size)
            self.updateScrollViewFrames(size: size)
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.callHeader.isHidden = hideCallControls
            // If a hand is raised during this animation, the toast will be
            // positioned wrong unless this is called again in the completion.
            self.updateBottomVStackItems()

            if self.raisedHandsToast.raisedHands.isEmpty {
                self.raisedHandsToast.wasHidden()
            }
        })
        callHeader.isHidden = false
    }

    private func dismissCall(shouldHangUp: Bool = true) {
        if shouldHangUp {
            callService.callUIAdapter.localHangupCall(call)
        }
        didHangupCall()
    }

    private func didHangupCall() {
        guard !hasDismissed else {
            return
        }
        hasDismissed = true

        guard self.isViewLoaded else {
            // This can happen if the call is canceled before it's ever shown (ie a
            // ring that's not answered).
            AppEnvironment.shared.windowManagerRef.endCall(viewController: self)
            return
        }

        bottomSheetStateManager.submitState(.callControls)
        self.raisedHandsToast.raisedHands.removeAll()
        self.callLinkApprovalViewModel.requests.removeAll()

        guard
            let splitViewSnapshot = SignalApp.shared.snapshotSplitViewController(afterScreenUpdates: false),
            view.superview?.insertSubview(splitViewSnapshot, belowSubview: view) != nil
        else {
            // This can happen if we're in the background when the call is dismissed (say, from CallKit).
            AppEnvironment.shared.windowManagerRef.endCall(viewController: self)
            return
        }

        splitViewSnapshot.autoPinEdgesToSuperviewEdges()

        bottomSheet.cancelAnimationAndUpdateConstraints()
        bottomSheet.dismiss(animated: true) { [self] in
            dismissSelf(splitViewSnapshot: splitViewSnapshot)
        }
    }

    private func dismissSelf(splitViewSnapshot: UIView) {
        UIView.animate(withDuration: 0.2, animations: {
            self.view.alpha = 0
        }) { _ in
            splitViewSnapshot.removeFromSuperview()
            AppEnvironment.shared.windowManagerRef.endCall(viewController: self)
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    private var hasAtLeastTwoOthers: Bool {
        switch ringRtcCall.localDeviceState.joinState {
        case .notJoined, .joining, .pending:
            return false
        case .joined:
            return ringRtcCall.remoteDeviceStates.count >= 2
        }
    }

    /// The view controller to present new view controllers from.
    private var presenter: UIViewController {
        presentedViewController ?? self
    }

    private func presentApprovalRequestDetails(approvalRequest: CallLinkApprovalRequest) {
        let presenter = self.presenter
        // Present request details on top of the bulk request sheet by checking
        // one layer deeper than `presenter`.
        let presentingViewController = presenter.presentedViewController ?? presenter
        CallLinkApprovalRequestDetailsSheet(
            approvalRequest: approvalRequest,
            approvalViewModel: self.callLinkApprovalViewModel
        )
        .present(from: presentingViewController, dismissalDelegate: self)
    }

    private func presentBulkApprovalSheet() {
        CallLinkBulkApprovalSheet(viewModel: callLinkApprovalViewModel)
            .present(from: presenter, dismissalDelegate: self)
    }

    // MARK: - Drawer timeout

    @objc
    private func didTouchRootView(sender: UIGestureRecognizer) {
        switch self.bottomSheetStateManager.bottomSheetState {
        case .callControlsAndOverflow, .hidden:
            bottomSheetStateManager.submitState(.callControls)
        case .callControls:
            if bottomSheetMustBeVisible {
                return
            }
            bottomSheetStateManager.submitState(.hidden)
        case .callInfo:
            bottomSheetStateManager.submitState(.callControls)
            self.bottomSheet.minimizeHeight()
        case .transitioning:
            break
        }
    }

    private var bottomSheetMustBeVisible: Bool {
        return groupCall.isJustMe
    }

    private var sheetTimeoutTimer: Timer?
    private func scheduleBottomSheetTimeoutIfNecessary() {
        let shouldAutomaticallyDismissDrawer: Bool = {
            switch self.bottomSheetStateManager.bottomSheetState {
            case .callControlsAndOverflow, .hidden:
                return false
            case .callControls:
                break
            case .callInfo, .transitioning:
                return false
            }

            if bottomSheetMustBeVisible {
                return false
            }

            if isCallMinimized {
                return false
            }

            let isPresentingOtherSheet = presentedViewController != nil && presentedViewController != bottomSheet
            let otherSheetIsPresented = isPresentingOtherSheet || bottomSheet.presentedViewController != nil
            if otherSheetIsPresented {
                return false
            }

            return true
        }()

        guard shouldAutomaticallyDismissDrawer else {
            cancelBottomSheetTimeout()
            return
        }

        guard sheetTimeoutTimer == nil else { return }
        sheetTimeoutTimer = .scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.timeoutBottomSheet()
        }
    }

    private func timeoutBottomSheet() {
        self.sheetTimeoutTimer = nil
        bottomSheetStateManager.submitState(.hidden)
    }

    private func cancelBottomSheetTimeout() {
        sheetTimeoutTimer?.invalidate()
        sheetTimeoutTimer = nil
    }

    private func showCallControlsIfTheyMustBeVisible() {
        if bottomSheetMustBeVisible {
            showCallControlsIfHidden()
        }
    }

    private func showCallControlsIfHidden() {
        switch self.bottomSheetStateManager.bottomSheetState {
        case .callControlsAndOverflow, .callControls:
            break
        case .hidden:
            bottomSheetStateManager.submitState(.callControls)
        case .callInfo, .transitioning:
            break
        }
    }

    // MARK: - Ringing/Incoming Call Controls

    private func createIncomingCallControlsIfNeeded() -> IncomingCallControls {
        if let incomingCallControls {
            return incomingCallControls
        }
        let incomingCallControls = IncomingCallControls(
            isVideoCall: true,
            didDeclineCall: { [unowned self] in self.dismissCall() },
            didAcceptCall: { [unowned self] hasVideo in self.acceptRingingIncomingCall(hasVideo: hasVideo) }
        )
        self.view.addSubview(incomingCallControls)
        incomingCallControls.autoPinWidthToSuperview()
        incomingCallControls.autoPinEdge(toSuperviewEdge: .bottom)
        self.incomingCallControls = incomingCallControls
        return incomingCallControls
    }

    private func acceptRingingIncomingCall(hasVideo: Bool) {
        // Explicitly unmute video in order to request permissions as needed.
        // (Audio is unmuted as part of the call UI adapter.)

        callService.updateIsLocalVideoMuted(isLocalVideoMuted: !hasVideo)
        // When turning off video, default speakerphone to on.
        if !hasVideo, !callService.audioService.hasExternalInputs {
            callService.audioService.requestSpeakerphone(call: call, isEnabled: true)
        }

        callService.callUIAdapter.answerCall(call)
    }

    // MARK: Profile updates

    @objc
    private func otherUsersProfileChanged(notification: Notification) {
        AssertIsOnMainThread()

        guard let changedAddress = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
              changedAddress.isValid else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }

        if let peekInfo = self.ringRtcCall.peekInfo {
            let joinedAndPendingMembers = peekInfo.joinedMembers + peekInfo.pendingUsers

            if joinedAndPendingMembers.contains(where: { uuid in
                changedAddress == SignalServiceAddress(Aci(fromUUID: uuid))
            }) {
                self.bottomSheet.updateMembers()

                switch self.ringRtcCall.kind {
                case .signalGroup:
                    break
                case .callLink:
                    // Refresh profiles in call link admin approval UI.
                    self.callLinkApprovalViewModel.loadRequestsWithSneakyTransaction(for: peekInfo.pendingUsers)
                }
            }
        }
    }
}

// MARK: CallViewControllerWindowReference

extension GroupCallViewController: CallViewControllerWindowReference {
    var localVideoViewReference: CallMemberView { localMemberView }
    var remoteVideoViewReference: CallMemberView { speakerView }

    var remoteVideoAddress: SignalServiceAddress {
        guard let firstMember = ringRtcCall.remoteDeviceStates.sortedByAddedTime.first else {
            return DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aciAddress
        }
        return firstMember.address
    }

    var isJustMe: Bool {
        groupCall.isJustMe
    }

    public func returnFromPip(pipWindow: UIWindow) {
        // The call "pip" uses our remote and local video views since only
        // one `AVCaptureVideoPreviewLayer` per capture session is supported.
        // We need to re-add them when we return to this view.
        guard speakerView.superview != speakerPage && localMemberView.superview != view else {
            return owsFailDebug("unexpectedly returned to call while we own the video views")
        }

        guard let splitViewSnapshot = SignalApp.shared.snapshotSplitViewController(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot rootViewController")
        }

        guard let pipSnapshot = pipWindow.snapshotView(afterScreenUpdates: false) else {
            return owsFailDebug("failed to snapshot pip")
        }

        isCallMinimized = false

        showCallControlsIfHidden()

        animateReturnFromPip(pipSnapshot: pipSnapshot, pipFrame: pipWindow.frame, splitViewSnapshot: splitViewSnapshot)
    }

    func willMoveToPip(pipWindow: UIWindow) {
        flipCameraTooltipManager.dismissTooltip()
        localMemberView.applyChangesToCallMemberViewAndVideoView { view in
            if !isJustMe {
                view.isHidden = true
            } else {
                view.frame = CGRect(origin: .zero, size: pipWindow.bounds.size)
            }
        }
    }

    private func animateReturnFromPip(pipSnapshot: UIView, pipFrame: CGRect, splitViewSnapshot: UIView) {
        guard let window = view.window else { return owsFailDebug("missing window") }
        view.superview?.insertSubview(splitViewSnapshot, belowSubview: view)
        splitViewSnapshot.autoPinEdgesToSuperviewEdges()

        let originalContentOffset = scrollView.contentOffset

        view.frame = pipFrame
        view.addSubview(pipSnapshot)
        pipSnapshot.autoPinEdgesToSuperviewEdges()

        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.2, animations: {
            pipSnapshot.alpha = 0
            self.view.frame = window.frame
            self.updateCallUI()
            self.videoGrid.reloadData()
            self.scrollView.contentOffset = originalContentOffset
            self.view.layoutIfNeeded()
        }) { _ in
            splitViewSnapshot.removeFromSuperview()
            pipSnapshot.removeFromSuperview()

            if self.hasUnresolvedSafetyNumberMismatch {
                self.resolveSafetyNumberMismatch()
            }
        }
    }

    private func safetyNumberMismatchAddresses(untrustedThreshold: Date?) -> [SignalServiceAddress] {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let addressesToCheck: [SignalServiceAddress]
            if
                case .groupThread(let groupThreadCall) = groupCall.concreteType,
                ringRtcCall.localDeviceState.joinState == .notJoined
            {
                // If we haven't joined the call yet, we want to alert for all members of the group
                let groupThread = TSGroupThread.fetch(forGroupId: groupThreadCall.groupId, tx: transaction)
                addressesToCheck = groupThread!.recipientAddresses(with: transaction)
            } else {
                // If we are in the call, we only care about safety numbers for the active call participants
                addressesToCheck = ringRtcCall.remoteDeviceStates.map { $0.value.address }
            }

            let identityManager = DependenciesBridge.shared.identityManager
            return addressesToCheck.filter { memberAddress in
                identityManager.untrustedIdentityForSending(
                    to: memberAddress,
                    untrustedThreshold: untrustedThreshold,
                    tx: transaction.asV2Read
                ) != nil
            }
        }
    }

    fileprivate func resolveSafetyNumberMismatch() {
        let resendMediaKeysAndResetMismatch = { [unowned self] in
            self.ringRtcCall.resendMediaKeys()
            self.hasUnresolvedSafetyNumberMismatch = false
        }

        if !isCallMinimized, CurrentAppContext().isAppForegroundAndActive() {
            presentSafetyNumberChangeSheetIfNecessary { [weak self] success in
                guard let self = self else { return }
                if success {
                    resendMediaKeysAndResetMismatch()
                } else {
                    self.dismissCall()
                }
            }
        } else {
            let unresolvedAddresses = safetyNumberMismatchAddresses(untrustedThreshold: nil)
            guard !unresolvedAddresses.isEmpty else {
                // Spurious warning, maybe from delayed callbacks.
                resendMediaKeysAndResetMismatch()
                return
            }

            // If a problematic member was present at join, leaves, and then joins again,
            // we'll still treat them as having been there "since join", but that's okay.
            // It's not worth trying to track this more precisely.
            let atLeastOneUnresolvedPresentAtJoin = unresolvedAddresses.contains { membersAtJoin?.contains($0) ?? false }
            switch groupCall.concreteType {
            case .groupThread(let call):
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                let groupThread = databaseStorage.read { tx in
                    return TSGroupThread.fetch(forGroupId: call.groupId, tx: tx)
                }
                guard let groupThread else {
                    owsFail("Missing thread for active call.")
                }
                SSKEnvironment.shared.notificationPresenterRef.notifyForGroupCallSafetyNumberChange(
                    callTitle: groupThread.groupNameOrDefault,
                    threadUniqueId: groupThread.uniqueId,
                    roomId: nil,
                    presentAtJoin: atLeastOneUnresolvedPresentAtJoin
                )
            case .callLink(let call):
                SSKEnvironment.shared.notificationPresenterRef.notifyForGroupCallSafetyNumberChange(
                    callTitle: call.callLinkState.localizedName,
                    threadUniqueId: nil,
                    roomId: call.callLink.rootKey.deriveRoomId(),
                    presentAtJoin: atLeastOneUnresolvedPresentAtJoin
                )
            }
        }
    }

    fileprivate func presentSafetyNumberChangeSheetIfNecessary(untrustedThreshold: Date? = nil, completion: @escaping (Bool) -> Void) {
        let localDeviceHasNotJoined = ringRtcCall.localDeviceState.joinState == .notJoined
        let newUntrustedThreshold = Date()
        let addressesToAlert = safetyNumberMismatchAddresses(untrustedThreshold: untrustedThreshold)

        // There are no unverified addresses that we're currently concerned about. No need to show a sheet
        guard !addressesToAlert.isEmpty else { return completion(true) }

        if let existingSheet = (presentedViewController as? SafetyNumberConfirmationSheet) ?? (presentedViewController?.presentedViewController as? SafetyNumberConfirmationSheet) {
            // The set of untrusted addresses may have changed.
            // It's a bit clunky, but we'll just dismiss the existing sheet before putting up a new one.
            existingSheet.dismiss(animated: false)
        }

        let continueCallString = OWSLocalizedString("GROUP_CALL_CONTINUE_BUTTON", comment: "Button to continue an ongoing group call")
        let leaveCallString = OWSLocalizedString("GROUP_CALL_LEAVE_BUTTON", comment: "Button to leave a group call")
        let cancelString = CommonStrings.cancelButton

        let approveText: String
        let denyText: String
        if localDeviceHasNotJoined {
            approveText = CallControls.joinButtonLabel(for: call)
            denyText = cancelString
        } else {
            approveText = continueCallString
            denyText = leaveCallString
        }

        let sheet = SafetyNumberConfirmationSheet(
            addressesToConfirm: addressesToAlert,
            confirmationText: approveText,
            cancelText: denyText,
            theme: .translucentDark
        ) { [weak self] didApprove in
            if let self, didApprove {
                self.presentSafetyNumberChangeSheetIfNecessary(untrustedThreshold: newUntrustedThreshold, completion: completion)
            } else {
                completion(false)
            }
        }
        sheet.allowsDismissal = localDeviceHasNotJoined
        presenter.present(sheet, animated: true, completion: nil)
    }
}

// MARK: CallObserver

extension GroupCallViewController: GroupCallObserver {
    func groupCallLocalDeviceStateChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsPrecondition(self.groupCall === call)
        guard self.isReadyToHandleObserver else {
            return
        }

        // It would be nice to animate more device state changes, but some
        // can cause unwanted animations, so only add them as tested.
        let addOnsViewVisibilityWillChange = shouldHideAddOnsView != fullscreenLocalMemberAddOnsView.isHiddenInStackView
        updateCallUI(shouldAnimateViewFrames: addOnsViewVisibilityWillChange)

        let isCallLink: Bool = switch groupCall.concreteType {
        case .groupThread:
            false
        case .callLink:
            true
        }

        Logger.debug("\(ringRtcCall.localDeviceState.joinState)\t\(hasDismissed)")

        switch ringRtcCall.localDeviceState.joinState {
        case .joined:
            if membersAtJoin == nil {
                membersAtJoin = Set(ringRtcCall.remoteDeviceStates.lazy.map { $0.value.address })
            }

            if isCallLink {
                callLinkLobbyToast.isHiddenInStackView = true
            }
        case .pending, .joining, .notJoined:
            membersAtJoin = nil
            if isCallLink, !hasDismissed {
                callLinkLobbyToast.isHiddenInStackView = false
            }
        }
    }

    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsPrecondition(self.groupCall === call)
        guard self.isReadyToHandleObserver else {
            return
        }

        isAnyRemoteDeviceScreenSharing = ringRtcCall.remoteDeviceStates.values.first { $0.sharingScreen == true } != nil

        showCallControlsIfTheyMustBeVisible()

        updateCallUI()
        scheduleBottomSheetTimeoutIfNecessary()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsPrecondition(self.groupCall === call)
        guard self.isReadyToHandleObserver else {
            return
        }

        switch call.concreteType {
        case .groupThread:
            break
        case .callLink:
            let requests = call.ringRtcCall.peekInfo?.pendingUsers ?? []
            self.callLinkApprovalViewModel.loadRequestsWithSneakyTransaction(for: requests)
        }

        updateCallUI()
    }

    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsPrecondition(self.groupCall === call)

        let title: String
        let message: String?
        let shouldDismissCallAfterDismissingActionSheet: Bool

        switch reason {
        case .deviceExplicitlyDisconnected:
            dismissCall(shouldHangUp: false)
            return

        case .hasMaxDevices:
            if let maxDevices = ringRtcCall.maxDevices {
                let formatString = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_%d",
                    tableName: "PluralAware",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices. Embeds {{max device count}}."
                )
                title = String.localizedStringWithFormat(formatString, maxDevices)
                message = nil
            } else {
                title = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_UNKNOWN_COUNT",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices."
                )
                message = nil
            }
            shouldDismissCallAfterDismissingActionSheet = true

        case .removedFromCall:
            title = OWSLocalizedString(
                "GROUP_CALL_REMOVED",
                comment: "The title of an alert when you've been removed from a group call."
            )
            message = OWSLocalizedString(
                "GROUP_CALL_REMOVED_MESSAGE",
                comment: "The message of an alert when you've been removed from a group call."
            )
            shouldDismissCallAfterDismissingActionSheet = true

        case .deniedRequestToJoinCall:
            title = OWSLocalizedString(
                "GROUP_CALL_REQUEST_DENIED",
                comment: "The title of an alert when tried to join a call using a link but the admin rejected your request."
            )
            message = OWSLocalizedString(
                "GROUP_CALL_REQUEST_DENIED_MESSAGE",
                comment: "The message of an alert when tried to join a call using a link but the admin rejected your request."
            )
            shouldDismissCallAfterDismissingActionSheet = true

        case
                .serverExplicitlyDisconnected,
                .callManagerIsBusy,
                .sfuClientFailedToJoin,
                .failedToCreatePeerConnectionFactory,
                .failedToNegotiateSrtpKeys,
                .failedToCreatePeerConnection,
                .failedToStartPeerConnection,
                .failedToUpdatePeerConnection,
                .failedToSetMaxSendBitrate,
                .iceFailedWhileConnecting,
                .iceFailedAfterConnected,
                .serverChangedDemuxId:
            Logger.warn("Group call ended with reason \(reason)")
            title = OWSLocalizedString(
                "GROUP_CALL_UNEXPECTEDLY_ENDED",
                comment: "An error displayed to the user when the group call unexpectedly ends."
            )
            message = nil
            shouldDismissCallAfterDismissingActionSheet = false
        }

        if self.isReadyToHandleObserver {
            showCallControlsIfTheyMustBeVisible()
            updateCallUI()
        }

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okButton,
            style: .default,
            handler: { [weak self] _ in
                if shouldDismissCallAfterDismissingActionSheet {
                    self?.dismissCall()
                }
            }
        ))
        presenter.presentActionSheet(actionSheet)
    }

    func groupCallReceivedReactions(_ call: GroupCall, reactions: [SignalRingRTC.Reaction]) {
        AssertIsOnMainThread()
        owsPrecondition(self.groupCall === call)
        guard self.isReadyToHandleObserver else {
            return
        }
        let localAci = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci
        }
        guard let localAci else {
            owsFailDebug("Local user is in call but doesn't have ACI!")
            return
        }
        let mappedReactions = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return reactions.map { reaction in
                let name: String
                let aci: Aci
                if
                    let remoteDeviceState = ringRtcCall.remoteDeviceStates[reaction.demuxId],
                    remoteDeviceState.aci != localAci
                {
                    name = SSKEnvironment.shared.contactManagerRef.displayName(for: remoteDeviceState.address, tx: tx).resolvedValue()
                    aci = remoteDeviceState.aci
                } else {
                    name = CommonStrings.you
                    aci = localAci
                }
                return Reaction(
                    emoji: reaction.value,
                    name: name,
                    aci: aci,
                    timestamp: Date.timeIntervalSinceReferenceDate
                )
            }
        }
        self.reactionsSink.addReactions(reactions: mappedReactions)
    }

    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        AssertIsOnMainThread()
        owsPrecondition(self.groupCall === call)
        guard self.isReadyToHandleObserver else {
            return
        }
        self.raisedHandsToast.raisedHands = raisedHands
        self.updateCallUI(shouldAnimateViewFrames: true)
    }

    func handleUntrustedIdentityError(_ call: GroupCall) {
        AssertIsOnMainThread()
        owsPrecondition(self.groupCall === call)
        guard self.isReadyToHandleObserver else {
            return
        }
        if !hasUnresolvedSafetyNumberMismatch {
            hasUnresolvedSafetyNumberMismatch = true
            resolveSafetyNumberMismatch()
        }
    }
}

// MARK: CallHeaderDelegate

extension GroupCallViewController: CallHeaderDelegate {
    func didTapBackButton() {
        if groupCall.hasJoinedOrIsWaitingForAdminApproval {
            isCallMinimized = true
            AppEnvironment.shared.windowManagerRef.leaveCallView()
            // This ensures raised hands are removed
            updateCallUI()
        } else {
            dismissCall()
        }
    }

    func didTapMembersButton() {
        switch self.bottomSheetStateManager.bottomSheetState {
        case .callControls, .callControlsAndOverflow, .transitioning:
            bottomSheetStateManager.submitState(.callInfo)
            self.bottomSheet.maximizeHeight(animated: true)
        case .hidden:
            bottomSheetStateManager.submitState(.callInfo)
            self.bottomSheet.maximizeHeight(animated: false)
        case .callInfo:
            bottomSheetStateManager.submitState(.callControls)
            self.bottomSheet.minimizeHeight(animated: true)
        }
    }
}

// MARK: RaisedHandsToastDelegate

extension GroupCallViewController: RaisedHandsToastDelegate {
    func didTapViewRaisedHands() {
        self.didTapMembersButton()
    }

    func raisedHandsToastDidChangeHeight() {
        self.updateCallUI(shouldAnimateViewFrames: true)
    }
}

// MARK: GroupCallVideoOverflowDelegate

extension GroupCallViewController: GroupCallVideoOverflowDelegate {
    var firstOverflowMemberIndex: Int {
        switch self.page {
        case .grid:
            return videoGrid.maxItems
        case .speaker:
            return 1
        }
    }
}

// MARK: UIScrollViewDelegate

extension GroupCallViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let isScrolledPastHalfway = scrollView.contentOffset.y > view.height / 2
        self.page = isScrolledPastHalfway ? .speaker : .grid

        if isAutoScrollingToScreenShare {
            isAutoScrollingToScreenShare = scrollView.contentOffset.y != speakerView.frame.origin.y
        }

        updateSwipeToastView()
    }
}

// MARK: CallControlsDelegate

extension GroupCallViewController: CallControlsDelegate {
    func didPressRing() {
        switch groupCall.concreteType {
        case .groupThread(let groupThreadCall):
            if groupThreadCall.ringRestrictions.isEmpty {
                // Refresh the call header.
                callHeader.groupCallLocalDeviceStateChanged(groupThreadCall)
            } else if groupThreadCall.ringRestrictions.contains(.groupTooLarge) {
                let toast = ToastController(text: OWSLocalizedString("GROUP_CALL_TOO_LARGE_TO_RING", comment: "Text displayed when trying to turn on ringing when calling a large group."))
                toast.presentToastView(from: .top, of: view, inset: view.safeAreaInsets.top + 8)
            }
        case .callLink:
            owsFail("Can't ring a call link")
        }
    }

    func didPressJoin() {
        if call.isFull {
            let text: String
            if let maxDevices = ringRtcCall.maxDevices {
                let formatString = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_%d",
                    tableName: "PluralAware",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices. Embeds {{max device count}}."
                )
                text = String.localizedStringWithFormat(formatString, maxDevices)
            } else {
                text = OWSLocalizedString(
                    "GROUP_CALL_HAS_MAX_DEVICES_UNKNOWN_COUNT",
                    comment: "An error displayed to the user when the group call ends because it has exceeded the max devices."
                )
            }

            let toastController = ToastController(text: text)
            // Leave the toast up longer than usual because this message is pretty long.
            toastController.presentToastView(
                from: .top,
                of: view,
                inset: view.safeAreaInsets.top + 8,
                dismissAfter: .seconds(8)
            )
            return
        }

        presentSafetyNumberChangeSheetIfNecessary { [weak self] success in
            guard let self = self else { return }
            guard success else { return }
            self.callService.joinGroupCallIfNecessary(self.call, groupCall: self.groupCall)
        }
    }

    func didPressHangup() {
        didHangupCall()
    }

    func didPressMore() {
        if self.callControlsOverflowView.isHidden {
            bottomSheetStateManager.submitState(.callControlsAndOverflow)
        } else {
            bottomSheetStateManager.submitState(.callControls)
        }
    }
}

// MARK: CallMemberErrorPresenter

extension GroupCallViewController: CallMemberErrorPresenter {
    func presentErrorSheet(title: String, message: String) {
        let actionSheet = ActionSheetController(title: title, message: message, theme: .translucentDark)
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton))
        presentActionSheet(actionSheet)
    }
}

// MARK: AnimatableLocalMemberViewDelegate

extension GroupCallViewController: AnimatableLocalMemberViewDelegate {
    var enclosingBounds: CGRect {
        return self.view.bounds
    }

    var remoteDeviceCount: Int {
        return ringRtcCall.remoteDeviceStates.count
    }

    func animatableLocalMemberViewDidCompleteExpandAnimation(_ localMemberView: CallMemberView) {
        self.expandedPipFrame = localMemberView.frame
        self.isPipAnimationInProgress = false
        performRetroactiveUiUpdateIfNecessary()
    }

    func animatableLocalMemberViewDidCompleteShrinkAnimation(_ localMemberView: CallMemberView) {
        self.expandedPipFrame = nil
        self.isPipAnimationInProgress = false
        performRetroactiveUiUpdateIfNecessary()
    }

    private func performRetroactiveUiUpdateIfNecessary() {
        if self.shouldRelayoutAfterPipAnimationCompletes {
            if let postAnimationUpdateMemberViewFramesSize {
                updateMemberViewFrames(size: postAnimationUpdateMemberViewFramesSize)
                self.postAnimationUpdateMemberViewFramesSize = nil
            }

            self.shouldRelayoutAfterPipAnimationCompletes = false
        }
    }

    func animatableLocalMemberViewWillBeginAnimation(_ localMemberView: CallMemberView) {
        self.isPipAnimationInProgress = true
        self.flipCameraTooltipManager.dismissTooltip()
    }
}

// MARK: - CallControlsOverflowPresenter

extension GroupCallViewController: CallControlsOverflowPresenter {
    func callControlsOverflowWillAppear() {
        self.cancelBottomSheetTimeout()
    }

    func callControlsOverflowDidDisappear() {
        self.scheduleBottomSheetTimeoutIfNecessary()
    }

    func willSendReaction() {
        bottomSheetStateManager.submitState(.callControls)
    }

    func didTapRaiseOrLowerHand() {
        bottomSheetStateManager.submitState(.callControls)
    }
}

// MARK: - SheetPanDelegate

extension GroupCallViewController: SheetPanDelegate {
    func sheetPanDidBegin() {
        bottomSheetStateManager.submitState(.transitioning)
        self.callControlsConfirmationToastManager.forceDismissToast()
    }

    func sheetPanDidEnd() {
        self.setBottomSheetStateAfterTransition()
    }

    func sheetPanDecelerationDidBegin() {
        bottomSheetStateManager.submitState(.transitioning)
    }

    func sheetPanDecelerationDidEnd() {
        self.setBottomSheetStateAfterTransition()
    }

    private func setBottomSheetStateAfterTransition() {
        if bottomSheet.isPresentingCallInfo() {
            bottomSheetStateManager.submitState(.callInfo)
        } else if bottomSheet.isPresentingCallControls() {
            bottomSheetStateManager.submitState(.callControls)
        } else if bottomSheet.isCrossFading() {
            bottomSheetStateManager.submitState(.transitioning)
        }
    }
}

// MARK: - CallDrawerDelegate

extension GroupCallViewController: CallDrawerDelegate {
    func didPresentViewController(_ viewController: UIViewController) {
        self.scheduleBottomSheetTimeoutIfNecessary()
    }

    func didTapDone() {
        bottomSheetStateManager.submitState(.callControls)
        self.bottomSheet.minimizeHeight()
    }
}

// MARK: - Bottom Sheet State Management

enum BottomSheetState {
    /// "Overflow" refers to the "..." menu that shows reactions & "Raise Hand".
    case callControlsAndOverflow
    case callControls
    case callInfo
    case transitioning
    case hidden
}

/// TODO: It may make sense to pull sheet timeout logic into this class.
class GroupCallBottomSheetStateManager {
    private weak var delegate: GroupCallBottomSheetStateDelegate?
    private(set) var bottomSheetState: BottomSheetState = .callControls {
        didSet {
            guard bottomSheetState != oldValue else { return }
            delegate?.bottomSheetStateDidChange(oldState: oldValue)
        }
    }

    fileprivate init(delegate: GroupCallBottomSheetStateDelegate) {
        self.delegate = delegate
    }

    func submitState(_ state: BottomSheetState) {
        if let delegate, !delegate.areStateChangesSuspended {
            bottomSheetState = state
        }
    }
}

private protocol GroupCallBottomSheetStateDelegate: AnyObject {
    var areStateChangesSuspended: Bool { get }
    func bottomSheetStateDidChange(oldState: BottomSheetState)
}

extension GroupCallViewController: GroupCallBottomSheetStateDelegate {
    var areStateChangesSuspended: Bool {
        self.callControlsOverflowView.isAnimating
    }

    func bottomSheetStateDidChange(oldState: BottomSheetState) {
        updateCallUI(bottomSheetChangedStateFrom: oldState)
        scheduleBottomSheetTimeoutIfNecessary()
    }
}

extension GroupCallViewController: SheetDismissalDelegate {
    func didDismissPresentedSheet() {
        scheduleBottomSheetTimeoutIfNecessary()
    }
}
