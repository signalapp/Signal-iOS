//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

class BadgeDetailsSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }
    override var renderExternalHandle: Bool { false }

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

    public enum Owner: Equatable {
        // TODO: Eventually we won't need a short name for self, the server will provide copy for us.
        case local(shortName: String)
        case remote(shortName: String)

        func formattedDescription(for badge: ProfileBadge) -> String {
            switch self {
            case .local(let shortName):
                return badge.localizedDescriptionFormatString.replacingOccurrences(of: "{short_name}", with: shortName)
            case .remote(let shortName):
                return badge.localizedDescriptionFormatString.replacingOccurrences(of: "{short_name}", with: shortName)
            }
        }

        var isLocal: Bool {
            switch self {
            case .local: return true
            case .remote: return false
            }
        }
    }
    private let owner: Owner
    private let focusedBadge: ProfileBadge

    // TODO: support initializing with a list of available badges and paging between them
    required init(focusedBadge: ProfileBadge, owner: Owner) {
        self.focusedBadge = focusedBadge
        self.owner = owner
        super.init()
        createContent()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        handleContainer.backgroundColor = Theme.tableView2PresentedBackgroundColor
        updateTableContents()
    }

    private func createContent() {
        addChild(tableViewController)
        tableViewController.shouldDeferInitialLoad = false

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

        updateViewState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateViewState()
    }

    private var previousMinimizedHeight: CGFloat?
    private var previousSafeAreaInsets: UIEdgeInsets?
    private func updateViewState() {
        if previousSafeAreaInsets != tableViewController.view.safeAreaInsets {
            updateTableContents()
            previousSafeAreaInsets = tableViewController.view.safeAreaInsets
        }
        if minimizedHeight != previousMinimizedHeight {
            heightConstraint?.constant = minimizedHeight
            previousMinimizedHeight = minimizedHeight
        }
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        defer { tableViewController.contents = contents }

        let focusedBadgeSection = OWSTableSection()
        focusedBadgeSection.hasBackground = false
        contents.addSection(focusedBadgeSection)

        focusedBadgeSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            let badgeImageView = UIImageView()
            badgeImageView.image = self.focusedBadge.assets?.universal160
            badgeImageView.autoSetDimensions(to: CGSize(square: 160))
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(14, after: badgeImageView)

            let badgeLabel = UILabel()
            badgeLabel.font = .ows_dynamicTypeTitle3.ows_semibold
            badgeLabel.textColor = Theme.primaryTextColor
            badgeLabel.textAlignment = .center
            badgeLabel.numberOfLines = 0
            badgeLabel.text = self.focusedBadge.localizedName
            stackView.addArrangedSubview(badgeLabel)
            stackView.setCustomSpacing(36, after: badgeLabel)

            let badgeDescription = UILabel()
            badgeDescription.font = .ows_dynamicTypeBody
            badgeDescription.textColor = Theme.primaryTextColor
            badgeDescription.textAlignment = .center
            badgeDescription.numberOfLines = 0
            badgeDescription.text = self.owner.formattedDescription(for: self.focusedBadge)
            badgeDescription.setCompressionResistanceVerticalHigh()
            badgeDescription.setContentHuggingVerticalHigh()
            stackView.addArrangedSubview(badgeDescription)
            stackView.setCustomSpacing(30, after: badgeDescription)

            return cell
        }, actionBlock: nil))

        // Don't show actions for the local user's badges.
        guard !owner.isLocal else { return }

        switch focusedBadge.rawCategory.lowercased() {
        case "donor":
            if DonationUtilities.isApplePayAvailable {
                if BoostBadgeIds.contains(focusedBadge.id) {
                    let boostButtonSection = OWSTableSection()
                    boostButtonSection.hasBackground = false
                    contents.addSection(boostButtonSection)
                    boostButtonSection.add(.init(customCellBlock: { [weak self] in
                        let cell = OWSTableItem.newCell()
                        cell.selectionStyle = .none
                        guard let self = self else { return cell }

                        let boostButton = OWSFlatButton.button(
                            title: NSLocalizedString(
                                "BADGE_DETAILS_GIVE_A_BOOST",
                                comment: "Text prompting the user to boost"),
                            font: UIFont.ows_dynamicTypeBody.ows_semibold,
                            titleColor: .white,
                            backgroundColor: .ows_accentBlue,
                            target: self,
                            selector: #selector(self.didTapBoost)
                        )
                        boostButton.autoSetHeightUsingFont()
                        boostButton.cornerRadius = 8
                        cell.contentView.addSubview(boostButton)
                        boostButton.autoPinEdgesToSuperviewMargins()

                        return cell
                    }, actionBlock: nil))
                } else if SubscriptionBadgeIds.contains(focusedBadge.id) {
                    let subscribeButtonSection = OWSTableSection()
                    subscribeButtonSection.hasBackground = false
                    contents.addSection(subscribeButtonSection)
                    subscribeButtonSection.add(.init(customCellBlock: { [weak self] in
                        let cell = OWSTableItem.newCell()
                        cell.selectionStyle = .none
                        guard let self = self else { return cell }

                        let subscribeButton = OWSFlatButton.button(
                            title: NSLocalizedString(
                                "BADGE_DETAILS_BECOME_A_SUSTAINER",
                                comment: "Text prompting the user to become a signal sustainer"),
                            font: UIFont.ows_dynamicTypeBody.ows_semibold,
                            titleColor: .white,
                            backgroundColor: .ows_accentBlue,
                            target: self,
                            selector: #selector(self.didTapSubscribe)
                        )
                        subscribeButton.autoSetHeightUsingFont()
                        subscribeButton.cornerRadius = 8
                        cell.contentView.addSubview(subscribeButton)
                        subscribeButton.autoPinEdgesToSuperviewMargins()

                        return cell
                    }, actionBlock: nil))
                }
            } else {
                // TODO: Show generic donation link
            }
        default:
            break
        }

    }

    @objc
    func didTapSubscribe() {
        dismiss(animated: true) {
            CurrentAppContext().frontmostViewController()?.present(OWSNavigationController(rootViewController: SubscriptionViewController()), animated: true)
        }
    }

    @objc
    func didTapBoost() {
        dismiss(animated: true) {
            CurrentAppContext().frontmostViewController()?.present(BoostSheetView(), animated: true)
        }
    }
}
