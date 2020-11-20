//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

@objc
class GroupCallMemberSheet: UIViewController {
    let contentView = UIView()
    let handle = UIView()
    let backdropView = UIView()

    let tableView = UITableView(frame: .zero, style: .grouped)
    let call: SignalCall

    init(call: SignalCall) {
        self.call = call
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self

        call.addObserverAndSyncState(observer: self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { call.removeObserver(self) }

    // MARK: -

    override public func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        view.addSubview(contentView)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        contentView.autoHCenterInSuperview()
        contentView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)

        if UIAccessibility.isReduceTransparencyEnabled {
            contentView.backgroundColor = .ows_blackAlpha80
        } else {
            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            contentView.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
            contentView.backgroundColor = .ows_blackAlpha40
        }

        // Prefer to be full width, but don't exceed the maximum width
        contentView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentView.autoPinWidthToSuperview()
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.tableHeaderView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: CGFloat.leastNormalMagnitude)))
        contentView.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        tableView.register(GroupCallMemberCell.self, forCellReuseIdentifier: GroupCallMemberCell.reuseIdentifier)
        tableView.register(GroupCallEmptyCell.self, forCellReuseIdentifier: GroupCallEmptyCell.reuseIdentifier)

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()

        updateMembers()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        contentView.layoutIfNeeded()

        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: contentView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(square: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        contentView.layer.mask = shapeLayer
    }

    @objc func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true)
    }

    // MARK: - Resize / Interactive Dismiss

    var heightConstraint: NSLayoutConstraint?
    let maxWidth: CGFloat = 512
    var minimizedHeight: CGFloat {
        return min(maximizedHeight, 346)
    }
    var maximizedHeight: CGFloat {
        return CurrentAppContext().frame.height - topLayoutGuide.length - 32
    }

    let maxAnimationDuration: TimeInterval = 0.2
    var startingHeight: CGFloat?
    var startingTranslation: CGFloat?

    func setupInteractiveSizing() {
        heightConstraint = contentView.autoSetDimension(.height, toSize: minimizedHeight)

        // Create a pan gesture to handle when the user interacts with the
        // view outside of the collection view.
        let panGestureRecognizer = DirectionalPanGestureRecognizer(direction: .vertical, target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.delegate = self

        // We also want to handle the pan gesture for the collection view,
        // so we can do a nice scroll to dismiss gesture, and so we can
        // transfer any initial scrolling into maximizing the view.
        tableView.panGestureRecognizer.addTarget(self, action: #selector(handlePan))

        handle.backgroundColor = .ows_whiteAlpha80
        handle.autoSetDimensions(to: CGSize(width: 56, height: 5))
        handle.layer.cornerRadius = 5 / 2
        view.addSubview(handle)
        handle.autoHCenterInSuperview()
        handle.autoPinEdge(.bottom, to: .top, of: contentView, withOffset: -8)
    }

    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        let isCollectionViewPanGesture = sender == tableView.panGestureRecognizer

        switch sender.state {
        case .began, .changed:
            guard beginInteractiveTransitionIfNecessary(sender),
                let startingHeight = startingHeight,
                let startingTranslation = startingTranslation else {
                    return resetInteractiveTransition()
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            if isCollectionViewPanGesture {
                tableView.contentOffset.y = 0
                tableView.showsVerticalScrollIndicator = false
            }

            // We may have panned some distance if we were scrolling before we started
            // this interactive transition. Offset the translation we use to move the
            // view by whatever the translation was when we started the interactive
            // portion of the gesture.
            let translation = sender.translation(in: view).y - startingTranslation

            var newHeight = startingHeight - translation
            if newHeight > maximizedHeight {
                newHeight = maximizedHeight
            }

            // If the height is decreasing, adjust the relevant view's proporitionally
            if newHeight < startingHeight {
                backdropView.alpha = 1 - (startingHeight - newHeight) / startingHeight
            }

            // Update our height to reflect the new position
            heightConstraint?.constant = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            guard let startingHeight = startingHeight else { break }

            let dismissThreshold = startingHeight * 0.5
            let growThreshold = startingHeight * 1.5
            let velocityThreshold: CGFloat = 500

            let currentHeight = contentView.height
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, dismissing, cancelling }
            let completionState: CompletionState

            if abs(currentVelocity) >= velocityThreshold {
                completionState = currentVelocity < 0 ? .growing : .dismissing
            } else if currentHeight >= growThreshold {
                completionState = .growing
            } else if currentHeight <= dismissThreshold {
                completionState = .dismissing
            } else {
                completionState = .cancelling
            }

            let finalHeight: CGFloat
            switch completionState {
            case .dismissing:
                finalHeight = 0
            case .growing:
                finalHeight = maximizedHeight
            case .cancelling:
                finalHeight = startingHeight

                if isCollectionViewPanGesture {
                    tableView.setContentOffset(tableView.contentOffset, animated: false)
                }
            }

            let remainingDistance = finalHeight - currentHeight

            // Calculate the time to complete the animation if we want to preserve
            // the user's velocity. If this time is too slow (e.g. the user was scrolling
            // very slowly) we'll default to `maxAnimationDuration`
            let remainingTime = TimeInterval(abs(remainingDistance / currentVelocity))

            UIView.animate(withDuration: min(remainingTime, maxAnimationDuration), delay: 0, options: .curveEaseOut, animations: {
                if remainingDistance < 0 {
                    self.contentView.frame.origin.y -= remainingDistance
                    self.handle.frame.origin.y -= remainingDistance
                } else {
                    self.heightConstraint?.constant = finalHeight
                    self.view.layoutIfNeeded()
                }

                self.backdropView.alpha = completionState == .dismissing ? 0 : 1
            }) { _ in
                self.heightConstraint?.constant = finalHeight
                self.view.layoutIfNeeded()

                if completionState == .dismissing {
                    self.dismiss(animated: true)
                }
            }

            resetInteractiveTransition()
        default:
            resetInteractiveTransition()

            backdropView.alpha = 1

            guard let startingHeight = startingHeight else { break }
            heightConstraint?.constant = startingHeight
        }
    }

    func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        // If we're at the top of the scrollView, the the view is not
        // currently maximized, or we're panning outside of the collection
        // view we want to do an interactive transition.
        guard tableView.contentOffset.y <= 0
            || contentView.height < maximizedHeight
            || sender != tableView.panGestureRecognizer else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = contentView.height
        }

        return true
    }

    func resetInteractiveTransition() {
        startingTranslation = nil
        startingHeight = nil
        tableView.showsVerticalScrollIndicator = true
    }

    struct JoinedMember {
        let address: SignalServiceAddress
        let conversationColorName: ConversationColorName
        let displayName: String
        let comparableName: String
        let isAudioMuted: Bool?
        let isVideoMuted: Bool?
    }

    private var sortedMembers = [JoinedMember]()
    func updateMembers() {
        let unsortedMembers: [JoinedMember] = databaseStorage.uiRead { transaction in
            var members = [JoinedMember]()

            if self.call.groupCall.localDeviceState.joinState == .joined {
                members += self.call.groupCall.remoteDeviceStates.values.map { member in
                    let thread = TSContactThread.getWithContactAddress(member.address, transaction: transaction)
                    let displayName: String
                    let comparableName: String
                    if member.address.isLocalAddress {
                        displayName = NSLocalizedString(
                            "GROUP_CALL_YOU_ON_ANOTHER_DEVICE",
                            comment: "Text describing the local user in the group call members sheet when connected from another device."
                        )
                        comparableName = displayName
                    } else {
                        displayName = self.contactsManager.displayName(for: member.address, transaction: transaction)
                        comparableName = self.contactsManager.comparableName(for: member.address, transaction: transaction)
                    }

                    return JoinedMember(
                        address: member.address,
                        conversationColorName: thread?.conversationColorName ?? .default,
                        displayName: displayName,
                        comparableName: comparableName,
                        isAudioMuted: member.audioMuted,
                        isVideoMuted: member.videoMuted
                    )
                }

                guard let localAddress = self.tsAccountManager.localAddress else { return members }

                let thread = TSContactThread.getWithContactAddress(localAddress, transaction: transaction)
                let displayName = NSLocalizedString(
                    "GROUP_CALL_YOU",
                    comment: "Text describing the local user as a participant in a group call."
                )
                let comparableName = displayName

                members.append(JoinedMember(
                    address: localAddress,
                    conversationColorName: thread?.conversationColorName ?? .default,
                    displayName: displayName,
                    comparableName: comparableName,
                    isAudioMuted: self.call.groupCall.isOutgoingAudioMuted,
                    isVideoMuted: self.call.groupCall.isOutgoingVideoMuted
                ))
            } else {
                // If we're not yet in the call, `remoteDeviceStates` will not exist.
                // We can get the list of joined members still, provided we are connected.
                members += self.call.groupCall.peekInfo?.joinedMembers.map { uuid in
                    let address = SignalServiceAddress(uuid: uuid)
                    let thread = TSContactThread.getWithContactAddress(address, transaction: transaction)
                    let displayName = self.contactsManager.displayName(for: address, transaction: transaction)
                    let comparableName = self.contactsManager.comparableName(for: address, transaction: transaction)

                    return JoinedMember(
                        address: address,
                        conversationColorName: thread?.conversationColorName ?? .default,
                        displayName: displayName,
                        comparableName: comparableName,
                        isAudioMuted: nil,
                        isVideoMuted: nil
                    )
                } ?? []
            }

            return members
        }

        sortedMembers = unsortedMembers.sorted { $0.comparableName.caseInsensitiveCompare($1.comparableName) == .orderedAscending }

        tableView.reloadData()
    }
}

