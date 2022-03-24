//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class DonationReceiptsViewController: OWSTableViewController2 {
    private class ProfileBadgeLookup {
        let boostBadge: ProfileBadge?
        let badgesBySubscriptionLevel: [UInt: ProfileBadge]

        public init(boostBadge: ProfileBadge?, subscriptionLevels: [SubscriptionLevel]) {
            self.boostBadge = boostBadge

            var badgesBySubscriptionLevel = [UInt: ProfileBadge]()
            for subscriptionLevel in subscriptionLevels {
                badgesBySubscriptionLevel[subscriptionLevel.level] = subscriptionLevel.badge
            }
            self.badgesBySubscriptionLevel = badgesBySubscriptionLevel
        }

        public func get(donationReceipt: DonationReceipt) -> ProfileBadge? {
            if let subscriptionLevel = donationReceipt.subscriptionLevel {
                return badgesBySubscriptionLevel[subscriptionLevel]
            } else {
                return boostBadge
            }
        }

        public func getImage(donationReceipt: DonationReceipt, preferDarkTheme: Bool) -> UIImage? {
            guard let assets = get(donationReceipt: donationReceipt)?.assets else { return nil }
            return preferDarkTheme ? assets.dark16 : assets.light16
        }
    }

    private enum State {
        case loading
        case loaded(donationReceipts: [DonationReceipt], profileBadgeLookup: ProfileBadgeLookup)
    }

    private var state: State = .loading

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("DONATION_RECEIPTS", comment: "Title of view where you can see all of your donation receipts, or button to take you there")

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        updateTableContents()

        loadData()
    }

    override func themeDidChange() {
        updateTableContents()
    }

    // MARK: - Loading data

    private static let loadingQueue = DispatchQueue(label: "DonationReceiptsViewController.loadingQueue", qos: .userInitiated)

    private func loadData() {
        firstly(on: Self.loadingQueue) {
            Self.databaseStorage.read { DonationReceiptFinder.fetchAllInReverseDateOrder(transaction: $0) }
        }.then(on: Self.loadingQueue) { donationReceipts in
            Self.loadProfileBadgeLookup().map { (donationReceipts, $0) }
        }.then(on: Self.loadingQueue) { donationReceipts, profileBadgeLookup -> Guarantee<Void> in
            self.state = .loaded(donationReceipts: donationReceipts, profileBadgeLookup: profileBadgeLookup)
            return Self.populateAssetsOnBadges(donationReceipts: donationReceipts, profileBadgeLookup: profileBadgeLookup)
        }.done(on: .main) {
            self.updateTableContents()
        }.catch { error in
            owsFailDebug("Failed to fetch donation receipts and badges \(error)")
            // This should be rare, so we just leave the view in a loading state.
        }
    }

    private static func loadProfileBadgeLookup() -> Guarantee<ProfileBadgeLookup> {
        let boostBadgePromise: Guarantee<ProfileBadge?> = SubscriptionManager.getBoostBadge()
            .map { Optional.some($0) }
            .recover { error -> Guarantee<ProfileBadge?> in
                Logger.warn("Failed to fetch boost badge \(error). Proceeding without it, as it is only cosmetic here")
                return Guarantee.value(nil)
            }

        let subscriptionLevelsPromise: Guarantee<[SubscriptionLevel]> = SubscriptionManager.getSubscriptions()
            .recover { error -> Guarantee<[SubscriptionLevel]> in
                Logger.warn("Failed to fetch subscription levels \(error). Proceeding without them, as they are only cosmetic here")
                return Guarantee.value([])
            }

        return boostBadgePromise.then { boostBadge in
            subscriptionLevelsPromise.map { subscriptionLevels in
                ProfileBadgeLookup(boostBadge: boostBadge, subscriptionLevels: subscriptionLevels)
            }
        }
    }

    private static func populateAssetsOnBadges(donationReceipts: [DonationReceipt], profileBadgeLookup: ProfileBadgeLookup) -> Guarantee<Void> {
        let promises = donationReceipts
            .compactMap { profileBadgeLookup.get(donationReceipt: $0) }
            .map { self.profileManager.badgeStore.populateAssetsOnBadge($0) }
        return Promise.when(fulfilled: promises).recover { _ in Guarantee.value(()) }
    }

    // MARK: - Top-level render

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        switch state {
        case .loading:
            contents.addSection(loadingSection())
        case let .loaded(donationReceipts, profileBadgeLookup):
            for section in loadedSections(donationReceipts: donationReceipts, profileBadgeLookup: profileBadgeLookup) {
                contents.addSection(section)
            }
        }
    }

    // MARK: - Loading UI

    private func loadingSection() -> OWSTableSection {
        OWSTableSection(items: [AppSettingsViewsUtil.loadingTableItem(cellOuterInsets: cellOuterInsets)])
    }

    // MARK: - List UI

    private func loadedSections(donationReceipts: [DonationReceipt], profileBadgeLookup: ProfileBadgeLookup) -> [OWSTableSection] {
        var result = [OWSTableSection]()

        for donationReceipt in donationReceipts {
            let year = Calendar.current.component(.year, from: donationReceipt.timestamp)
            let yearString = String(year)

            let sectionForThisYear: OWSTableSection
            if let lastSection = result.last, lastSection.headerTitle == yearString {
                sectionForThisYear = lastSection
            } else {
                let newSection = OWSTableSection()
                newSection.headerTitle = yearString
                result.append(newSection)
                sectionForThisYear = newSection
            }

            let profileBadgeImage = profileBadgeLookup.getImage(donationReceipt: donationReceipt, preferDarkTheme: Theme.isDarkThemeEnabled)
            let formattedDate = dateFormatter.string(from: donationReceipt.timestamp)
            let formattedAmount = DonationUtilities.formatCurrency(NSDecimalNumber(decimal: donationReceipt.amount), currencyCode: donationReceipt.currencyCode)

            let tableItem = OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "donation_receipt.\(donationReceipt.uniqueId)")

                    return OWSTableItem.buildImageNameCell(
                        image: profileBadgeImage,
                        itemName: formattedDate,
                        subtitle: donationReceipt.localizedName,
                        accessoryText: formattedAmount,
                        accessoryTextColor: Theme.primaryTextColor,
                        accessoryType: .disclosureIndicator,
                        accessibilityIdentifier: accessibilityIdentifier
                    )
                },
                actionBlock: { [weak self] in
                    let vc = DonationReceiptViewController(model: donationReceipt)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            )

            sectionForThisYear.add(tableItem)
        }

        return result
    }
}
