//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalServiceKit
import UIKit
import BonMot
import PassKit
import SafariServices
import Lottie
import SignalCoreKit

class SubscriptionViewController: OWSTableViewController2 {
    // MARK: - View controller state

    private enum SubscriptionViewState {
        case initializing
        case loading
        case loadFailed
        case loaded(subscriptionLevels: [SubscriptionLevel],
                    selectedCurrencyCode: Currency.Code,
                    selectedSubscriptionLevel: SubscriptionLevel?,
                    currentSubscription: Subscription?)

        public var isApplePayButtonEnabled: Bool {
            switch self {
            case .initializing, .loading, .loadFailed:
                return false
            case let .loaded(_, _, selectedSubscriptionLevel, currentSubscription):
                if let selectedSubscriptionLevel = selectedSubscriptionLevel,
                   let currentSubscription = currentSubscription {
                    return currentSubscription.level != selectedSubscriptionLevel.level
                } else {
                    return true
                }
            }
        }

        public mutating func selectCurrencyCode(_ newValue: Currency.Code) {
            switch self {
            case .initializing, .loading, .loadFailed:
                owsFailDebug("It should be impossible to select a currency code in this state")
            case let .loaded(subscriptionLevels, _, selectedSubscriptionLevel, currentSubscription):
                guard currentSubscription == nil else {
                    owsFailDebug("It should be impossible to select a currency code if there's already a subscription")
                    return
                }
                self = .loaded(subscriptionLevels: subscriptionLevels,
                               selectedCurrencyCode: newValue,
                               selectedSubscriptionLevel: selectedSubscriptionLevel,
                               currentSubscription: currentSubscription)
            }
        }

        public mutating func selectSubscriptionLevel(_ newValue: SubscriptionLevel) {
            switch self {
            case .initializing, .loading, .loadFailed:
                owsFailDebug("It should be impossible to select a subscription level in this state")
            case let .loaded(subscriptionLevels, selectedCurrencyCode, _, currentSubscription):
                self = .loaded(subscriptionLevels: subscriptionLevels,
                               selectedCurrencyCode: selectedCurrencyCode,
                               selectedSubscriptionLevel: newValue,
                               currentSubscription: currentSubscription)
            }
        }
    }

    private var state: SubscriptionViewState = .initializing

    // MARK: - Internal variables

    private var ignoreProfileBadgeStateForNewBadgeRedemption = false
    private var persistedSubscriberID: Data?

    private let sizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight

    private lazy var avatarView: ConversationAvatarView = {
        let newAvatarView = ConversationAvatarView(sizeClass: sizeClass, localUserDisplayMode: .asUser)
        return newAvatarView
    }()

    private var avatarImage: UIImage?

    private var applePayButton: ApplePayButton?

    private lazy var statusLabel: LinkingTextView = LinkingTextView()
    private lazy var descriptionTextView = LinkingTextView()

    private var subscriptionLevelCells: [SubscriptionLevelCell] = []

    private var subscriptionRedemptionPending: Bool {
        var hasPendingJobs = false
        SDSDatabaseStorage.shared.read { transaction in
            hasPendingJobs = SubscriptionManager.subscriptionJobQueue.hasPendingJobs(transaction: transaction)
        }
        hasPendingJobs = hasPendingJobs || SubscriptionManager.subscriptionJobQueue.runningOperations.get().count != 0
        return hasPendingJobs
    }