extension GroupCallMemberSheet: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedMembers.count > 0 ? sortedMembers.count : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !sortedMembers.isEmpty else {
            return tableView.dequeueReusableCell(withIdentifier: GroupCallEmptyCell.reuseIdentifier, for: indexPath)
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: GroupCallMemberCell.reuseIdentifier, for: indexPath)

        guard let memberCell = cell as? GroupCallMemberCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        guard let member = sortedMembers[safe: indexPath.row] else {
            owsFailDebug("missing member")
            return cell
        }

        memberCell.configure(item: member)

        return memberCell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        label.textColor = Theme.darkThemePrimaryColor

        if sortedMembers.count > 1 {
            let formatString = NSLocalizedString(
                "GROUP_CALL_MANY_IN_THIS_CALL_FORMAT",
                comment: "String indicating how many people are current in the call"
            )
            label.text = String(format: formatString, sortedMembers.count)
        } else if sortedMembers.count > 0 {
            label.text = NSLocalizedString(
                "GROUP_CALL_ONE_IN_THIS_CALL",
                comment: "String indicating one person is currently in the call"
            )
        } else {
            label.text = nil
        }

        let labelContainer = UIView()
        labelContainer.layoutMargins = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
        labelContainer.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        return labelContainer
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return .leastNormalMagnitude
    }
}

