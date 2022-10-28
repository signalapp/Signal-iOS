//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging

public class BadgeGiftingChooseBadgeViewController: OWSTableViewController2 {
    // MARK: - State management

    enum State {
        case initializing
        case loading
        case loadFailed
        case loaded(
            selectedCurrencyCode: Currency.Code,
            badge: ProfileBadge,
            pricesByCurrencyCode: [Currency.Code: FiatMoney]
        )

        public var canContinue: Bool {
            switch self {
            case .initializing, .loading, .loadFailed:
                return false
            case let .loaded(selectedCurrencyCode, _, pricesByCurrencyCode):
                let isValid = pricesByCurrencyCode[selectedCurrencyCode] != nil
                owsAssertDebug(isValid, "State was loaded but it was invalid")
                return isValid
            }
        }

        public func selectCurrencyCode(_ newCurrencyCode: Currency.Code) -> State {
            switch self {
            case .initializing, .loading, .loadFailed:
                assertionFailure("Invalid state; cannot select currency code")
                return self
            case let .loaded(_, badge, pricesByCurrencyCode):
                guard pricesByCurrencyCode[newCurrencyCode] != nil else {
                    assertionFailure("Tried to select a currency code that doesn't exist")
                    return self
                }
                return .loaded(selectedCurrencyCode: newCurrencyCode,
                               badge: badge,
                               pricesByCurrencyCode: pricesByCurrencyCode)
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
            loadData().done { self.state = $0 }
        case .loading, .loaded:
            break
        }
    }

    private func loadData() -> Guarantee<State> {
        firstly { () -> Promise<(ProfileBadge, [Currency.Code: FiatMoney])> in
            Logger.info("[Gifting] Fetching badge data...")
            return Promise.when(fulfilled: SubscriptionManager.getGiftBadge(), SubscriptionManager.getGiftBadgePricesByCurrencyCode())
        }.then { (giftBadge: ProfileBadge, pricesByCurrencyCode: [Currency.Code: FiatMoney]) -> Promise<(ProfileBadge, [Currency.Code: FiatMoney])> in
            Logger.info("[Gifting] Populating badge assets...")
            return self.profileManager.badgeStore.populateAssetsOnBadge(giftBadge).map { (giftBadge, pricesByCurrencyCode) }
        }.then { (giftBadge: ProfileBadge, pricesByCurrencyCode: [Currency.Code: FiatMoney]) -> Guarantee<State> in
            let selectedCurrencyCode: Currency.Code
            if pricesByCurrencyCode[Stripe.defaultCurrencyCode] != nil {
                selectedCurrencyCode = Stripe.defaultCurrencyCode
            } else if pricesByCurrencyCode["USD"] != nil {
                Logger.warn("Could not find the desired currency code. Falling back to USD")
                selectedCurrencyCode = "USD"
            } else {
                owsFail("Could not pick a currency, even USD")
            }

            return Guarantee.value(.loaded(
                selectedCurrencyCode: selectedCurrencyCode,
                badge: giftBadge,
                pricesByCurrencyCode: pricesByCurrencyCode
            ))
        }.recover { error -> Guarantee<State> in
            Logger.warn("\(error)")
            return Guarantee.value(.loadFailed)
        }
    }

    private func didTapNext() {
        switch state {
        case .initializing, .loading, .loadFailed:
            owsFailDebug("Tapped next when the state wasn't loaded")
        case let .loaded(selectedCurrencyCode, badge, pricesByCurrencyCode):
            guard let price = pricesByCurrencyCode[selectedCurrencyCode] else {
                owsFailDebug("State is invalid. We selected a currency code that we don't have a price for")
                return
            }
            let vc = BadgeGiftingChooseRecipientViewController(badge: badge, price: price)
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    // MARK: - Callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()
        loadDataIfNecessary()
        updateTableContents()
        setUpBottomFooter()
    }

    public override func themeDidChange() {
        super.themeDidChange()
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
                let introStack = UIStackView()
                introStack.axis = .vertical
                introStack.spacing = 12

                let imageName = Theme.isDarkThemeEnabled ? "badge-gifting-promo-image-dark" : "badge-gifting-promo-image-light"
                let imageView = UIImageView(image: UIImage(named: imageName))
                introStack.addArrangedSubview(imageView)
                imageView.contentMode = .scaleAspectFit

                let titleLabel = UILabel()
                introStack.addArrangedSubview(titleLabel)
                titleLabel.text = NSLocalizedString("BADGE_GIFTING_CHOOSE_BADGE_TITLE",
                                                    comment: "Title on the screen where you choose a gift badge")
                titleLabel.textAlignment = .center
                titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
                titleLabel.numberOfLines = 0
                titleLabel.lineBreakMode = .byWordWrapping
                titleLabel.autoPinWidthToSuperview(withMargin: 26)

                let paragraphLabel = UILabel()
                introStack.addArrangedSubview(paragraphLabel)
                paragraphLabel.text = NSLocalizedString("BADGE_GIFTING_CHOOSE_BADGE_DESCRIPTION",
                                                        comment: "Short paragraph on the screen where you choose a gift badge")
                paragraphLabel.textAlignment = .center
                paragraphLabel.font = UIFont.ows_dynamicTypeBody
                paragraphLabel.numberOfLines = 0
                paragraphLabel.lineBreakMode = .byWordWrapping
                paragraphLabel.autoPinWidthToSuperview(withMargin: 26)

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
        case let .loaded(selectedCurrencyCode, badge, pricesByCurrencyCode):
            result += loadedSections(selectedCurrencyCode: selectedCurrencyCode, badge: badge, pricesByCurrencyCode: pricesByCurrencyCode)
        }

        return result
    }