    private let bottomFooterStackView = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomFooterStackView }
        set {}
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let subscriptionBannerAvatarSize: UInt = 88

    // MARK: - Callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()

        loadAndUpdateStateIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subscriptionRedemptionJobStateDidChange),
            name: SubscriptionManager.SubscriptionJobQueueDidFinishJobNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subscriptionRedemptionJobStateDidChange),
            name: SubscriptionManager.SubscriptionJobQueueDidFailJobNotification,
            object: nil)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAndUpdateStateIfNeeded()

        // If we're the root view, add a cancel button
        if navigationController?.viewControllers.first == self {
            navigationItem.leftBarButtonItem = .init(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(didTapDone)
            )
        }
    }

    @objc
    func didTapDone() {
        self.dismiss(animated: true)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateTableContents()
    }

    @objc
    func subscriptionRedemptionJobStateDidChange(notification: NSNotification) {
        updateTableContents()
    }

    // MARK: - Loading state

    private func loadAndUpdateStateIfNeeded() {
        switch state {
        case .initializing, .loadFailed:
            self.state = .loading
            loadState().done {
                self.state = $0
                self.updateTableContents()
            }
        case .loading, .loaded:
            return
        }
    }

    private func loadState() -> Guarantee<SubscriptionViewState> {
        let (subscriberID, previousCurrencyCode) = SDSDatabaseStorage.shared.read {(
            SubscriptionManager.getSubscriberID(transaction: $0),
            SubscriptionManager.getSubscriberCurrencyCode(transaction: $0)
        )}

        self.persistedSubscriberID = subscriberID

        let currentSubscriptionPromise = DonationViewsUtil.loadCurrentSubscription(subscriberID: subscriberID)

        return firstly {
            DonationViewsUtil.loadSubscriptionLevels(badgeStore: self.profileManager.badgeStore)
        }.then { subscriptionLevels -> Promise<([SubscriptionLevel], Subscription?)> in
            currentSubscriptionPromise.map { currentSubscription in (subscriptionLevels, currentSubscription) }
        }.then { (subscriptionLevels, currentSubscription) -> Guarantee<SubscriptionViewState> in
            let selectedCurrencyCode: Currency.Code
            let selectedSubscriptionLevel: SubscriptionLevel?
            if let currentSubscription = currentSubscription {
                selectedCurrencyCode = previousCurrencyCode ?? currentSubscription.currency
                selectedSubscriptionLevel = subscriptionLevels.first { currentSubscription.level == $0.level } ?? subscriptionLevels.first
            } else {
                selectedCurrencyCode = Stripe.defaultCurrencyCode
                selectedSubscriptionLevel = subscriptionLevels.first
            }
            let newState: SubscriptionViewState = .loaded(subscriptionLevels: subscriptionLevels,
                                                          selectedCurrencyCode: selectedCurrencyCode,
                                                          selectedSubscriptionLevel: selectedSubscriptionLevel,
                                                          currentSubscription: currentSubscription)

            return Guarantee.value(newState)
        }.recover { (error: Error) -> Guarantee<SubscriptionViewState> in
            Logger.warn("\(error)")
            return Guarantee.value(SubscriptionViewState.loadFailed)
        }
    }

    // MARK: - Rendering

    func updateTableContents() {
        let contents = OWSTableContents()
        defer {
            self.contents = contents
        }

        let section = OWSTableSection()
        section.hasBackground = false
        contents.addSection(section)

        section.customHeaderView = {
            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.layoutMargins = UIEdgeInsets(top: 0, left: 19, bottom: 20, right: 19)
            stackView.isLayoutMarginsRelativeArrangement = true

            stackView.addArrangedSubview(avatarView)
            stackView.setCustomSpacing(16, after: avatarView)

            // Title text
            let titleLabel = UILabel()
            titleLabel.textAlignment = .center
            titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
            titleLabel.text = NSLocalizedString(
                "SUSTAINER_VIEW_TITLE",
                comment: "Title for the signal sustainer view"
            )
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(20, after: titleLabel)

            switch state {
            case .initializing, .loading, .loadFailed:
                break
            case .loaded:
                descriptionTextView.attributedText = .composed(of: [NSLocalizedString("SUSTAINER_VIEW_WHY_DONATE_BODY", comment: "The body text for the signal sustainer view"), " ", NSLocalizedString("SUSTAINER_VIEW_READ_MORE", comment: "Read More tappable text in sustainer view body").styled(with: .link(SupportConstants.subscriptionFAQURL))]).styled(with: .color(Theme.primaryTextColor), .font(.ows_dynamicTypeBody))
                descriptionTextView.textAlignment = .center

                descriptionTextView.linkTextAttributes = [
                    .foregroundColor: Theme.accentBlueColor,
                    .underlineColor: UIColor.clear,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]

                descriptionTextView.delegate = self
                stackView.addArrangedSubview(descriptionTextView)
            }

            return stackView
        }()

        // Update avatar view
        updateAvatarView()
        applePayButton = nil

        // Footer setup
        bottomFooterStackView.axis = .vertical
        bottomFooterStackView.alignment = .center
        bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor
        bottomFooterStackView.layoutMargins = UIEdgeInsets(top: 10, leading: 23, bottom: 10, trailing: 23)
        bottomFooterStackView.spacing = 16
        bottomFooterStackView.isLayoutMarginsRelativeArrangement = true
        bottomFooterStackView.removeAllSubviews()

        let shouldHideBottomFooter: Bool
        switch state {
        case .initializing, .loading, .loadFailed:
            shouldHideBottomFooter = true
            // TODO: We should show a different state if the loading failed.
            buildTableForLoadingState(contents: contents, section: section)
        case let .loaded(subscriptionLevels, selectedCurrencyCode, selectedSubscriptionLevel, currentSubscription):
            shouldHideBottomFooter = false
            buildTableForLoadedState(contents: contents,
                                     section: section,
                                     subscriptionLevels: subscriptionLevels,
                                     selectedCurrencyCode: selectedCurrencyCode,
                                     selectedSubscriptionLevel: selectedSubscriptionLevel,
                                     currentSubscription: currentSubscription)
        }

        UIView.performWithoutAnimation {
            self.shouldHideBottomFooter = shouldHideBottomFooter
        }
    }

    private func updateAvatarView() {
        guard case let .loaded(_, _, selectedSubscriptionLevel, currentSubscription) = state else {
            return
        }

        let useExistingBadge = currentSubscription != nil
        if useExistingBadge {
            databaseStorage.read { readTx in
                self.avatarView.update(readTx) { config in
                    if let address = tsAccountManager.localAddress(with: readTx) {
                        config.dataSource = .address(address)
                        config.addBadgeIfApplicable = true
                    }
                }
            }
        } else {
            guard let selectedSubscriptionLevel = selectedSubscriptionLevel else {
                owsFailDebug("No subscription level selected, which is unexpected")
                return
            }

            databaseStorage.read { readTx in
                if self.avatarImage == nil {
                    self.avatarImage = Self.avatarBuilder.avatarImageForLocalUser(diameterPoints: self.sizeClass.diameter,
                                                                                  localUserDisplayMode: .asUser,
                                                                                  transaction: readTx)
                }

                let assets = selectedSubscriptionLevel.badge.assets
                let avatarBadge = assets.flatMap { sizeClass.fetchImageFromBadgeAssets($0) }

                self.avatarView.update(readTx) { config in
                    config.dataSource = .asset(avatar: avatarImage, badge: avatarBadge)
                    config.addBadgeIfApplicable = true
                }

            }

        }

    }

    private func buildTableForLoadingState(contents: OWSTableContents, section: OWSTableSection) {
        section.add(AppSettingsViewsUtil.loadingTableItem(cellOuterInsets: cellOuterInsets))
    }

    private func buildTableForLoadedState(contents: OWSTableContents,
                                          section: OWSTableSection,
                                          subscriptionLevels: [SubscriptionLevel],
                                          selectedCurrencyCode: Currency.Code,
                                          selectedSubscriptionLevel: SubscriptionLevel?,
                                          currentSubscription: Subscription?) {
        if DonationUtilities.isApplePayAvailable {
            buildTableForCreateOrUpdateSubscriptionState(contents: contents,
                                                         section: section,
                                                         subscriptionLevels: subscriptionLevels,
                                                         selectedCurrencyCode: selectedCurrencyCode,
                                                         selectedSubscriptionLevel: selectedSubscriptionLevel,
                                                         currentSubscription: currentSubscription)
        } else {
            buildTableForCancelOnlySubscriptionState(contents: contents,
                                                     section: section,
                                                     subscriptionLevels: subscriptionLevels,
                                                     currentSubscription: currentSubscription)
        }
    }

    /// Get the currency codes that are supported by all the subscription levels.
    private static func supportedCurrencyCodes(subscriptionLevels: [SubscriptionLevel]) -> Set<Currency.Code> {
        guard let firstLevel = subscriptionLevels.first else { return Set() }
        return subscriptionLevels.reduce(Set(firstLevel.currency.keys)) { (result, level) in
            result.intersection(level.currency.keys)
        }
    }

    private func buildTableForCreateOrUpdateSubscriptionState(contents: OWSTableContents,
                                                              section: OWSTableSection,
                                                              subscriptionLevels: [SubscriptionLevel],
                                                              selectedCurrencyCode: Currency.Code,
                                                              selectedSubscriptionLevel: SubscriptionLevel?,
                                                              currentSubscription: Subscription?) {
        guard case let .loaded(subscriptions, selectedCurrencyCode, _, _) = state else {
            return
        }

        if currentSubscription == nil {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

                    let currencyPickerButton = DonationCurrencyPickerButton(currentCurrencyCode: selectedCurrencyCode) { [weak self] in
                        guard let self = self else { return }

                        let vc = CurrencyPickerViewController(
                            dataSource: StripeCurrencyPickerDataSource(currentCurrencyCode: selectedCurrencyCode,
                                                                       supportedCurrencyCodes: Self.supportedCurrencyCodes(subscriptionLevels: subscriptionLevels))
                        ) { [weak self] currencyCode in
                            guard let self = self else { return }
                            self.state.selectCurrencyCode(currencyCode)
                            self.updateTableContents()
                        }
                        self.navigationController?.pushViewController(vc, animated: true)
                    }
                    cell.contentView.addSubview(currencyPickerButton)
                    currencyPickerButton.autoPinEdgesToSuperviewEdges(withInsets: UIEdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))

                    return cell
                },
                actionBlock: {}
            ))
        }

        buildSubscriptionLevelCells(section: section,
                                    subscriptionLevels: subscriptions,
                                    selectedCurrencyCode: selectedCurrencyCode,
                                    selectedSubscriptionLevel: selectedSubscriptionLevel,
                                    currentSubscription: currentSubscription)

        let applePayButton = ApplePayButton { [weak self] in
            self?.requestApplePayDonation()
        }
        self.applePayButton = applePayButton
        applePayButton.isEnabled = state.isApplePayButtonEnabled

        bottomFooterStackView.addArrangedSubview(applePayButton)
        applePayButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        applePayButton.autoPinWidthToSuperview(withMargin: 23)

        if currentSubscription != nil {
            bottomFooterStackView.addArrangedSubview(createCancelButton())
        }
    }

    private func buildTableForCancelOnlySubscriptionState(contents: OWSTableContents,
                                                          section: OWSTableSection,
                                                          subscriptionLevels: [SubscriptionLevel],
                                                          currentSubscription: Subscription?) {
        guard let currentSubscription = currentSubscription else {
            owsFailDebug("You shouldn't be able to enter this view with NO subscription and Apple Pay disabled")
            return
        }

        let subscriptionLevel = DonationViewsUtil.subscriptionLevelForSubscription(subscriptionLevels: subscriptionLevels, subscription: currentSubscription)
        let subscriptionRedemptionFailureReason = DonationViewsUtil.getSubscriptionRedemptionFailureReason(subscription: currentSubscription)
        section.add(DonationViewsUtil.getMySupportCurrentSubscriptionTableItem(subscriptionLevel: subscriptionLevel,
                currentSubscription: currentSubscription,
                subscriptionRedemptionFailureReason: subscriptionRedemptionFailureReason,
                statusLabelToModify: statusLabel))

        bottomFooterStackView.addArrangedSubview(createCancelButton())
    }

    private func buildSubscriptionLevelCells(section: OWSTableSection,
                                             subscriptionLevels: [SubscriptionLevel],
                                             selectedCurrencyCode: Currency.Code,
                                             selectedSubscriptionLevel: SubscriptionLevel?,
                                             currentSubscription: Subscription?) {
        subscriptionLevelCells.removeAll()
        for (index, subscription) in subscriptionLevels.enumerated() {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newSubscriptionCell()
                    cell.subscriptionID = subscription.level

                    let stackView = UIStackView()
                    stackView.axis = .horizontal
                    stackView.alignment = .center
                    stackView.layoutMargins = UIEdgeInsets(top: index == 0 ? 16 : 28, leading: 34, bottom: 16, trailing: 34)
                    stackView.isLayoutMarginsRelativeArrangement = true
                    stackView.spacing = 10
                    cell.contentView.addSubview(stackView)
                    stackView.autoPinEdgesToSuperviewEdges()

                    let isSelected = selectedSubscriptionLevel?.level == subscription.level

                    // Background view
                    let background = UIView()
                    background.backgroundColor = self.cellBackgroundColor
                    background.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth
                    background.layer.borderColor = isSelected ? Theme.accentBlueColor.cgColor : DonationViewsUtil.bubbleBorderColor.cgColor
                    background.layer.cornerRadius = 12
                    stackView.addSubview(background)
                    cell.cellBackgroundView = background
                    background.autoPinEdgesToSuperviewEdges(withInsets: UIEdgeInsets(top: index == 0 ? 0 : 12, leading: 24, bottom: 0, trailing: 24))

                    let badge = subscription.badge
                    let imageView = UIImageView()
                    imageView.setContentHuggingHigh()
                    if let badgeImage = badge.assets?.universal160 {
                        imageView.image = badgeImage
                    }
                    stackView.addArrangedSubview(imageView)
                    imageView.autoSetDimensions(to: CGSize(square: 64))
                    cell.badgeImageView = imageView

                    let textStackView = UIStackView()
                    textStackView.axis = .vertical
                    textStackView.alignment = .leading
                    textStackView.spacing = 4

                    let titleStackView = UIStackView()
                    titleStackView.axis = .horizontal
                    titleStackView.distribution = .fill
                    titleStackView.spacing = 4

                    let localizedBadgeName = subscription.name
                    let titleLabel = UILabel()
                    titleLabel.text = localizedBadgeName
                    titleLabel.font = .ows_dynamicTypeBody.ows_semibold
                    titleLabel.numberOfLines = 0
                    titleLabel.setContentHuggingHorizontalHigh()
                    titleLabel.setCompressionResistanceHorizontalHigh()
                    titleStackView.addArrangedSubview(titleLabel)

                    let isCurrent = currentSubscription?.level == subscription.level
                    if isCurrent {
                        titleStackView.addArrangedSubview(.hStretchingSpacer())
                        let checkmark = UIImageView(image: UIImage(named: "check-20")?.withRenderingMode(.alwaysTemplate))
                        checkmark.tintColor = Theme.primaryTextColor
                        titleStackView.addArrangedSubview(checkmark)
                        checkmark.setContentHuggingHorizontalLow()
                        checkmark.setCompressionResistanceHorizontalHigh()
                    }

                    let descriptionLabel = UILabel()
                    let descriptionFormat = NSLocalizedString("SUSTAINER_VIEW_BADGE_DESCRIPTION", comment: "Description text for sustainer view badges, embeds {{localized badge name}}")
                    descriptionLabel.text = String(format: descriptionFormat, subscription.badge.localizedName)
                    descriptionLabel.font = .ows_dynamicTypeBody2
                    descriptionLabel.numberOfLines = 0

                    let pricingLabel = UILabel()

                    let currencyCode: Currency.Code = currentSubscription?.currency ?? selectedCurrencyCode
                    if let price = subscription.currency[currencyCode] {
                        let pricingFormat = NSLocalizedString("SUSTAINER_VIEW_PRICING", comment: "Pricing text for sustainer view badges, embeds {{price}}")
                        let currencyString = DonationUtilities.formatCurrency(price, currencyCode: currencyCode)
                        pricingLabel.numberOfLines = 0

                        if !isCurrent {
                            pricingLabel.text = String(format: pricingFormat, currencyString)
                            pricingLabel.font = .ows_dynamicTypeBody2
                        } else {
                            if let currentSubscription = currentSubscription {
                                let pricingString = String(format: pricingFormat, currencyString)

                                let renewalFormat = currentSubscription.cancelAtEndOfPeriod ? NSLocalizedString("SUSTAINER_VIEW_PRICING_EXPIRATION", comment: "Renewal text for sustainer view management badges, embeds {{Expiration}}") : NSLocalizedString("SUSTAINER_VIEW_PRICING_RENEWAL", comment: "Expiration text for sustainer view management badges, embeds {{Expiration}}")
                                let renewalDate = Date(timeIntervalSince1970: currentSubscription.endOfCurrentPeriod)
                                let renewalString = String(format: renewalFormat, self.dateFormatter.string(from: renewalDate))

                                let attributedString = NSMutableAttributedString(string: pricingString + renewalString)
                                attributedString.addAttributesToEntireString([.font: UIFont.ows_dynamicTypeBody2, .foregroundColor: Theme.primaryTextColor])
                                attributedString.addAttributes([.foregroundColor: UIColor.ows_gray45], range: NSRange(location: pricingString.utf16.count, length: renewalString.utf16.count))
                                pricingLabel.attributedText = attributedString
                            }
                        }
                    }

                    textStackView.addArrangedSubviews([titleStackView, descriptionLabel, pricingLabel])
                    stackView.addArrangedSubview(textStackView)

                    self.subscriptionLevelCells.append(cell)
                    return cell
                },
                actionBlock: {
                    self.updateLevelSelectionState(for: subscription)
                }
            ))
        }
    }

    private func createCancelButton() -> OWSButton {
        let cancelButtonString = NSLocalizedString("SUSTAINER_VIEW_CANCEL_SUBSCRIPTION", comment: "Sustainer view Cancel Subscription button title")
        let cancelButton = OWSButton(title: cancelButtonString) { [weak self] in
            guard let self = self else { return }
            let title = NSLocalizedString("SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_TITLE", comment: "Confirm Cancellation? Action sheet title")
            let message = NSLocalizedString("SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_MESSAGE", comment: "Confirm Cancellation? Action sheet message")
            let confirm = NSLocalizedString("SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_CONFIRM", comment: "Confirm Cancellation? Action sheet confirm button")
            let notNow = NSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW", comment: "Sustainer view Not Now Action sheet button")
            let actionSheet = ActionSheetController(title: title, message: message)
            actionSheet.addAction(ActionSheetAction(
                    title: confirm,
                    style: .default,
                    handler: { [weak self] _ in
                        self?.cancelSubscription()
                    }
            ))

            actionSheet.addAction(ActionSheetAction(
                    title: notNow,
                    style: .cancel,
                    handler: nil
            ))
            self.presentActionSheet(actionSheet)
        }
        cancelButton.setTitleColor(Theme.accentBlueColor, for: .normal)
        cancelButton.dimsWhenHighlighted = true
        return cancelButton
    }

    // MARK: - Actions

    private func updateLevelSelectionState(for subscription: SubscriptionLevel) {
        state.selectSubscriptionLevel(subscription)

        updateAvatarView()
        self.applePayButton?.isEnabled = state.isApplePayButtonEnabled

        var subscriptionCell: SubscriptionLevelCell?
        var index: Int?
        for (idx, cell) in subscriptionLevelCells.enumerated() {
            if cell.subscriptionID == subscription.level {
                subscriptionCell = cell
                index = idx
                cell.toggleSelectedOutline(true)
            } else {
                cell.toggleSelectedOutline(false)
            }
        }

        let animationNames = [
            "boost_fire",
            "boost_shock",
            "boost_rockets"
        ]

        guard let subscriptionCell = subscriptionCell, let index = index, let imageView = subscriptionCell.badgeImageView else {
            return owsFailDebug("Unable to add animation to cell")
        }

        guard let selectedAnimation = animationNames[safe: index] else {
            return owsFailDebug("Missing animation for preset")
        }

        let animationView = AnimationView(name: selectedAnimation)
        animationView.isUserInteractionEnabled = false
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .forceFinish
        self.view.addSubview(animationView)
        animationView.autoPinEdge(.bottom, to: .top, of: imageView, withOffset: 40)
        animationView.autoPinEdge(.leading, to: .leading, of: imageView)
        animationView.autoMatch(.width, to: .width, of: imageView)
        animationView.play { _ in
            animationView.removeFromSuperview()
        }
    }

    private func cancelSubscription() {
        guard let persistedSubscriberID = persistedSubscriberID else {
            owsFailDebug("Asked to cancel subscription but no persisted subscriberID")
            return
        }
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            firstly {
                SubscriptionManager.cancelSubscription(for: persistedSubscriberID)
            }.done(on: .main) {
                modal.dismiss {
                    if let navController = self.navigationController {
                        self.view.presentToast(
                            text: NSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CANCELLED", comment: "Toast indicating that the subscription has been cancelled"), fromViewController: navController)
                        navController.popViewController(animated: true)
                    }
                }
            }.catch { error in
                modal.dismiss {}
                owsFailDebug("Failed to cancel subscription \(error)")
            }
        }

    }

    private func newSubscriptionCell() -> SubscriptionLevelCell {
        let cell = SubscriptionLevelCell()
        OWSTableItem.configureCell(cell)
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        cell.selectionStyle = .none
        return cell
    }

    func presentBadgeCantBeAddedSheet() {
        let currentSubscription: Subscription?
        switch state {
        case .initializing, .loading, .loadFailed:
            currentSubscription = nil
        case let .loaded(_, _, _, subscription):
            currentSubscription = subscription
        }

        DonationViewsUtil.presentBadgeCantBeAddedSheet(viewController: self,
                                                       currentSubscription: currentSubscription)
    }

    func presentStillProcessingSheet() {
        let title = NSLocalizedString("SUSTAINER_STILL_PROCESSING_BADGE_TITLE", comment: "Action sheet title for Still Processing Badge sheet")
        let message = NSLocalizedString("SUSTAINER_VIEW_STILL_PROCESSING_BADGE_MESSAGE", comment: "Action sheet message for Still Processing Badge sheet")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(OWSActionSheets.okayAction)
        self.navigationController?.topViewController?.presentActionSheet(actionSheet)
    }

    func presentReadMoreSheet() {
        let readMoreSheet = SubscriptionReadMoreSheet()
        self.present(readMoreSheet, animated: true)
    }
}

