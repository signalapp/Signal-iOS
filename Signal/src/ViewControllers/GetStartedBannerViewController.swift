//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol GetStartedBannerViewControllerDelegate: AnyObject {
    func getStartedBannerDidTapInviteFriends(_ banner: GetStartedBannerViewController)
    func getStartedBannerDidTapCreateGroup(_ banner: GetStartedBannerViewController)
    func getStartedBannerDidTapAppearance(_ banner: GetStartedBannerViewController)
    func getStartedBannerDidDismissAllCards(_ banner: GetStartedBannerViewController, animated: Bool)
    func getStartedBannerDidTapAvatarBuilder(_ banner: GetStartedBannerViewController)
}

class GetStartedBannerViewController: UIViewController, UICollectionViewDelegateFlowLayout {

    // MARK: - Views

    private let header: UILabel = {
        let label = UILabel()
        label.font = UIFont.dynamicTypeBodyClamped.semibold()
        label.adjustsFontForContentSizeCategory = true
        label.text = OWSLocalizedString(
            "GET_STARTED_BANNER_TITLE",
            comment: "Title for the 'Get Started' banner")
        return label
    }()

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 166, height: 178)
        layout.minimumInteritemSpacing = 16
        layout.sectionInsetReference = .fromLayoutMargins

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.register(GetStartedBannerCell.self, forCellWithReuseIdentifier: GetStartedBannerCell.reuseIdentifier)
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        return view
    }()

    // Colors are updated in applyTheme()
    private let opaqueBackdrop = UIView()
    private let gradientBackdrop: GradientView = {
        let gradient = GradientView(colors: [])
        gradient.isUserInteractionEnabled = false
        return gradient
    }()

    // MARK: - Data

    public var hasIncompleteCards: Bool { bannerContent.count > 0 }

    public var opaqueHeight: CGFloat { view.height - gradientBackdrop.height }

    private weak var delegate: GetStartedBannerViewControllerDelegate?
    private let threadFinder = AnyThreadFinder()
    private var bannerContent: [GetStartedBannerEntry] = []

    // MARK: - Lifecycle

    init(delegate: GetStartedBannerViewControllerDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)

        updateContent()
        applyTheme()

        SDSDatabaseStorage.shared.appendDatabaseChangeDelegate(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: .themeDidChange,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activeCardsDidChange),
            name: Self.activeCardsDidChange,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localProfileDidChange),
            name: .localProfileDidChange,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = PassthroughView()

        view.addSubview(gradientBackdrop)
        view.addSubview(opaqueBackdrop)
        view.addSubview(header)
        view.addSubview(collectionView)
        view.layoutMargins = UIEdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8)

        gradientBackdrop.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        gradientBackdrop.autoSetDimension(.height, toSize: 40)
        opaqueBackdrop.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        opaqueBackdrop.autoPinEdge(.top, to: .bottom, of: gradientBackdrop)

        header.autoPinLeadingToSuperviewMargin()
        header.autoPinEdge(toSuperviewMargin: .trailing, relation: .lessThanOrEqual)
        header.autoPinEdge(.top, to: .top, of: opaqueBackdrop, withOffset: 8)

        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.autoSetDimension(.height, toSize: 180)
        collectionView.autoPinEdge(.top, to: .bottom, of: header, withOffset: 12)
        collectionView.autoPinWidthToSuperview()
        collectionView.autoPinBottomToSuperviewMargin()
        collectionView.clipsToBounds = false

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.delegate = self
        collectionView.dataSource = self
    }

    @objc
    func applyTheme() {
        header.textColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_black
        let backdropColor = Theme.backgroundColor
        opaqueBackdrop.backgroundColor = backdropColor

        if Theme.isDarkThemeEnabled {
            gradientBackdrop.colors = [ .clear, backdropColor ]
        } else {
            gradientBackdrop.colors = [ .ows_whiteAlpha00, backdropColor ]
        }
    }

    func fetchContent() -> [GetStartedBannerEntry] {
        SDSDatabaseStorage.shared.read { readTx in
            let activeCards = Self.getActiveCards(readTx: readTx)

            let visibleThreadCount: UInt
            do {
                let unarchivedThreadCount = try self.threadFinder.visibleThreadCount(isArchived: false, transaction: readTx)
                let archivedThreadCount = try self.threadFinder.visibleThreadCount(isArchived: true, transaction: readTx)
                visibleThreadCount = unarchivedThreadCount + archivedThreadCount
            } catch {
                owsFailDebug("Failed to fetch thread count")
                return []
            }

            // If we have five or more threads, dismiss all cards
            if activeCards.count > 0, visibleThreadCount >= 5 {
                Logger.info("User has more than five threads. Dismissing Get Started banner.")
                SDSDatabaseStorage.shared.asyncWrite { writeTx in
                    Self.dismissAllCards(writeTx: writeTx)
                }
                return []
            } else {
                // Once you have an avatar, don't show the avatar builder card.
                if Self.profileManager.localProfileAvatarData() != nil {
                    Self.databaseStorage.asyncWrite { writeTx in
                        Self.completeCard(.avatarBuilder, writeTx: writeTx)
                    }
                    return activeCards.filter { $0 != .avatarBuilder }
                }
                return activeCards
            }
        }
    }

    func updateContent() {
        let oldContent = bannerContent
        let newContent = fetchContent()

        // The data source is only set after -viewDidLoad
        // We can skip animations if we haven't been showing content to begin with
        let isAnimated = (collectionView.dataSource === self)

        if isAnimated {
            collectionView.performBatchUpdates {
                bannerContent = newContent

                let oldBannerIds = oldContent.map { $0.identifier }
                let newBannerIds = newContent.map { $0.identifier }

                // Delete everything in oldBannerIds that's not in newBannerIds
                collectionView.deleteItems(
                    at: oldBannerIds.enumerated()
                        .filter { newBannerIds.contains($0.element) == false }
                        .map { IndexPath(item: $0.offset, section: 0) })

                // Insert everything in newBannerIds that's not in oldBannerIds
                collectionView.insertItems(
                    at: newBannerIds.enumerated()
                        .filter { oldBannerIds.contains($0.element) == false }
                        .map { IndexPath(item: $0.offset, section: 0) })
            }
        } else {
            bannerContent = newContent
        }

        if bannerContent.count == 0 {
            delegate?.getStartedBannerDidDismissAllCards(self, animated: isAnimated)
        }
    }
}

