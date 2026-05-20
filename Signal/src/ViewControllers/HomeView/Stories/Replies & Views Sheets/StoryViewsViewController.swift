//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

private struct Viewer {
    let address: SignalServiceAddress
    let comparableName: ComparableDisplayName
    let viewedTimestamp: UInt64
}

class StoryViewsViewController: OWSViewController, DatabaseChangeDelegate, UIAdaptivePresentationControllerDelegate,
    UITableViewDelegate, UITableViewDataSource
{
    private(set) var storyMessage: StoryMessage

    let context: StoryContext

    // This VC also gets embedded as a child VC into StoryGroupRepliesAndViewsSheet.
    // Distinguish that vs when this VC is presented on its own.
    private let isStandaloneVC: Bool

    var dismissHandler: (() -> Void)?

    let tableView = UITableView(frame: .zero, style: .grouped)

    private let emptyStateView = UIView()

    init(storyMessage: StoryMessage, context: StoryContext, isStandaloneVC: Bool) {
        self.storyMessage = storyMessage
        self.context = context
        self.isStandaloneVC = isStandaloneVC

        super.init()

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        overrideUserInterfaceStyle = .dark

        if isStandaloneVC {
            modalPresentationStyle = .pageSheet
            presentationController?.delegate = self

            if let sheetPresentationController {
                if #available(iOS 17.0, *) {
                    sheetPresentationController.traitOverrides.userInterfaceStyle = .dark
                } else {
                    sheetPresentationController.overrideTraitCollection = UITraitCollection(userInterfaceStyle: .dark)
                }
                sheetPresentationController.detents = [.medium(), .large()]
                sheetPresentationController.prefersGrabberVisible = true
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.tableHeaderView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: CGFloat.leastNormalMagnitude)))
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        tableView.register(StoryViewCell.self, forCellReuseIdentifier: StoryViewCell.reuseIdentifier)

        view.addSubview(emptyStateView)
        emptyStateView.preservesSuperviewLayoutMargins = true
        emptyStateView.autoPinEdgesToSuperviewEdges()

        updateViewers()
    }

    // MARK: - Data

    private var viewers = [Viewer]()

    private func updateViewers(reloadStoryMessage: Bool = false) {
        defer {
            tableView.reloadData()
            // If it's a personal story, only allow half-screen sheet only if no views.
            if isStandaloneVC {
                sheetPresentationController?.detents = if viewers.isEmpty { [.medium()] } else { [.medium()] }
            }
            updateEmptyStateView()
        }

        guard StoryManager.areViewReceiptsEnabled else {
            self.viewers = []
            return
        }

        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            if reloadStoryMessage {
                guard let latestStoryMessage = StoryMessage.anyFetch(uniqueId: storyMessage.uniqueId, transaction: transaction) else {
                    owsFailDebug("Missing story message")
                    self.viewers = []
                    return
                }

                self.storyMessage = latestStoryMessage
            }

            guard case .outgoing(let recipientStates) = storyMessage.manifest else {
                owsFailDebug("Invalid story message for views")
                self.viewers = []
                return
            }

            let config: DisplayName.ComparableValue.Config = .current()
            self.viewers = recipientStates
                .lazy
                .filter { $1.isValidForContext(self.context) }
                .compactMap { serviceId, recipientState -> Viewer? in
                    guard let viewedTimestamp = recipientState.viewedTimestamp else { return nil }
                    let address = SignalServiceAddress(serviceId)
                    return Viewer(
                        address: address,
                        comparableName: ComparableDisplayName(
                            address: address,
                            displayName: SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: transaction),
                            config: config,
                        ),
                        viewedTimestamp: viewedTimestamp,
                    )
                }.sorted { lhs, rhs in
                    if lhs.viewedTimestamp != rhs.viewedTimestamp {
                        return lhs.viewedTimestamp > rhs.viewedTimestamp
                    }
                    return lhs.comparableName < rhs.comparableName
                }
        }
    }

    private func updateEmptyStateView() {
        emptyStateView.removeAllSubviews()
        emptyStateView.isHidden = viewers.count > 0

        if StoryManager.areViewReceiptsEnabled {
            let label = UILabel()
            label.textAlignment = .center
            label.font = .dynamicTypeHeadline
            label.textColor = .Signal.secondaryLabel
            label.text = OWSLocalizedString(
                "STORIES_NO_VIEWS_YET",
                comment: "Indicates that this story has no views yet",
            )
            emptyStateView.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(greaterThanOrEqualTo: emptyStateView.topAnchor),
                label.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),

                label.leadingAnchor.constraint(equalTo: emptyStateView.layoutMarginsGuide.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: emptyStateView.layoutMarginsGuide.trailingAnchor),
            ])

            emptyStateView.isUserInteractionEnabled = false
        } else {
            let label = UILabel()
            label.textAlignment = .center
            label.font = .dynamicTypeSubheadline
            label.textColor = .Signal.secondaryLabel
            label.text = OWSLocalizedString(
                "STORIES_VIEWS_OFF_DESCRIPTION",
                comment: "Text explaining that you will not see any views for your story because you have view receipts turned off",
            )
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.setContentHuggingVerticalHigh()

            let settingsButton = UIButton(
                configuration: .smallSecondary(title: CommonStrings.goToSettingsButton),
                primaryAction: UIAction { [weak self] _ in
                    guard let self else { return }

                    let privacySettings = OWSNavigationController(rootViewController: StoryPrivacySettingsViewController())

                    // Dismiss the story view and present the privacy settings screen
                    owsAssertDebug(self.presentingViewController?.presentingViewController is ConversationSplitViewController)
                    self.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: {
                        CurrentAppContext().frontmostViewController()?.present(privacySettings, animated: true)
                    })
                },
            )

            let stackView = UIStackView(arrangedSubviews: [
                label,
                settingsButton,
            ])
            stackView.axis = .vertical
            stackView.spacing = 20
            stackView.alignment = .center
            emptyStateView.addSubview(stackView)
            stackView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(greaterThanOrEqualTo: emptyStateView.topAnchor),
                stackView.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),

                stackView.leadingAnchor.constraint(equalTo: emptyStateView.layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: emptyStateView.layoutMarginsGuide.trailingAnchor),
            ])

            emptyStateView.isUserInteractionEnabled = true
        }
    }

    // MARK: - UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: StoryViewCell.reuseIdentifier, for: indexPath) as! StoryViewCell
        guard let viewer = viewers[safe: indexPath.row] else {
            owsFailDebug("Unexpectedly missing viewer")
            return UITableViewCell()
        }
        cell.configure(with: viewer)
        return cell
    }

    // MARK: - DatabaseChangeDelegate

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.storyMessageRowIds.contains(storyMessage.id!) {
            updateViewers(reloadStoryMessage: true)
        }
    }

    func databaseChangesDidUpdateExternally() {
        updateViewers(reloadStoryMessage: true)
    }

    func databaseChangesDidReset() {
        updateViewers(reloadStoryMessage: true)
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        dismissHandler?()
    }
}

private class StoryViewCell: UITableViewCell {

    static let reuseIdentifier = "StoryViewCell"

    let avatarView = ConversationAvatarView(sizeClass: .thirtySix, localUserDisplayMode: .asUser, badged: true)

    lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBodyClamped
        label.textColor = .Signal.label
        return label
    }()

    lazy var timestampLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeFootnoteClamped
        label.textColor = .Signal.secondaryLabel
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear

        let hStack = UIStackView(arrangedSubviews: [avatarView, nameLabel, .hStretchingSpacer(), timestampLabel])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 12
        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with viewer: Viewer) {
        avatarView.updateWithSneakyTransactionIfNecessary { $0.dataSource = .address(viewer.address) }
        nameLabel.text = viewer.comparableName.resolvedValue()
        timestampLabel.text = DateUtil.formatPastTimestampRelativeToNow(viewer.viewedTimestamp)
    }
}