extension SubscriptionViewController: PKPaymentAuthorizationControllerDelegate {

    @objc
    fileprivate func requestApplePayDonation() {
        guard case let .loaded(_, selectedCurrencyCode, selectedSubscription, currentSubscription) = state else {
            owsFailDebug("Not loaded, can't invoke Apple Pay donation")
            return
        }

        guard let subscription = selectedSubscription else {
            owsFailDebug("No selected subscription, can't invoke Apple Pay donation")
            return
        }

        guard let subscriptionAmount = subscription.currency[selectedCurrencyCode] else {
            owsFailDebug("Failed to get amount for current currency code")
            return
        }

        if currentSubscription == nil {
            presentApplePay(for: subscriptionAmount, currencyCode: selectedCurrencyCode)
        } else {
            var currencyString: String = ""
            if let selectedSubscription = selectedSubscription, let price = selectedSubscription.currency[selectedCurrencyCode] {
                currencyString = DonationUtilities.formatCurrency(price, currencyCode: selectedCurrencyCode)
            }

            let title = NSLocalizedString("SUSTAINER_VIEW_UPDATE_SUBSCRIPTION_CONFIRMATION_TITLE", comment: "Update Subscription? Action sheet title")
            let message = String(format: NSLocalizedString("SUSTAINER_VIEW_UPDATE_SUBSCRIPTION_CONFIRMATION_MESSAGE", comment: "Update Subscription? Action sheet message, embeds {{Price}}"), currencyString)
            let confirm = NSLocalizedString("SUSTAINER_VIEW_UPDATE_SUBSCRIPTION_CONFIRMATION_UPDATE", comment: "Update Subscription? Action sheet confirm button")
            let notNow = NSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW", comment: "Sustainer view Not Now Action sheet button")
            let actionSheet = ActionSheetController(title: title, message: message)
            actionSheet.addAction(ActionSheetAction(
                title: confirm,
                style: .default,
                handler: { [weak self] _ in
                    self?.presentApplePay(for: subscriptionAmount, currencyCode: selectedCurrencyCode)
                }
            ))

            actionSheet.addAction(ActionSheetAction(
                title: notNow,
                style: .cancel,
                handler: nil
            ))
            self.presentActionSheet(actionSheet)
        }

    }