// MARK: - UICollectionViewDataSource

extension GetStartedBannerViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if section == 0 {
            return bannerContent.count
        } else {
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard indexPath.item < bannerContent.count,
              let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GetStartedBannerCell.reuseIdentifier,
                for: indexPath) as? GetStartedBannerCell else {
            owsFailDebug("Unrecognized cell type")
            return UICollectionViewCell()
        }

        let model = bannerContent[indexPath.item]
        cell.configure(model: model, delegate: self)
        return cell
    }
}

// MARK: - Actions

extension GetStartedBannerViewController: GetStartedBannerCellDelegate {
    func didTapClose(_ cell: GetStartedBannerCell) {
        guard let model = cell.model else { return }

        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            Self.completeCard(model, writeTx: writeTx)
        }
    }

    func didTapAction(_ cell: GetStartedBannerCell) {
        guard let model = cell.model else { return }

        switch model {
        case .inviteFriends:
            delegate?.getStartedBannerDidTapInviteFriends(self)
        case .newGroup:
            delegate?.getStartedBannerDidTapCreateGroup(self)
        case .appearance:
            delegate?.getStartedBannerDidTapAppearance(self)
        case .avatarBuilder:
            delegate?.getStartedBannerDidTapAvatarBuilder(self)
        }
    }
}

// MARK: - Storage

extension GetStartedBannerViewController {
    private static let activeCardsDidChange = NSNotification.Name("ActiveBannerCardsDidChange")
    private static let keyValueStore = SDSKeyValueStore(collection: "GetStartedBannerViewController")
    private static let completePrefix = "ActiveCard."

    static func enableAllCards(writeTx: SDSAnyWriteTransaction) {
        var didChange = false

        GetStartedBannerEntry.allCases.forEach { entry in
            let key = completePrefix + entry.identifier

            let isActive = keyValueStore.getBool(key, defaultValue: false, transaction: writeTx)
            guard !isActive else {
                // Card already active.
                return
            }

            Self.keyValueStore.setBool(true, key: key, transaction: writeTx)
            didChange = true
        }

        guard didChange else {
            return
        }

        writeTx.addSyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(activeCardsDidChange, object: nil)
        }
    }

    static private func getActiveCards(readTx: SDSAnyReadTransaction) -> [GetStartedBannerEntry] {
        GetStartedBannerEntry.allCases.filter { entry in
            let key = completePrefix + entry.identifier
            let isActive = keyValueStore.getBool(key, defaultValue: false, transaction: readTx)
            return isActive
        }
    }

    static func dismissAllCards(writeTx: SDSAnyWriteTransaction) {
        var didChange = false

        GetStartedBannerEntry.allCases.forEach { entry in
            let key = completePrefix + entry.identifier

            let isActive = keyValueStore.getBool(key, defaultValue: false, transaction: writeTx)
            guard isActive else {
                // Card not active.
                return
            }

            Self.keyValueStore.removeValue(forKey: key, transaction: writeTx)
            didChange = true
        }

        guard didChange else {
            return
        }

        writeTx.addSyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(activeCardsDidChange, object: nil)
        }
    }

    static private func completeCard(_ model: GetStartedBannerEntry, writeTx: SDSAnyWriteTransaction) {
        let key = Self.completePrefix + model.identifier

        let isActive = keyValueStore.getBool(key, defaultValue: false, transaction: writeTx)
        guard isActive else {
            // Card not active.
            return
        }

        Self.keyValueStore.removeValue(forKey: key, transaction: writeTx)

        writeTx.addSyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(activeCardsDidChange, object: nil)
        }
    }
}

// MARK: - Database Observation

extension GetStartedBannerViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        if databaseChanges.didUpdateThreads {
            updateContent()
        }
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        updateContent()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        updateContent()
    }

    @objc
    private func activeCardsDidChange() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        updateContent()
    }

    @objc
    private func localProfileDidChange() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        updateContent()
    }
}

// Wrapper view for a collection of interactable subviews
// Will not return a positive hit test result for itself
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result != self ? result : nil
    }
}
