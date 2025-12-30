//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class BadgeGiftingChooseBadgeViewController: OWSTableViewController2 {
    typealias GiftConfiguration = DonationSubscriptionConfiguration.GiftConfiguration
    typealias PaymentMethodsConfiguration = DonationSubscriptionConfiguration.PaymentMethodsConfiguration

    // MARK: - State management

    enum State {
        case initializing
        case loading
        case loadFailed
        case loaded(
            selectedCurrencyCode: Currency.Code,
            giftConfiguration: GiftConfiguration,
            paymentMethodsConfiguration: PaymentMethodsConfiguration,
        )

        var canContinue: Bool {
            switch self {
            case .initializing, .loading, .loadFailed:
                return false
            case let .loaded(selectedCurrencyCode, giftConfiguration, _):
                let isValid = giftConfiguration.presetAmount[selectedCurrencyCode] != nil
                owsAssertDebug(isValid, "State was loaded but it was invalid")
                return isValid
            }
        }

        func selectCurrencyCode(_ newCurrencyCode: Currency.Code) -> State {
            switch self {
            case .initializing, .loading, .loadFailed:
                assertionFailure("Invalid state; cannot select currency code")
                return self
            case let .loaded(_, giftConfiguration, paymentMethodsConfiguration):
                guard giftConfiguration.presetAmount[newCurrencyCode] != nil else {
                    assertionFailure("Tried to select a currency code that doesn't exist")
                    return self
                }
                return .loaded(
                    selectedCurrencyCode: newCurrencyCode,
                    giftConfiguration: giftConfiguration,
                    paymentMethodsConfiguration: paymentMethodsConfiguration,
                )
            }
        }
    }

    private var state: State = .initializing {
        didSet {
            updateTableContents()
            updateBottomFooter()
        }
    }

    private func loadDataIfNecessary() {
        switch state {
        case .initializing, .loadFailed:
            state = .loading
            Task { @MainActor in
                self.state = await loadData()
            }
        case .loading, .loaded:
            break
        }
    }

    private func loadData() async -> State {
        do {
            Logger.info("[Gifting] Fetching donation configuration...")
            let donationConfiguration = try await DonationSubscriptionManager.fetchDonationConfiguration()
            Logger.info("[Gifting] Populating badge assets...")
            let giftBadge = donationConfiguration.gift.badge
            try await SSKEnvironment.shared.profileManagerRef.badgeStore.populateAssetsOnBadge(giftBadge)
            let defaultCurrencyCode = DonationUtilities.chooseDefaultCurrency(
                preferred: [
                    Locale.current.currencyCode?.uppercased(),
                    "USD",
                    donationConfiguration.gift.presetAmount.keys.first,
                ],
                supported: donationConfiguration.gift.presetAmount.keys,
            )
            guard let defaultCurrencyCode else {
                // This indicates a bug, either in the iOS app or the server.
                owsFailBeta("[Gifting] Successfully loaded data, but a preferred currency could not be found")
                return .loadFailed
            }

            return .loaded(
                selectedCurrencyCode: defaultCurrencyCode,
                giftConfiguration: donationConfiguration.gift,
                paymentMethodsConfiguration: donationConfiguration.paymentMethods,
            )
        } catch {
            Logger.warn("\(error)")
            return .loadFailed
        }
    }

    private func didTapNext() {
        switch state {
        case .initializing, .loading, .loadFailed:
            owsFailBeta("Tapped next when the state wasn't loaded")
        case let .loaded(selectedCurrencyCode, giftConfiguration, paymentMethodsConfiguration):
            guard let price = giftConfiguration.presetAmount[selectedCurrencyCode] else {
                owsFailBeta("State is invalid. We selected a currency code that we don't have a price for")
                return
            }
            let vc = BadgeGiftingChooseRecipientViewController(
                badge: giftConfiguration.badge,
                price: price,
                paymentMethodsConfiguration: paymentMethodsConfiguration,
            )
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    // MARK: - Callbacks

    override public func viewDidLoad() {
        super.viewDidLoad()

        let isPresentedStandalone = navigationController?.viewControllers.first == self
        if isPresentedStandalone {
            navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        }

        loadDataIfNecessary()
        updateTableContents()
        updateBottomFooter()
    }

    // MARK: - Table contents

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: getTableSections())
    }

    private func getTableSections() -> [OWSTableSection] {
        let introSection: OWSTableSection = {
            let section = OWSTableSection()
            section.hasBackground = false
            section.customHeaderView = {
                let imageView = UIImageView(image: UIImage(named: "badge-gifting-promo-image"))
                imageView.contentMode = .scaleAspectFit
                let imageViewContainer = UIView.container()
                imageViewContainer.addSubview(imageView)
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageViewContainer.addConstraints([
                    imageView.topAnchor.constraint(equalTo: imageViewContainer.topAnchor),
                    imageView.leadingAnchor.constraint(greaterThanOrEqualTo: imageViewContainer.leadingAnchor),
                    imageView.centerXAnchor.constraint(equalTo: imageViewContainer.centerXAnchor),
                    imageView.bottomAnchor.constraint(equalTo: imageViewContainer.bottomAnchor),
                ])

                let titleLabel = UILabel.title2Label(text: OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_CHOOSE_BADGE_TITLE",
                    comment: "Users can donate on behalf of a friend, and the friend will receive a badge. This is the title on the screen where users choose the badge their friend will receive.",
                ))
                titleLabel.setCompressionResistanceVerticalHigh()
                let subtitleLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_CHOOSE_BADGE_DESCRIPTION",
                    comment: "Users can donate on behalf of a friend, and the friend will receive a badge. This is a short paragraph on the screen where users choose the badge their friend will receive.",
                ))
                subtitleLabel.setCompressionResistanceVerticalHigh()

                let introStack = UIStackView(arrangedSubviews: [
                    imageViewContainer,
                    titleLabel,
                    subtitleLabel,
                ])
                introStack.axis = .vertical
                introStack.spacing = 12

                return introStack
            }()
            return section
        }()

        var result: [OWSTableSection] = [introSection]

        switch state {
        case .initializing, .loading:
            result += loadingSections()
        case .loadFailed:
            result += loadFailedSections()
        case let .loaded(selectedCurrencyCode, giftConfiguration, _):
            result += loadedSections(
                selectedCurrencyCode: selectedCurrencyCode,
                badge: giftConfiguration.badge,
                pricesByCurrencyCode: giftConfiguration.presetAmount,
            )
        }

        return result
    }

    private func loadingSections() -> [OWSTableSection] {
        let section = OWSTableSection()
        section.add(AppSettingsViewsUtil.loadingTableItem())
        section.hasBackground = false
        return [section]
    }

    private func loadFailedSections() -> [OWSTableSection] {
        let section = OWSTableSection()
        section.add(.init(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell()

            let textLabel = UILabel()
            textLabel.text = OWSLocalizedString(
                "DONATION_VIEW_LOAD_FAILED",
                comment: "Text that's shown when the donation view fails to load data, probably due to network failure",
            )
            textLabel.font = .dynamicTypeSubheadline
            textLabel.textAlignment = .center
            textLabel.textColor = .Signal.label
            textLabel.numberOfLines = 0

            let retryButton = UIButton(
                configuration: .mediumSecondary(title: CommonStrings.retryButton),
                primaryAction: UIAction { [weak self] _ in
                    self?.loadDataIfNecessary()
                },
            )
            // Container is needed to center button instead of stretching it horizontally.
            let retryButtonContainer = retryButton.enclosedInVerticalStackView(isFullWidthButton: false)
            retryButtonContainer.directionalLayoutMargins.bottom = 0

            let stackView = UIStackView(arrangedSubviews: [
                textLabel,
                retryButtonContainer,
            ])
            stackView.axis = .vertical
            stackView.spacing = 16
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        }))
        return [section]
    }

    private func loadedSections(
        selectedCurrencyCode: Currency.Code,
        badge: ProfileBadge,
        pricesByCurrencyCode: [Currency.Code: FiatMoney],
    ) -> [OWSTableSection] {
        let currencyButtonSection = OWSTableSection()
        currencyButtonSection.hasBackground = false
        currencyButtonSection.add(.init(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell()

            let currencyPickerButton = DonationCurrencyPickerButton(
                currentCurrencyCode: selectedCurrencyCode,
                hasLabel: true,
            ) { [weak self] in
                guard let self else { return }
                let vc = CurrencyPickerViewController(
                    dataSource: StripeCurrencyPickerDataSource(
                        currentCurrencyCode: selectedCurrencyCode,
                        supportedCurrencyCodes: Set(pricesByCurrencyCode.keys),
                    ),
                ) { [weak self] currencyCode in
                    guard let self else { return }
                    self.state = self.state.selectCurrencyCode(currencyCode)
                }
                self.navigationController?.pushViewController(vc, animated: true)
            }

            cell.contentView.addSubview(currencyPickerButton)
            currencyPickerButton.translatesAutoresizingMaskIntoConstraints = false
            cell.addConstraints([
                // Cell might be a little too tall - center button vertically.
                currencyPickerButton.topAnchor.constraint(greaterThanOrEqualTo: cell.contentView.topAnchor),
                currencyPickerButton.leadingAnchor.constraint(greaterThanOrEqualTo: cell.contentView.leadingAnchor),
                currencyPickerButton.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                currencyPickerButton.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            ])

            return cell
        }))

        let badgeSection = OWSTableSection()
        badgeSection.add(.init(customCellBlock: {
            let cell = AppSettingsViewsUtil.newCell()

            guard let price = pricesByCurrencyCode[selectedCurrencyCode] else {
                owsFailBeta("State is invalid. We selected a currency code that we don't have a price for.")
                return cell
            }
            let badgeCellView = GiftBadgeCellView(badge: badge, price: price)
            cell.contentView.addSubview(badgeCellView)
            badgeCellView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        return [currencyButtonSection, badgeSection]
    }

    // MARK: - Footer contents

    override open var bottomFooter: UIView? {
        get { bottomFooterContainer }
        set {}
    }

    private lazy var nextButton = UIButton(
        configuration: .largePrimary(title: CommonStrings.nextButton),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapNext()
        },
    )

    private lazy var bottomFooterContainer: UIView = {
        let stackView = UIStackView.verticalButtonStack(buttons: [nextButton])
        let containerView = UIView()
        containerView.preservesSuperviewLayoutMargins = true
        containerView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        return containerView
    }()

    private func updateBottomFooter() {
        nextButton.isEnabled = state.canContinue
    }
}