// MARK: -
extension GroupCallMemberSheet: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer:
            let point = gestureRecognizer.location(in: view)
            guard !contentView.frame.contains(point) else { return false }
            return true
        default:
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UIPanGestureRecognizer:
            return tableView.panGestureRecognizer == otherGestureRecognizer
        default:
            return false
        }
    }
}

// MARK: -

private class GroupCallMemberSheetAnimationController: UIPresentationController {

    var backdropView: UIView? {
        guard let vc = presentedViewController as? GroupCallMemberSheet else { return nil }
        return vc.backdropView
    }

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        backdropView?.backgroundColor = Theme.backdropColor
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView, let backdropView = backdropView else { return }
        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()
        containerView.layoutIfNeeded()

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 0
        }, completion: { _ in
            self.backdropView?.removeFromSuperview()
        })
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let presentedView = presentedView else { return }
        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        }, completion: nil)
    }
}

extension GroupCallMemberSheet: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return GroupCallMemberSheetAnimationController(presentedViewController: presented, presenting: presenting)
    }
}

extension GroupCallMemberSheet: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }
}

private class GroupCallMemberCell: UITableViewCell {
    static let reuseIdentifier = "GroupCallMemberCell"

    let avatarView = AvatarImageView()
    let avatarDiameter: CGFloat = 36
    let nameLabel = UILabel()
    let videoMutedIndicator = UIImageView()
    let audioMutedIndicator = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        contentView.addSubview(avatarView)
        avatarView.autoPinLeadingToSuperviewMargin()
        avatarView.autoPinHeightToSuperviewMargins()
        avatarView.autoSetDimensions(to: CGSize(square: avatarDiameter))

