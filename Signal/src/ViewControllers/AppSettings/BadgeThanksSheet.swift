//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalUI

class BadgeThanksSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }
    override var renderExternalHandle: Bool { false }
    private var shouldMakeVisibleAndPrimary = false

    var contentSizeHeight: CGFloat {
        tableViewController.tableView.contentSize.height + tableViewController.tableView.adjustedContentInset.totalHeight
    }
    override var minimizedHeight: CGFloat {
        return min(contentSizeHeight, maximizedHeight)
    }
    override var maximizedHeight: CGFloat {
        min(contentSizeHeight, CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32))
    }

    private let tableViewController = OWSTableViewController2()
    private let handleContainer = UIView()

    private static let boostBadgeId = "BOOST"
    private let badge: ProfileBadge
    private var isBoost: Bool { badge.id == Self.boostBadgeId }
    private var isPrimaryBadge: Bool { badge.id == visibleBadges.first?.badgeId }

    private lazy var profileSnapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)
    private lazy var hasAnySustainerBadge = profileSnapshot.profileBadgeInfo?.first { $0.badgeId != Self.boostBadgeId } != nil
    private lazy var newBadgeIsBoost = badge.id == Self.boostBadgeId
    private lazy var visibleBadges = profileSnapshot.profileBadgeInfo?.filter { $0.isVisible ?? false } ?? []

    required init(badge: ProfileBadge) {
        owsAssertDebug(badge.assets != nil)
        self.badge = badge

        super.init()

        tableViewController.shouldDeferInitialLoad = false
        updateTableContents()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    override func willDismissInteractively() {
        super.willDismissInteractively()
        saveVisibilityChanges()
    }

    @objc
    func didTapDone() {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            self.saveVisibilityChanges().ensure {
                modal.dismiss {
                    self.dismiss(animated: true)
                }
            }.catch { error in
                owsFailDebug("Unexpectedly failed to save badge visibility \(error)")
            }
        }
    }

    @discardableResult
    func saveVisibilityChanges() -> Promise<Void> {
        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)

        let allBadges = snapshot.profileBadgeInfo ?? []
        let nonPrimaryBadgeIds = allBadges.filter { $0.badgeId != self.badge.id }.map { $0.badgeId }

        let visibleBadgeIds: [String]
        if shouldMakeVisibleAndPrimary {
            visibleBadgeIds = [self.badge.id] + nonPrimaryBadgeIds
        } else if !nonPrimaryBadgeIds.isEmpty {
            visibleBadgeIds = nonPrimaryBadgeIds + [self.badge.id]
        } else {
            visibleBadgeIds = []
        }

        return OWSProfileManager.updateLocalProfilePromise(
            profileGivenName: snapshot.givenName,
            profileFamilyName: snapshot.familyName,
            profileBio: snapshot.bio,
            profileBioEmoji: snapshot.bioEmoji,
            profileAvatarData: snapshot.avatarData,
            visibleBadgeIds: visibleBadgeIds,
            userProfileWriter: .localUser
        )
    }

    var titleText: String {
        switch badge.id {
        case "BOOST": return NSLocalizedString(
            "BADGE_THANKS_BOOST_TITLE",
            comment: "Title for boost on the thank you sheet."
        )
        default: return NSLocalizedString(
            "BADGE_THANKS_SUBSCRIPTION_TITLE",
            comment: "Title for subscription on the thank you sheet."
        )
        }
    }

    var bodyText: String {
        let formatText = NSLocalizedString(
            "BADGE_THANKS_YOU_EARNED_FORMAT",
            comment: "String explaing to the user that they've earned a badge on the badge thank you sheet. Embed {badge name}."
        )
        return String(format: formatText, badge.localizedName)
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        addChild(tableViewController)

        contentView.addSubview(tableViewController.view)
        tableViewController.view.autoPinEdgesToSuperviewEdges()

        // We add the handle directly to the content view,
        // so that it doesn't scroll with the table.
        handleContainer.backgroundColor = Theme.tableView2PresentedBackgroundColor
        contentView.addSubview(handleContainer)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.autoPinEdge(toSuperviewEdge: .top)

        let handle = UIView()
        handle.backgroundColor = tableViewController.separatorColor
        handle.autoSetDimensions(to: CGSize(width: 36, height: 5))
        handle.layer.cornerRadius = 5 / 2
        handleContainer.addSubview(handle)
        handle.autoPinHeightToSuperview(withMargin: 12)
        handle.autoHCenterInSuperview()

        if newBadgeIsBoost && hasAnySustainerBadge {
            shouldMakeVisibleAndPrimary = false
        } else if !isPrimaryBadge {
            shouldMakeVisibleAndPrimary = true
        } else {
            shouldMakeVisibleAndPrimary = false
        }

        updateViewState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateViewState()
    }

    private var previousMinimizedHeight: CGFloat?
    private func updateViewState() {
        if minimizedHeight != previousMinimizedHeight {
            heightConstraint?.constant = minimizedHeight
            previousMinimizedHeight = minimizedHeight
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        handleContainer.backgroundColor = Theme.tableView2PresentedBackgroundColor
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { tableViewController.contents = contents }

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.customHeaderHeight = 1
        contents.addSection(headerSection)

        headerSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            let titleLabel = UILabel()
            titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.text = self.titleText
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(12, after: titleLabel)

            let bodyLabel = UILabel()
            bodyLabel.font = .ows_dynamicTypeBody
            bodyLabel.textColor = Theme.primaryTextColor
            bodyLabel.textAlignment = .center
            bodyLabel.numberOfLines = 0
            bodyLabel.text = self.bodyText
            stackView.addArrangedSubview(bodyLabel)
            stackView.setCustomSpacing(30, after: bodyLabel)

            let badgeImageView = UIImageView()
            badgeImageView.image = self.badge.assets?.universal160
            badgeImageView.autoSetDimensions(to: CGSize(square: 160))
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(14, after: badgeImageView)

            let badgeLabel = UILabel()
            badgeLabel.font = .ows_dynamicTypeTitle3.ows_semibold
            badgeLabel.textColor = Theme.primaryTextColor
            badgeLabel.textAlignment = .center
            badgeLabel.numberOfLines = 0
            badgeLabel.text = self.badge.localizedName
            stackView.addArrangedSubview(badgeLabel)
            stackView.setCustomSpacing(36, after: badgeLabel)

            return cell
        }, actionBlock: nil))

        if !isPrimaryBadge {
            let switchSection = OWSTableSection()
            contents.addSection(switchSection)
            switchSection.add(.switch(
                withText: visibleBadges.isEmpty
                ? NSLocalizedString(
                    "BADGE_THANKS_DISPLAY_ON_PROFILE_LABEL",
                    comment: "Label prompting the user to display the new badge on their profile on the badge thank you sheet."
                )
                : NSLocalizedString(
                    "BADGE_THANKS_MAKE_FEATURED",
                    comment: "Label prompting the user to feature the new badge on their profile on the badge thank you sheet."
                ),
                isOn: { self.shouldMakeVisibleAndPrimary },
                target: self,
                selector: #selector(didToggleDisplayOnProfile)
            ))
            if !visibleBadges.isEmpty {
                switchSection.footerTitle = NSLocalizedString(
                    "BADGE_THANKS_TOGGLE_FOOTER",
                    comment: "Footer explaining that only one badge can be featured at a time on the thank you sheet."
                )
            }
        }

        let doneButtonSection = OWSTableSection()
        doneButtonSection.hasBackground = false
        contents.addSection(doneButtonSection)
        doneButtonSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            guard let self = self else { return cell }

            let doneButton = OWSFlatButton.button(title: CommonStrings.doneButton,
                                                  font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                  titleColor: .white,
                                                  backgroundColor: .ows_accentBlue,
                                                  target: self,
                                                  selector: #selector(self.didTapDone))
            doneButton.autoSetHeightUsingFont()
            doneButton.cornerRadius = 8
            cell.contentView.addSubview(doneButton)
            doneButton.autoPinEdgesToSuperviewMargins()

            return cell
        }, actionBlock: nil))
    }

    @objc
    func didToggleDisplayOnProfile(_ sender: UISwitch) {
        shouldMakeVisibleAndPrimary = sender.isOn
    }
}