    private func loadingSections() -> [OWSTableSection] {
        let section = OWSTableSection()
        section.add(AppSettingsViewsUtil.loadingTableItem(cellOuterInsets: cellOuterInsets))
        section.hasBackground = false
        return [section]
    }

    private func loadFailedSections() -> [OWSTableSection] {
        let section = OWSTableSection()
        section.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.spacing = 16

            let textLabel = UILabel()
            stackView.addArrangedSubview(textLabel)
            textLabel.text = NSLocalizedString("DONATION_VIEW_LOAD_FAILED",
                                               comment: "Text that's shown when the donation view fails to load data, probably due to network failure")
            textLabel.font = .ows_dynamicTypeBody2
            textLabel.textAlignment = .center
            textLabel.textColor = Theme.primaryTextColor
            textLabel.numberOfLines = 0

            let retryButton = OWSButton { [weak self] in self?.loadDataIfNecessary() }
            stackView.addArrangedSubview(retryButton)
            retryButton.setTitle(CommonStrings.retryButton, for: .normal)
            if Theme.isDarkThemeEnabled {
                retryButton.setTitleColor(.ows_gray05, for: .normal)
                retryButton.setBackgroundImage(UIImage.init(color: .ows_gray85), for: .normal)
            } else {
                retryButton.setTitleColor(.ows_gray90, for: .normal)
                retryButton.setBackgroundImage(UIImage.init(color: .ows_gray05), for: .normal)
            }
            retryButton.contentEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 6)
            retryButton.autoPinWidthToSuperviewMargins(relation: .lessThanOrEqual)
            retryButton.autoHCenterInSuperview()
            retryButton.setContentHuggingHigh()
            retryButton.layer.cornerRadius = 16
            retryButton.clipsToBounds = true

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        }))
        return [section]
    }

    private func loadedSections(
        selectedCurrencyCode: Currency.Code,
        badge: ProfileBadge,
        pricesByCurrencyCode: [Currency.Code: FiatMoney]
    ) -> [OWSTableSection] {
        let currencyButtonSection = OWSTableSection()
        currencyButtonSection.hasBackground = false
        currencyButtonSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let currencyPickerButton = DonationCurrencyPickerButton(currentCurrencyCode: selectedCurrencyCode) { [weak self] in
                guard let self = self else { return }
                let vc = CurrencyPickerViewController(
                    dataSource: StripeCurrencyPickerDataSource(currentCurrencyCode: selectedCurrencyCode,
                                                               supportedCurrencyCodes: Set(pricesByCurrencyCode.keys))
                ) { [weak self] currencyCode in
                    guard let self = self else { return }
                    self.state = self.state.selectCurrencyCode(currencyCode)
                }
                self.navigationController?.pushViewController(vc, animated: true)
            }

            cell.contentView.addSubview(currencyPickerButton)
            currencyPickerButton.autoPinEdgesToSuperviewEdges(withInsets: UIEdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))

            return cell
        }))

        let badgeSection = OWSTableSection()
        badgeSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            guard let price = pricesByCurrencyCode[selectedCurrencyCode] else {
                owsFailDebug("State is invalid. We selected a currency code that we don't have a price for.")
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

    open override var bottomFooter: UIView? {
        get { bottomFooterStackView }
        set {}
    }
    private let nextButton = OWSButton()
    private let bottomFooterStackView = UIStackView()

    private func setUpBottomFooter() {
        bottomFooterStackView.axis = .vertical
        bottomFooterStackView.alignment = .center
        bottomFooterStackView.layoutMargins = UIEdgeInsets(top: 10, leading: 23, bottom: 10, trailing: 23)
        bottomFooterStackView.spacing = 16
        bottomFooterStackView.isLayoutMarginsRelativeArrangement = true

        bottomFooterStackView.addArrangedSubview(nextButton)
        nextButton.block = { [weak self] in
            self?.didTapNext()
        }
        nextButton.setTitle(CommonStrings.nextButton, for: .normal)
        nextButton.dimsWhenHighlighted = true
        nextButton.layer.cornerRadius = 8
        nextButton.backgroundColor = .ows_accentBlue
        nextButton.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
        nextButton.autoSetDimension(.height, toSize: 48)
        nextButton.autoPinWidthToSuperviewMargins()

        updateBottomFooter()
    }

    private func updateBottomFooter() {
        bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor

        nextButton.isEnabled = state.canContinue
        nextButton.backgroundColor = .ows_accentBlue
        if !nextButton.isEnabled {
            nextButton.backgroundColor = nextButton.backgroundColor?.withAlphaComponent(0.5)
        }
    }
}