    private func presentApplePay(for amount: NSDecimalNumber, currencyCode: String) {
        guard case let .loaded(_, _, selectedSubscriptionLevel, _) = state else {
            owsFailDebug("Not loaded, can't invoke Apple Pay donation")
            return
        }

        guard let subscription = selectedSubscriptionLevel else {
            owsFailDebug("No selected subscription, can't invoke Apple Pay donation")
            return
        }

        guard let subscriptionAmount = subscription.currency[currencyCode] else {
            owsFailDebug("Failed to get amount for current currency code")
            return
        }

        guard !Stripe.isAmountTooSmall(subscriptionAmount, in: currencyCode) else {
            owsFailDebug("Subscription amount is too small per Stripe API")
            return
        }

        guard !Stripe.isAmountTooLarge(subscriptionAmount, in: currencyCode) else {
            owsFailDebug("Subscription amount is too large per Stripe API")
            return
        }

        let request = DonationUtilities.newPaymentRequest(
            for: subscriptionAmount,
            currencyCode: currencyCode,
            isRecurring: true
        )

        let paymentController = PKPaymentAuthorizationController(paymentRequest: request)
        paymentController.delegate = self
        SubscriptionManager.terminateTransactionIfPossible = false
        paymentController.present { presented in
            if !presented { owsFailDebug("Failed to present payment controller") }
        }
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard case let .loaded(subscriptionLevels, selectedCurrencyCode, selectedSubscriptionLevel, currentSubscription) = state else {
            return
        }

        guard let selectedSubscription = selectedSubscriptionLevel else {
            owsFailDebug("No currently selected subscription")
            let authResult = PKPaymentAuthorizationResult(status: .failure, errors: nil)
            completion(authResult)
            return
        }

        if let currentSubscription = currentSubscription,
           let priorSubscriptionLevel = DonationViewsUtil.subscriptionLevelForSubscription(subscriptionLevels: subscriptionLevels, subscription: currentSubscription),
           let subscriberID = self.persistedSubscriberID {
            firstly {
                return try SubscriptionManager.updateSubscriptionLevel(for: subscriberID,
                                                                       from: priorSubscriptionLevel,
                                                                       to: selectedSubscription,
                                                                       payment: payment,
                                                                       currencyCode: selectedCurrencyCode)
            }.done(on: .main) {
                let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                self.fetchAndRedeemReceipts(newSubscriptionLevel: selectedSubscription)
            }.catch { error in
                let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                owsFailDebug("Error setting up subscription, \(error)")
            }

        } else {
            firstly {
                return try SubscriptionManager.setupNewSubscription(subscription: selectedSubscription, payment: payment, currencyCode: selectedCurrencyCode)
            }.done(on: .main) {
                let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                self.fetchAndRedeemReceipts(newSubscriptionLevel: selectedSubscription)
            }.catch { error in
                let authResult = PKPaymentAuthorizationResult(status: .failure, errors: [error])
                completion(authResult)
                SubscriptionManager.terminateTransactionIfPossible = false
                owsFailDebug("Error setting up subscription, \(error)")
            }
        }

    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        SubscriptionManager.terminateTransactionIfPossible = true
        controller.dismiss()
    }