        nameLabel.font = .ows_dynamicTypeBody
        contentView.addSubview(nameLabel)
        nameLabel.autoPinLeading(toTrailingEdgeOf: avatarView, offset: 8)
        nameLabel.autoPinHeightToSuperviewMargins()

        videoMutedIndicator.contentMode = .scaleAspectFit
        videoMutedIndicator.setTemplateImage(#imageLiteral(resourceName: "video-off-solid-28"), tintColor: .ows_white)
        contentView.addSubview(videoMutedIndicator)
        videoMutedIndicator.autoSetDimensions(to: CGSize(square: 16))
        videoMutedIndicator.autoPinLeading(toTrailingEdgeOf: nameLabel, offset: 16)
        videoMutedIndicator.setContentHuggingHorizontalHigh()
        videoMutedIndicator.autoPinHeightToSuperviewMargins()

        audioMutedIndicator.contentMode = .scaleAspectFit
        audioMutedIndicator.setTemplateImage(#imageLiteral(resourceName: "mic-off-solid-28"), tintColor: .ows_white)
        contentView.addSubview(audioMutedIndicator)
        audioMutedIndicator.autoSetDimensions(to: CGSize(square: 16))
        audioMutedIndicator.autoPinLeading(toTrailingEdgeOf: videoMutedIndicator, offset: 16)
        audioMutedIndicator.setContentHuggingHorizontalHigh()
        audioMutedIndicator.autoPinHeightToSuperviewMargins()
        audioMutedIndicator.autoPinTrailingToSuperviewMargin()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: GroupCallMemberSheet.JoinedMember) {

        let avatarBuilder = OWSContactAvatarBuilder(
            address: item.address,
            colorName: item.conversationColorName,
            diameter: UInt(avatarDiameter)
        )

        nameLabel.textColor = Theme.darkThemePrimaryColor
        videoMutedIndicator.isHidden = item.isVideoMuted != true
        audioMutedIndicator.isHidden = item.isAudioMuted != true

        if item.address.isLocalAddress {
            nameLabel.text = item.displayName
            avatarView.image = OWSProfileManager.shared().localProfileAvatarImage() ?? avatarBuilder.buildDefaultImage()
        } else {
            nameLabel.text = item.displayName
            avatarView.image = avatarBuilder.build()
        }
    }
}

private class GroupCallEmptyCell: UITableViewCell {
    static let reuseIdentifier = "GroupCallEmptyCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        let imageView = UIImageView(image: #imageLiteral(resourceName: "sad-cat"))
        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)
        imageView.autoSetDimensions(to: CGSize(square: 160))
        imageView.autoHCenterInSuperview()
        imageView.autoPinTopToSuperviewMargin(withInset: 32)

        let label = UILabel()
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.textColor = Theme.darkThemePrimaryColor
        label.text = NSLocalizedString("GROUP_CALL_NOBODY_IS_IN_YET",
                                       comment: "Text explaining to the user that nobody has joined this call yet.")
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        contentView.addSubview(label)
        label.autoPinWidthToSuperviewMargins()
        label.autoPinBottomToSuperviewMargin()
        label.autoPinEdge(.top, to: .bottom, of: imageView, withOffset: 16)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
