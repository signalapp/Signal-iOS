//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

    private enum SubscriptionViewState {
        case loading
        case subscriptionNotYetSetUp
        case subscriptionExists
        case subscriptionUpdating
    }

    private var subscriptionViewState: SubscriptionViewState {
        if updatingSubscriptions == true {
            return .subscriptionUpdating
        } else if fetchedSubscriptionStatus == false || subscriptions == nil {
            return .loading
        } else {
            guard let currentSubscription = currentSubscription else {
                return .subscriptionNotYetSetUp
            }

            if !ignoreProfileBadgeStateForNewBadgeRedemption && profileSubscriptionBadges.isEmpty {
                return .subscriptionNotYetSetUp
            }

            if currentSubscription.active {
                return .subscriptionExists
            } else {
                return (subscriptionRedemptionFailureReason == .none) ? .subscriptionExists : .subscriptionNotYetSetUp
            }
        }
    }

    private var subscriptions: [SubscriptionLevel]? {
        didSet {
            if let newSubscriptions = subscriptions, selectedSubscription == nil {
                selectedSubscription = newSubscriptions.first ?? nil
            }
            updateTableContents()
        }
    }

    private var currentSubscription: Subscription?

    private lazy var profileSubscriptionBadges: [OWSUserProfileBadgeInfo] = {
        return SubscriptionManager.currentProfileSubscriptionBadges()
    }()

    private var selectedSubscription: SubscriptionLevel?

    private var fetchedSubscriptionStatus = false {
        didSet {
            if fetchedSubscriptionStatus {
                showBadgeExpirySheetIfNeeded()
            }
        }
    }

    private var ignoreProfileBadgeStateForNewBadgeRedemption = false
    private var updatingSubscriptions = false
    private var persistedSubscriberID: Data?
    private var persistedSubscriberCurrencyCode: String?

    private var currencyCode = Stripe.defaultCurrencyCode {
        didSet {
            guard oldValue != currencyCode else { return }
            updateTableContents()
        }
    }

    private let sizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight

    private lazy var avatarView: ConversationAvatarView = {
        let newAvatarView = ConversationAvatarView(sizeClass: sizeClass, localUserDisplayMode: .asUser)
        return newAvatarView
    }()

    private var avatarImage: UIImage?

    private var paymentButton: PKPaymentButton?

    private lazy var redemptionLoadingSpinner: AnimationView = {
        let loadingAnimationView = AnimationView(name: "indeterminate_spinner_blue")
        loadingAnimationView.loopMode = .loop
        loadingAnimationView.contentMode = .scaleAspectFit
        loadingAnimationView.play()
        return loadingAnimationView
    }()

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

    private var subscriptionRedemptionFailureReason: SubscriptionRedemptionFailureReason {
        var failureReason: SubscriptionRedemptionFailureReason = .none

        if let currentSubscription = currentSubscription {
            if currentSubscription.status == .incomplete || currentSubscription.status == .incompleteExpired {
                return .paymentFailed
            }
        }

        SDSDatabaseStorage.shared.read { transaction in
            failureReason = SubscriptionManager.lastReceiptRedemptionFailed(transaction: transaction)
        }
        return failureReason
    }

    private let bottomFooterStackView = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomFooterStackView }
        set {}
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        return formatter
    }()

    static let bubbleBorderWidth: CGFloat = 1.5
    static var bubbleBorderColor: UIColor { Theme.isDarkThemeEnabled ? UIColor.ows_gray65 : UIColor(rgbHex: 0xdedede) }
    static var bubbleBackgroundColor: UIColor { Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white }
    private static let subscriptionBannerAvatarSize: UInt = 88

    public init(updatingSubscriptionsState: Bool, subscriptions: [SubscriptionLevel]?, currentSubscription: Subscription?, subscriberID: Data?, subscriberCurrencyCode: String?) {
        updatingSubscriptions = updatingSubscriptionsState
        self.subscriptions = subscriptions
        self.currentSubscription = currentSubscription
        if let currentSubscription = currentSubscription, let subscriptions = subscriptions {
            fetchedSubscriptionStatus = true
            for subscription in subscriptions {
                if subscription.level == currentSubscription.level {
                    self.selectedSubscription = subscription
                }
            }
        }

        self.persistedSubscriberID = subscriberID
        self.persistedSubscriberCurrencyCode = subscriberCurrencyCode
        super.init()
    }

    public convenience override init() {
        self.init(updatingSubscriptionsState: false, subscriptions: nil, currentSubscription: nil, subscriberID: nil, subscriberCurrencyCode: nil)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        if subscriptions == nil {
            // Fetch available subscriptions
            firstly {
                SubscriptionManager.getSubscriptions()
            }.done(on: .main) { (fetchedSubscriptions: [SubscriptionLevel]) in
                self.subscriptions = fetchedSubscriptions
                Logger.debug("successfully fetched subscriptions")

                let badgeUpdatePromises = fetchedSubscriptions.map { return self.profileManager.badgeStore.populateAssetsOnBadge($0.badge) }
                firstly {
                    return Promise.when(fulfilled: badgeUpdatePromises)
                }.done(on: .main) {
                    self.updateTableContents()
                }.catch { error in
                    owsFailDebug("Failed to fetch assets for badge \(error)")
                }

            }.catch(on: .main) { error in
                owsFailDebug("Failed to fetch subscriptions \(error)")
            }
        }

        fetchCurrentSubscription()
        updateTableContents()
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
        fetchCurrentSubscription()

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

    @objc
    func subscriptionRedemptionJobStateDidChange(notification: NSNotification) {
        updateTableContents()
    }

    func fetchCurrentSubscription() {
        // Fetch current subscription state
        var subscriberID: Data?
        var currencyCode: String?
        SDSDatabaseStorage.shared.read { transaction in
            subscriberID = SubscriptionManager.getSubscriberID(transaction: transaction)
            currencyCode = SubscriptionManager.getSubscriberCurrencyCode(transaction: transaction)
        }

        if let subscriberID = subscriberID, let currencyCode = currencyCode {
            self.persistedSubscriberID = subscriberID
            self.persistedSubscriberCurrencyCode = currencyCode
            firstly {
                SubscriptionManager.getCurrentSubscriptionStatus(for: subscriberID)
            }.done(on: .main) { subscription in
                self.fetchedSubscriptionStatus = true
                self.currentSubscription = subscription
                self.updateTableContents()
                self.avatarView.reloadDataIfNecessary()
            }.catch { error in
                owsFailDebug("Failed to fetch subscription \(error)")
            }
        } else {
            self.currentSubscription = nil
            if self.fetchedSubscriptionStatus {
                // Dispatch to next run loop to avoid reentrant db calls
                DispatchQueue.main.async {
                    self.updateTableContents()
                }
            } else {
                self.fetchedSubscriptionStatus = true
            }
        }
    }

    func showBadgeExpirySheetIfNeeded() {
        guard subscriptionViewState == .subscriptionNotYetSetUp, let subscriptions = subscriptions else {
            return
        }

        let expiredBadgeID = SubscriptionManager.mostRecentlyExpiredBadgeIDWithSneakyTransaction()
        guard let expiredBadgeID = expiredBadgeID, SubscriptionBadgeIds.contains(expiredBadgeID) else {
            return
        }

        let subscriptionLevel = subscriptions.first { $0.badge.id == expiredBadgeID }

        guard let subscriptionLevel = subscriptionLevel else {
            owsFailDebug("Unable to find current subscription level for expired badge")
            return
        }

        selectedSubscription = subscriptionLevel
        updateTableContents()

        let sheet = BadgeExpirationSheet(badge: subscriptionLevel.badge)
        sheet.delegate = self
        self.present(sheet, animated: true)
    }

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

            if subscriptionViewState == .subscriptionNotYetSetUp || subscriptionViewState == .subscriptionUpdating {
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
        paymentButton = nil

        // Footer setup
        bottomFooterStackView.axis = .vertical
        bottomFooterStackView.alignment = .center
        bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor
        bottomFooterStackView.layoutMargins = UIEdgeInsets(top: 10, leading: 23, bottom: 10, trailing: 23)
        bottomFooterStackView.spacing = 16
        bottomFooterStackView.isLayoutMarginsRelativeArrangement = true
        bottomFooterStackView.removeAllSubviews()

        switch subscriptionViewState {
        case .loading:
            buildTableForPendingState(contents: contents, section: section)
        case .subscriptionNotYetSetUp:
            buildTableForPendingSubscriptionState(contents: contents, section: section)
        case .subscriptionExists:
            buildTableForExistingSubscriptionState(contents: contents, section: section)
        case .subscriptionUpdating:
            buildTableForUpdatingSubscriptionState(contents: contents, section: section)
        }

        UIView.performWithoutAnimation {
            self.shouldHideBottomFooter = !(self.subscriptionViewState == .subscriptionNotYetSetUp || self.subscriptionViewState == .subscriptionUpdating)
        }
    }

    private func updateAvatarView() {

        let useExistingBadge = subscriptionViewState == .subscriptionExists || self.selectedSubscription == nil
        let shouldAddBadge = subscriptionViewState != .loading
        if useExistingBadge {
            databaseStorage.read { readTx in
                self.avatarView.update(readTx) { config in
                    if let address = tsAccountManager.localAddress(with: readTx) {
                        config.dataSource = .address(address)
                        config.addBadgeIfApplicable = shouldAddBadge
                    }
                }
            }
        } else {
            databaseStorage.read { readTx in
                if self.avatarImage == nil {
                    self.avatarImage = Self.avatarBuilder.avatarImageForLocalUser(diameterPoints: self.sizeClass.avatarDiameter,
                                                                                  localUserDisplayMode: .asUser,
                                                                                  transaction: readTx)
                }

                var avatarBadge: UIImage?
                if let selectedSubscription = self.selectedSubscription {
                    let assets = selectedSubscription.badge.assets
                    avatarBadge = assets.flatMap { sizeClass.fetchImageFromBadgeAssets($0) }
                }

                self.avatarView.update(readTx) { config in
                    config.dataSource = .asset(avatar: avatarImage, badge: avatarBadge)
                    config.addBadgeIfApplicable = shouldAddBadge
                }

            }

        }

    }

    private func buildTableForPendingSubscriptionState(contents: OWSTableContents, section: OWSTableSection) {

        if DonationUtilities.isApplePayAvailable {

            if let subscriptions = self.subscriptions {
                section.add(.init(
                    customCellBlock: { [weak self] in
                        guard let self = self else { return UITableViewCell() }
                        let cell = self.newCell()

                        let stackView = UIStackView()
                        stackView.axis = .horizontal
                        stackView.alignment = .center
                        stackView.spacing = 8
                        stackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0)
                        stackView.isLayoutMarginsRelativeArrangement = true
                        cell.contentView.addSubview(stackView)
                        stackView.autoPinEdgesToSuperviewEdges()

                        let label = UILabel()
                        label.font = .ows_dynamicTypeBodyClamped
                        label.textColor = Theme.primaryTextColor
                        label.text = NSLocalizedString(
                            "SUSTAINER_VIEW_CURRENCY",
                            comment: "Set currency label in sustainer view"
                        )
                        stackView.addArrangedSubview(label)

                        let picker = OWSButton { [weak self] in
                            guard let self = self else { return }
                            let vc = CurrencyPickerViewController(
                                dataSource: StripeCurrencyPickerDataSource(currentCurrencyCode: self.currencyCode)
                            ) { [weak self] currencyCode in
                                self?.currencyCode = currencyCode
                            }
                            self.navigationController?.pushViewController(vc, animated: true)
                        }

                        picker.setAttributedTitle(NSAttributedString.composed(of: [
                            self.currencyCode,
                            Special.noBreakSpace,
                            NSAttributedString.with(
                                image: #imageLiteral(resourceName: "chevron-down-18").withRenderingMode(.alwaysTemplate),
                                font: .ows_regularFont(withSize: 17)
                            ).styled(
                                with: .color(Self.bubbleBorderColor)
                            )
                        ]).styled(
                            with: .font(.ows_regularFont(withSize: 17)),
                            .color(Theme.primaryTextColor)
                        ), for: .normal)

                        picker.setBackgroundImage(UIImage(color: Self.bubbleBackgroundColor), for: .normal)
                        picker.setBackgroundImage(UIImage(color: Self.bubbleBackgroundColor.withAlphaComponent(0.8)), for: .highlighted)

                        let pillView = PillView()
                        pillView.layer.borderWidth = Self.bubbleBorderWidth
                        pillView.layer.borderColor = Self.bubbleBorderColor.cgColor
                        pillView.clipsToBounds = true
                        pillView.addSubview(picker)
                        picker.autoPinEdgesToSuperviewEdges()
                        picker.autoSetDimension(.width, toSize: 74, relation: .greaterThanOrEqual)

                        stackView.addArrangedSubview(pillView)
                        pillView.autoSetDimension(.height, toSize: 36, relation: .greaterThanOrEqual)

                        let leadingSpacer = UIView.hStretchingSpacer()
                        let trailingSpacer = UIView.hStretchingSpacer()
                        stackView.insertArrangedSubview(leadingSpacer, at: 0)
                        stackView.addArrangedSubview(trailingSpacer)
                        leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)

                        return cell
                    },
                    actionBlock: {}
                ))

                buildSubscriptionLevelCells(subscriptions: subscriptions, section: section)

            }

            let applePayContributeButton = newPaymentButton()
            self.paymentButton = applePayContributeButton
            bottomFooterStackView.addArrangedSubview(applePayContributeButton)
            applePayContributeButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
            applePayContributeButton.autoPinWidthToSuperview(withMargin: 23)
        }
    }

    private func buildTableForExistingSubscriptionState(contents: OWSTableContents, section: OWSTableSection) {

        let subscriptionPending = subscriptionRedemptionPending
        let subscriptionFailed = subscriptionRedemptionFailureReason != .none

        // My Support header
        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()

                let titleLabel = UILabel()
                titleLabel.text = NSLocalizedString("SUSTAINER_VIEW_MY_SUPPORT", comment: "Existing subscriber support header")
                titleLabel.font = .ows_dynamicTypeBody.ows_semibold
                titleLabel.numberOfLines = 0
                cell.contentView.addSubview(titleLabel)
                titleLabel.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 0, leading: 24, bottom: 14, trailing: 24))
                return cell
            },
            actionBlock: {}
        ))

        // Current support level
        let subscriptionLevel = subscriptionLevelForSubscription(currentSubscription)
        if let subscriptionLevel = subscriptionLevel, let currentSubscription = currentSubscription {
            section.add(.init(
                customCellBlock: { [weak self] in
                    guard let self = self else { return UITableViewCell() }
                    let cell = self.newCell()

                    let containerStackView = UIStackView()
                    containerStackView.axis = .vertical
                    containerStackView.alignment = .center
                    containerStackView.layoutMargins = UIEdgeInsets(top: 16, leading: 30, bottom: 16, trailing: 30)
                    containerStackView.isLayoutMarginsRelativeArrangement = true
                    containerStackView.spacing = 16

                    cell.contentView.addSubview(containerStackView)
                    containerStackView.autoPinEdgesToSuperviewEdges()

                    // Background view
                    let background = UIView()
                    background.backgroundColor = self.cellBackgroundColor
                    background.layer.cornerRadius = 12
                    containerStackView.addSubview(background)
                    background.autoPinEdgesToSuperviewEdges(withInsets: UIEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                    let stackView = UIStackView()
                    stackView.axis = .horizontal
                    stackView.alignment = .center
                    stackView.spacing = 10
                    containerStackView.addArrangedSubview(stackView)
                    stackView.autoPinWidthToSuperviewMargins()

                    let imageView = UIImageView()
                    imageView.setContentHuggingHigh()

                    if let badgeImage = subscriptionLevel.badge.assets?.universal160 {
                        imageView.image = badgeImage
                    }

                    stackView.addArrangedSubview(imageView)
                    imageView.autoSetDimensions(to: CGSize(square: 64))

                    if subscriptionPending {
                        stackView.addSubview(self.redemptionLoadingSpinner)
                        self.redemptionLoadingSpinner.autoPin(toEdgesOf: imageView, withInset: UIEdgeInsets(hMargin: 14, vMargin: 14))
                        let progress = self.redemptionLoadingSpinner.currentProgress
                        self.redemptionLoadingSpinner.play(fromProgress: progress, toProgress: 1)
                    } else {
                        self.redemptionLoadingSpinner.removeFromSuperview()
                    }

                    imageView.alpha = subscriptionPending || subscriptionFailed ? 0.5 : 1

                    let textStackView = UIStackView()
                    textStackView.axis = .vertical
                    textStackView.alignment = .leading
                    textStackView.spacing = 4

                    let localizedBadgeName = subscriptionLevel.name
                    let titleLabel = UILabel()
                    titleLabel.text = localizedBadgeName
                    titleLabel.font = .ows_dynamicTypeBody.ows_semibold
                    titleLabel.numberOfLines = 0

                    let pricingLabel = UILabel()
                    let pricingFormat = NSLocalizedString("SUSTAINER_VIEW_PRICING", comment: "Pricing text for sustainer view badges, embeds {{price}}")
                    var amount = currentSubscription.amount
                    if !Stripe.zeroDecimalCurrencyCodes.contains(currentSubscription.currency) {
                        amount = amount.dividing(by: NSDecimalNumber(value: 100))
                    }

                    let currencyString = DonationUtilities.formatCurrency(amount, currencyCode: currentSubscription.currency)
                    pricingLabel.text = String(format: pricingFormat, currencyString)
                    pricingLabel.font = .ows_dynamicTypeBody2
                    pricingLabel.numberOfLines = 0

                    var statusText: NSMutableAttributedString?
                    if subscriptionPending {
                        let text = NSLocalizedString("SUSTAINER_VIEW_PROCESSING_TRANSACTION", comment: "Status text while processing a badge redemption")
                        statusText = NSMutableAttributedString(string: text, attributes: [.foregroundColor: Theme.secondaryTextAndIconColor, .font: UIFont.ows_dynamicTypeBody2])
                    } else if subscriptionFailed {
                        let helpFormat = self.subscriptionRedemptionFailureReason == .paymentFailed ? NSLocalizedString("SUSTAINER_VIEW_PAYMENT_ERROR", comment: "Payment error occured text, embeds {{link to contact support}}")
                        : NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE", comment: "Couldn't add badge text, embeds {{link to contact support}}")
                        let contactSupport = NSLocalizedString("SUSTAINER_VIEW_CONTACT_SUPPORT", comment: "Contact support link")
                        let text = String(format: helpFormat, contactSupport)
                        let attributedText = NSMutableAttributedString(string: text, attributes: [.foregroundColor: Theme.secondaryTextAndIconColor, .font: UIFont.ows_dynamicTypeBody2])
                        attributedText.addAttributes([.link: NSURL()], range: NSRange(location: text.utf16.count - contactSupport.utf16.count, length: contactSupport.utf16.count))
                        statusText = attributedText
                    } else {
                        let renewalFormat = NSLocalizedString("SUSTAINER_VIEW_RENEWAL", comment: "Renewal date text for sustainer view level, embeds {{renewal date}}")
                        let renewalDate = Date(timeIntervalSince1970: currentSubscription.endOfCurrentPeriod)
                        let renewalString = self.dateFormatter.string(from: renewalDate)
                        let text = String(format: renewalFormat, renewalString)
                        statusText = NSMutableAttributedString(string: text, attributes: [.foregroundColor: Theme.secondaryTextAndIconColor, .font: UIFont.ows_dynamicTypeBody2])
                    }

                    self.statusLabel.attributedText = statusText
                    self.statusLabel.linkTextAttributes = [
                        .foregroundColor: Theme.accentBlueColor,
                        .underlineColor: UIColor.clear,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]

                    self.statusLabel.delegate = self

                    textStackView.addArrangedSubviews([titleLabel, pricingLabel, self.statusLabel])
                    stackView.addArrangedSubview(textStackView)

                    let addBoostString = NSLocalizedString("SUSTAINER_VIEW_ADD_BOOST", comment: "Sustainer view Add Boost button title")
                    let addBoostButton = OWSButton(title: addBoostString) { [weak self] in
                        guard let self = self else { return }
                        self.present(BoostSheetView(), animated: true)
                    }
                    addBoostButton.dimsWhenHighlighted = true
                    addBoostButton.layer.cornerRadius = 8
                    addBoostButton.backgroundColor = .ows_accentBlue
                    containerStackView.addArrangedSubview(addBoostButton)
                    addBoostButton.autoSetDimension(.height, toSize: 48)
                    addBoostButton.autoPinWidthToSuperview(withMargin: 34)

                    if subscriptionPending {
                        addBoostButton.isHighlighted = true
                        addBoostButton.isUserInteractionEnabled = false
                    }

                    return cell
                },
                actionBlock: {}
            ))
        }

        // Management disclosure
        let managementSection = OWSTableSection()
        contents.addSection(managementSection)

        if subscriptionPending {
            managementSection.add(.item(icon: .settingsManage,
                                        tintColor: .ows_gray40,
                                        name: NSLocalizedString("SUBSCRIBER_MANAGE_SUBSCRIPTION", comment: "Title for the 'Manage Subscription' button in sustainer view."),
                                        maxNameLines: 0,
                                        textColor: .ows_gray40,
                                        accessoryText: nil,
                                        accessoryType: .none,
                                        accessoryImage: nil,
                                        accessoryView: nil,
                                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "manageSubscription"),
                                        actionBlock: nil))

            managementSection.add(.item(icon: .settingsBadges,
                                        tintColor: .ows_gray40,
                                        name: NSLocalizedString("SUBSCRIBER_BADGES", comment: "Title for the 'Badges' button in sustainer view."),
                                        maxNameLines: 0,
                                        textColor: .ows_gray40,
                                        accessoryText: nil,
                                        accessoryType: .none,
                                        accessoryImage: nil,
                                        accessoryView: nil,
                                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "badges"),
                                        actionBlock: nil))
        } else {
            managementSection.add(.disclosureItem(
                icon: .settingsManage,
                name: NSLocalizedString("SUBSCRIBER_MANAGE_SUBSCRIPTION", comment: "Title for the 'Manage Subscription' button in sustainer view."),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "manageSubscription"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    if let subscriptions = self.subscriptions, let currentSubscription = self.currentSubscription, let persistedSubscriberID = self.persistedSubscriberID, let persistedSubscriberCurrencyCode = self.persistedSubscriberCurrencyCode {
                        let managementController = SubscriptionViewController(updatingSubscriptionsState: true, subscriptions: subscriptions, currentSubscription: currentSubscription, subscriberID: persistedSubscriberID, subscriberCurrencyCode: persistedSubscriberCurrencyCode)
                        self.navigationController?.pushViewController(managementController, animated: true)
                    }
                }
            ))

            managementSection.add(.disclosureItem(
                icon: .settingsBadges,
                name: NSLocalizedString("SUBSCRIBER_BADGES", comment: "Title for the 'Badges' button in sustainer view."),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "badges"),
                actionBlock: { [weak self] in
                    if let self = self {
                        let vc = BadgeConfigurationViewController(fetchingDataFromLocalProfileWithDelegate: self)
                        self.navigationController?.pushViewController(vc, animated: true)
                    }
                }
            ))
        }

        managementSection.add(.disclosureItem(
            icon: .settingsHelp,
            name: NSLocalizedString("SUBSCRIBER_SUBSCRIPTION_FAQ", comment: "Title for the 'Subscription FAQ' button in sustainer view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "subscriptionFAQ"),
            actionBlock: { [weak self] in
                let vc = SFSafariViewController(url: SupportConstants.subscriptionFAQURL)
                self?.present(vc, animated: true, completion: nil)
            }
        ))

    }

    private func buildTableForPendingState(contents: OWSTableContents, section: OWSTableSection) {
        section.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = self.newCell()
                let stackView = UIStackView()
                stackView.axis = .vertical
                stackView.alignment = .center
                stackView.layoutMargins = UIEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
                stackView.isLayoutMarginsRelativeArrangement = true
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewEdges()

                let activitySpinner: UIActivityIndicatorView
                if #available(iOS 13, *) {
                    activitySpinner = UIActivityIndicatorView(style: .medium)
                } else {
                    activitySpinner = UIActivityIndicatorView(style: .gray)
                }

                activitySpinner.startAnimating()

                stackView.addArrangedSubview(activitySpinner)

                return cell
            },
            actionBlock: {}
        ))
    }

    private func buildTableForUpdatingSubscriptionState(contents: OWSTableContents, section: OWSTableSection) {
        if let subscriptions = subscriptions {
            buildSubscriptionLevelCells(subscriptions: subscriptions, section: section)
        }

        let applePayContributeButton = newPaymentButton()
        self.paymentButton = applePayContributeButton
        bottomFooterStackView.addArrangedSubview(applePayContributeButton)
        applePayContributeButton.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        applePayContributeButton.autoPinWidthToSuperview(withMargin: 23)

        if self.subscriptionRedemptionFailureReason == .none, let currentSubscription = currentSubscription, let selectedSubscription = selectedSubscription {
            let enabled = currentSubscription.level != selectedSubscription.level
            applePayContributeButton.isEnabled = enabled
        }

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
        bottomFooterStackView.addArrangedSubview(cancelButton)

    }

    private func buildSubscriptionLevelCells(subscriptions: [SubscriptionLevel], section: OWSTableSection) {
        subscriptionLevelCells.removeAll()
        for (index, subscription) in subscriptions.enumerated() {
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

                    let isSelected = self.selectedSubscription?.level == subscription.level

                    // Background view
                    let background = UIView()
                    background.backgroundColor = self.cellBackgroundColor
                    background.layer.borderWidth = Self.bubbleBorderWidth
                    background.layer.borderColor = isSelected ? Theme.accentBlueColor.cgColor : Self.bubbleBorderColor.cgColor
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

                    let isUpdating = self.subscriptionViewState == .subscriptionUpdating
                    let isCurrent = isUpdating && self.currentSubscription?.level == subscription.level
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

                    let currencyCode = isUpdating ? self.persistedSubscriberCurrencyCode ?? self.currencyCode : self.currencyCode
                    if let price = subscription.currency[currencyCode] {
                        let pricingFormat = NSLocalizedString("SUSTAINER_VIEW_PRICING", comment: "Pricing text for sustainer view badges, embeds {{price}}")
                        let currencyString = DonationUtilities.formatCurrency(price, currencyCode: currencyCode)
                        pricingLabel.numberOfLines = 0

                        if !isCurrent {
                            pricingLabel.text = String(format: pricingFormat, currencyString)
                            pricingLabel.font = .ows_dynamicTypeBody2
                        } else {
                            if let currentSubscription = self.currentSubscription {
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
                    self.selectedSubscription = subscription
                    self.updateLevelSelectionState(for: subscription)
                    if self.subscriptionViewState == .subscriptionUpdating, self.subscriptionRedemptionFailureReason == .none, let paymentButton = self.paymentButton, let currentSubscription = self.currentSubscription, let selectedSubscription = self.selectedSubscription {
                        let enabled = currentSubscription.level != selectedSubscription.level
                        paymentButton.isEnabled = enabled
                    }
                }
            ))
        }
    }

    private func updateLevelSelectionState(for subscription: SubscriptionLevel) {
        updateAvatarView()

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
                try SubscriptionManager.cancelSubscription(for: persistedSubscriberID)
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

    private func newCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        return cell
    }

    private func newSubscriptionCell() -> SubscriptionLevelCell {
        let cell = SubscriptionLevelCell()
        OWSTableItem.configureCell(cell)
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        cell.selectionStyle = .none
        return cell
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateTableContents()
    }

    func presentBadgeCantBeAddedSheet() {
        let title = subscriptionRedemptionFailureReason == .paymentFailed ? NSLocalizedString("SUSTAINER_VIEW_ERROR_PROCESSING_PAYMENT_TITLE", comment: "Action sheet title for Error Processing Payment sheet") : NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_TITLE", comment: "Action sheet title for Couldn't Add Badge sheet")
        let message = NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_MESSAGE", comment: "Action sheet message for Couldn't Add Badge sheet")

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("CONTACT_SUPPORT", comment: "Button text to initiate an email to signal support staff"),
            style: .default,
            handler: { [weak self] _ in
                let localizedSheetTitle = NSLocalizedString("EMAIL_SIGNAL_TITLE",
                                                            comment: "Title for the fallback support sheet if user cannot send email")
                let localizedSheetMessage = NSLocalizedString("EMAIL_SIGNAL_MESSAGE",
                                                              comment: "Description for the fallback support sheet if user cannot send email")
                guard ComposeSupportEmailOperation.canSendEmails else {
                    let fallbackSheet = ActionSheetController(title: localizedSheetTitle,
                                                              message: localizedSheetMessage)
                    let buttonTitle = NSLocalizedString("BUTTON_OKAY", comment: "Label for the 'okay' button.")
                    fallbackSheet.addAction(ActionSheetAction(title: buttonTitle, style: .default))
                    self?.presentActionSheet(fallbackSheet)
                    return
                }
                let supportVC = ContactSupportViewController()
                supportVC.selectedFilter = .sustainers
                let navVC = OWSNavigationController(rootViewController: supportVC)
                self?.presentFormSheet(navVC, animated: true)
            }
        ))

        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW", comment: "Sustainer view Not Now Action sheet button"),
            style: .cancel,
            handler: nil
        ))
        self.navigationController?.topViewController?.presentActionSheet(actionSheet)
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

    fileprivate func newPaymentButton() -> PKPaymentButton {

        let applePayContributeButton = PKPaymentButton(
            paymentButtonType: .donate,
            paymentButtonStyle: Theme.isDarkThemeEnabled ? .white : .black
        )

        applePayContributeButton.cornerRadius = 12
        applePayContributeButton.addTarget(self, action: #selector(self.requestApplePayDonation), for: .touchUpInside)
        return applePayContributeButton
    }

    @objc
    fileprivate func requestApplePayDonation() {
        guard let subscription = selectedSubscription else {
            owsFailDebug("No selected subscription, can't invoke Apple Pay donation")
            return
        }

        let currencyCode = subscriptionViewState == .subscriptionUpdating ? persistedSubscriberCurrencyCode ?? currencyCode : currencyCode
        guard let subscriptionAmount = subscription.currency[currencyCode] else {
            owsFailDebug("Failed to get amount for current currency code")
            return
        }

        if subscriptionViewState == .subscriptionUpdating {
            var currencyString: String = ""
            if let selectedSubscription = selectedSubscription, let price = selectedSubscription.currency[currencyCode] {
                currencyString = DonationUtilities.formatCurrency(price, currencyCode: currencyCode)
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
                    if let currencyCode = self?.persistedSubscriberCurrencyCode {
                        self?.presentApplePay(for: subscriptionAmount, currencyCode: currencyCode)
                    }
                }
            ))

            actionSheet.addAction(ActionSheetAction(
                title: notNow,
                style: .cancel,
                handler: nil
            ))
            self.presentActionSheet(actionSheet)
        } else {
            presentApplePay(for: subscriptionAmount, currencyCode: currencyCode)
        }

    }

    private func presentApplePay(for amount: NSDecimalNumber, currencyCode: String) {
        guard let subscription = selectedSubscription else {
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

        let request = DonationUtilities.newPaymentRequest(for: subscriptionAmount, currencyCode: currencyCode)

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

        guard let selectedSubscription = self.selectedSubscription else {
            owsFailDebug("No currently selected subscription")
            let authResult = PKPaymentAuthorizationResult(status: .failure, errors: nil)
            completion(authResult)
            return
        }

        if subscriptionViewState == .subscriptionUpdating, let priorSubscriptionLevel = self.subscriptionLevelForSubscription(self.currentSubscription),
           let subscriberID = self.persistedSubscriberID,
           let currencyCode = self.persistedSubscriberCurrencyCode {

            firstly {
                return try SubscriptionManager.updateSubscriptionLevel(for: subscriberID, from: priorSubscriptionLevel, to: selectedSubscription, payment: payment, currencyCode: currencyCode)
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
                return try SubscriptionManager.setupNewSubscription(subscription: selectedSubscription, payment: payment, currencyCode: self.currencyCode)
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
            try SubscriptionManager.requestAndRedeemRecieptsIfNecessary(for: subscriberID,
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

                if self.subscriptionViewState == .subscriptionUpdating {
                    self.navigationController?.popViewController(animated: true)
                } else {
                    self.fetchCurrentSubscription()
                }

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

                // Only show the badge sheet if redemption succeeds.
                if let selectedSubscription = self.selectedSubscription {
                    self.navigationController?.topViewController?.present(BadgeThanksSheet(badge: selectedSubscription.badge), animated: true)
                } else {
                    owsFailDebug("Missing selected subscription after redemption.")
                }
            }
        }.catch { error in
            progressView.stopAnimating(success: false) {
                backdropView.alpha = 0
            } completion: {
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()

                if self.subscriptionViewState == .subscriptionUpdating {
                    self.navigationController?.popViewController(animated: true)
                } else {
                    self.fetchCurrentSubscription()
                }

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

    func subscriptionLevelForSubscription( _ subscription: Subscription?) -> SubscriptionLevel? {
        guard let subscription = subscription else {
            return nil
        }

        guard let subscriptionLevels = subscriptions else {
            return nil
        }

        for subscriptionLevel in subscriptionLevels {
            if subscriptionLevel.level == subscription.level {
                return subscriptionLevel
            }
        }

        return nil
    }

}

extension SubscriptionViewController: BadgeConfigurationDelegate {
    func badgeConfiguration(_ vc: BadgeConfigurationViewController, didCompleteWithBadgeSetting setting: BadgeConfiguration) {
        if !self.reachabilityManager.isReachable {
            OWSActionSheets.showErrorAlert(
                message: NSLocalizedString("PROFILE_VIEW_NO_CONNECTION",
                                           comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."))
            return
        }

        firstly { () -> Promise<Void> in
            let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
            let allBadges = snapshot.profileBadgeInfo ?? []
            let oldVisibleBadges = allBadges.filter { $0.isVisible ?? true }
            let oldVisibleBadgeIds = oldVisibleBadges.map { $0.badgeId }

            let newVisibleBadgeIds: [String]
            switch setting {
            case .doNotDisplayPublicly:
                newVisibleBadgeIds = []
            case .display(featuredBadge: let newFeaturedBadge):
                let allBadgeIds = allBadges.map { $0.badgeId }
                guard allBadgeIds.contains(newFeaturedBadge.badgeId) else {
                    throw OWSAssertionError("Invalid badge")
                }
                newVisibleBadgeIds = [newFeaturedBadge.badgeId] + allBadgeIds.filter { $0 != newFeaturedBadge.badgeId }
            }

            if oldVisibleBadgeIds != newVisibleBadgeIds {
                Logger.info("Updating visible badges from \(oldVisibleBadgeIds) to \(newVisibleBadgeIds)")
                vc.showDismissalActivity = true
                return OWSProfileManager.updateLocalProfilePromise(
                    profileGivenName: snapshot.givenName,
                    profileFamilyName: snapshot.familyName,
                    profileBio: snapshot.bio,
                    profileBioEmoji: snapshot.bioEmoji,
                    profileAvatarData: snapshot.avatarData,
                    visibleBadgeIds: newVisibleBadgeIds,
                    userProfileWriter: .localUser)
            } else {
                return Promise.value(())
            }
        }.then(on: .global()) { () -> Promise<Void> in
            let displayBadgesOnProfile: Bool
            switch setting {
            case .doNotDisplayPublicly:
                displayBadgesOnProfile = false
            case .display:
                displayBadgesOnProfile = true
            }

            return Self.databaseStorage.writePromise { transaction in
                Self.subscriptionManager.setDisplayBadgesOnProfile(
                    displayBadgesOnProfile,
                    updateStorageService: true,
                    transaction: transaction
                )
            }.asVoid()
        }.done {
            self.navigationController?.popViewController(animated: true)
        }.catch { error in
            owsFailDebug("Failed to update profile: \(error)")
            self.navigationController?.popViewController(animated: true)
        }
    }

    func badgeConfirmationDidCancel(_: BadgeConfigurationViewController) {
        self.navigationController?.popViewController(animated: true)
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
            background.layer.borderColor = selected ? Theme.accentBlueColor.cgColor : SubscriptionViewController.bubbleBorderColor.cgColor
        }
    }
}

private class SubscriptionReadMoreSheet: InteractiveSheetViewController {
    let contentScrollView = UIScrollView()
    let stackView = UIStackView()
    let handleContainer = UIView()
    override var interactiveScrollViews: [UIScrollView] { [contentScrollView] }
    override var minHeight: CGFloat { min(740, CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32)) }
    override var maximizedHeight: CGFloat { minHeight }
    override var renderExternalHandle: Bool { false }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()
        contentView.backgroundColor = Theme.tableView2PresentedBackgroundColor

        // We add the handle directly to the content view,
        // so that it doesn't scroll with the table.
        handleContainer.backgroundColor = Theme.tableView2PresentedBackgroundColor
        contentView.addSubview(handleContainer)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.autoPinEdge(toSuperviewEdge: .top)

        let handle = UIView()
        handle.backgroundColor = Theme.tableView2PresentedSeparatorColor
        handle.autoSetDimensions(to: CGSize(width: 36, height: 5))
        handle.layer.cornerRadius = 5 / 2
        handleContainer.addSubview(handle)
        handle.autoPinHeightToSuperview(withMargin: 12)
        handle.autoHCenterInSuperview()

        contentView.addSubview(contentScrollView)

        stackView.axis = .vertical
        stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 24)
        stackView.isLayoutMarginsRelativeArrangement = true
        contentScrollView.addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        stackView.autoPinWidth(toWidthOf: view)

        contentScrollView.autoPinWidthToSuperview()
        contentScrollView.autoPinEdge(toSuperviewEdge: .bottom)
        contentScrollView.autoPinEdge(.top, to: .bottom, of: handleContainer)
        contentScrollView.alwaysBounceVertical = true

        buildContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        handleContainer.backgroundColor = Theme.tableView2PresentedBackgroundColor
        contentView.backgroundColor = Theme.tableView2PresentedBackgroundColor

    }

    private func buildContents() {

        // Header image
        let image = UIImage(named: "sustainer-heart")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(imageView)
        stackView.setCustomSpacing(12, after: imageView)

        // Header label
        let titleLabel = UILabel()
        titleLabel.textAlignment = .natural
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_TITLE",
            comment: "Title for the signal sustainer read more view"
        )
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        let firstDescriptionBlock = UILabel()
        firstDescriptionBlock.textAlignment = .natural
        firstDescriptionBlock.font = .ows_dynamicTypeBody
        firstDescriptionBlock.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_DESCRIPTION_BLOCK_ONE",
            comment: "First block of description text in read more sheet"
        )
        firstDescriptionBlock.numberOfLines = 0
        firstDescriptionBlock.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(firstDescriptionBlock)
        stackView.setCustomSpacing(32, after: firstDescriptionBlock)

        let titleLabel2 = UILabel()
        titleLabel2.textAlignment = .natural
        titleLabel2.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel2.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_WHY_CONTRIBUTE",
            comment: "Why Contribute title for the signal sustainer read more view"
        )
        titleLabel2.numberOfLines = 0
        titleLabel2.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(titleLabel2)
        stackView.setCustomSpacing(12, after: titleLabel2)

        let secondDescriptionBlock = UILabel()
        secondDescriptionBlock.textAlignment = .natural
        secondDescriptionBlock.font = .ows_dynamicTypeBody
        secondDescriptionBlock.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_DESCRIPTION_BLOCK_TWO",
            comment: "Second block of description text in read more sheet"
        )
        secondDescriptionBlock.numberOfLines = 0
        secondDescriptionBlock.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(secondDescriptionBlock)
    }
}

extension SubscriptionViewController: BadgeExpirationSheetDelegate {

    func badgeExpirationSheetActionButtonTapped(_ badgeExpirationSheet: BadgeExpirationSheet) {
        SubscriptionManager.clearMostRecentlyExpiredBadgeIDWithSneakyTransaction()
        requestApplePayDonation()
    }

    func badgeExpirationSheetNotNowButtonTapped(_ badgeExpirationSheet: BadgeExpirationSheet) {
        SubscriptionManager.clearMostRecentlyExpiredBadgeIDWithSneakyTransaction()
    }

}