    func fetchAndRedeemReceipts(newSubscriptionLevel: SubscriptionLevel, priorSubscriptionLevel: SubscriptionLevel? = nil) {
        guard let subscriberID = databaseStorage.read(
            block: { SubscriptionManager.getSubscriberID(transaction: $0) }
        ) else {
            return owsFailDebug("Did not fetch subscriberID")
        }

        do {
            try SubscriptionManager.requestAndRedeemReceiptsIfNecessary(for: subscriberID,
                                                                        subscriptionLevel: newSubscriptionLevel.level,
                                                                        priorSubscriptionLevel: priorSubscriptionLevel?.level ?? 0)
        } catch {
            owsFailDebug("Failed to redeem receipts \(error)")
        }

        let backdropView = UIView()
        backdropView.backgroundColor = Theme.backdropColor
        backdropView.alpha = 0
        view.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        let progressViewContainer = UIView()
        progressViewContainer.backgroundColor = Theme.backgroundColor
        progressViewContainer.layer.cornerRadius = 12
        backdropView.addSubview(progressViewContainer)
        progressViewContainer.autoCenterInSuperview()

        let progressView = AnimatedProgressView(loadingText: NSLocalizedString("SUSTAINER_VIEW_PROCESSING_PAYMENT", comment: "Loading indicator on the sustainer view"))
        view.addSubview(progressView)
        progressView.autoCenterInSuperview()
        progressViewContainer.autoMatch(.width, to: .width, of: progressView, withOffset: 32)
        progressViewContainer.autoMatch(.height, to: .height, of: progressView, withOffset: 32)

        progressView.startAnimating {
            backdropView.alpha = 1
        }

        enum SubscriptionError: Error { case timeout, assertion }

        Promise.race(
            NotificationCenter.default.observe(
                once: SubscriptionManager.SubscriptionJobQueueDidFinishJobNotification,
                object: nil
            ),
            NotificationCenter.default.observe(
                once: SubscriptionManager.SubscriptionJobQueueDidFailJobNotification,
                object: nil
            )
        ).timeout(seconds: 30) {
            return SubscriptionError.timeout
        }.done { notification in
            if notification.name == SubscriptionManager.SubscriptionJobQueueDidFailJobNotification {
                throw SubscriptionError.assertion
            }

            self.ignoreProfileBadgeStateForNewBadgeRedemption = true

            progressView.stopAnimating(success: true) {
                backdropView.alpha = 0
            } completion: {
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()

                self.navigationController?.popViewController(animated: true)

                // We can't use a sneaky transaction here, because the
                // subscription's existence means that the experience
                // upgrade is no longer "active" and won't be found
                // in the unsnoozed list.
                self.databaseStorage.write { transaction in
                    ExperienceUpgradeManager.snoozeExperienceUpgrade(
                        .subscriptionMegaphone,
                        transaction: transaction.unwrapGrdbWrite
                    )
                }

                self.navigationController?.topViewController?.present(BadgeThanksSheet(badge: newSubscriptionLevel.badge, type: .subscription), animated: true)
            }
        }.catch { error in
            progressView.stopAnimating(success: false) {
                backdropView.alpha = 0
            } completion: {
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()

                self.navigationController?.popViewController(animated: true)

                guard let error = error as? SubscriptionError else {
                    return owsFailDebug("Unexpected error \(error)")
                }

                switch error {
                case .timeout:
                    self.presentStillProcessingSheet()
                case .assertion:
                    self.presentBadgeCantBeAddedSheet()
                }
            }
        }
    }
}

extension SubscriptionViewController: UITextViewDelegate {

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if textView == statusLabel {
            presentBadgeCantBeAddedSheet()
        } else if textView == descriptionTextView {
            presentReadMoreSheet()
        }
        return false
    }
}

private class SubscriptionLevelCell: UITableViewCell {
    var subscriptionID: UInt = 0
    var badgeImageView: UIImageView?
    var cellBackgroundView: UIView?

    public func toggleSelectedOutline(_ selected: Bool) {
        if let background = cellBackgroundView {
            background.layer.borderColor = selected ? Theme.accentBlueColor.cgColor : DonationViewsUtil.bubbleBorderColor.cgColor
        }
    }
}
