//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSGetStartedBannerViewControllerDelegate)
protocol GetStartedBannerViewControllerDelegate: class {
    func getStartedBannerDidTapInviteFriends(_ banner: GetStartedBannerViewController)
    func getStartedBannerDidTapCreateGroup(_ banner: GetStartedBannerViewController)
    func getStartedBannerDidDismissAllCards(_ banner: GetStartedBannerViewController)
}

@objc(OWSGetStartedBannerViewController)
class GetStartedBannerViewController: UIViewController, UICollectionViewDelegateFlowLayout {

    // MARK: - Views

    private let header: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        label.adjustsFontForContentSizeCategory = true
        label.text = NSLocalizedString(
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
    private let backdrop = GradientView(colors: [])

    // MARK: - Data

    @objc
    public var hasIncompleteCards: Bool { bannerContent.count > 0 }

    private weak var delegate: GetStartedBannerViewControllerDelegate?
    private let threadFinder = AnyThreadFinder()
    private var bannerContent: [GetStartedBannerEntry] = [] {
        didSet {
            handleUpdatedContent(from: oldValue, to: bannerContent)
        }
    }

    // MARK: - Lifecycle

    @objc
    init(delegate: GetStartedBannerViewControllerDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)

        collectionView.delegate = self
        collectionView.dataSource = self
        updateContent()

        SDSDatabaseStorage.shared.appendUIDatabaseSnapshotDelegate(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: .ThemeDidChange,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = UIView()

        view.addSubview(backdrop)
        view.addSubview(header)
        view.addSubview(collectionView)

        backdrop.autoPinEdgesToSuperviewEdges()

        header.autoPinLeadingToSuperviewMargin()
        header.autoPinEdge(toSuperviewMargin: .trailing, relation: .lessThanOrEqual)
        header.autoPinEdge(.top, to: .top, of: backdrop, withOffset: 82)

        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.autoSetDimension(.height, toSize: 180)
        collectionView.autoPinEdge(.top, to: .bottom, of: header, withOffset: 12)
        collectionView.autoPinWidthToSuperview()
        collectionView.autoPinBottomToSuperviewMargin()
        collectionView.clipsToBounds = false

        self.view = view
    }

    @objc func applyTheme() {
        header.textColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_black

        if Theme.isDarkThemeEnabled {
            backdrop.colors = [
                (color: .clear, location: 0.0588),
                (color: .ows_black, location: 0.2059)
            ]
        } else {
            backdrop.colors = [
                (color: .ows_whiteAlpha00, location: 0.0588),
                (color: .ows_white, location: 0.2059)
            ]
        }
    }

    func updateContent() {
        bannerContent = SDSDatabaseStorage.shared.uiRead { readTx in
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
                return activeCards
            }
        }
    }

    private func handleUpdatedContent(from oldValue: [GetStartedBannerEntry], to newValue: [GetStartedBannerEntry]) {
        guard bannerContent.count > 0 else {
            delegate?.getStartedBannerDidDismissAllCards(self)
            return
        }

        collectionView.performBatchUpdates {
            let oldBannerIds = oldValue.map { $0.identifier }
            let newBannerIds = bannerContent.map { $0.identifier }

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
        } completion: {
            self.updateContent()
        }
    }

    func didTapAction(_ cell: GetStartedBannerCell) {
        guard let model = cell.model else { return }

        switch model {
        case .InviteFriends:
            delegate?.getStartedBannerDidTapInviteFriends(self)
        case .NewGroup:
            delegate?.getStartedBannerDidTapCreateGroup(self)
        }
    }
}

// MARK: - Storage

extension GetStartedBannerViewController {
    private static let keyValueStore = SDSKeyValueStore(collection: "GetStartedBannerViewController")
    private static let completePrefix = "CompletedCard."

    @objc(resetAllCardsWithTransaction:)
    static func resetAllCards(writeTx: SDSAnyWriteTransaction) {
        keyValueStore.removeAll(transaction: writeTx)
    }

    static private func getActiveCards(readTx: SDSAnyReadTransaction) -> [GetStartedBannerEntry] {
        return GetStartedBannerEntry.allCases.filter { entry in
            let key = completePrefix + entry.identifier
            let isComplete = keyValueStore.getBool(key, defaultValue: false, transaction: readTx)
            return !isComplete
        }
    }

    static func dismissAllCards(writeTx: SDSAnyWriteTransaction) {
        GetStartedBannerEntry.allCases.forEach { entry in
            completeCard(entry, writeTx: writeTx)
        }
    }

    static private func completeCard(_ model: GetStartedBannerEntry, writeTx: SDSAnyWriteTransaction) {
        let key = Self.completePrefix + model.identifier
        Self.keyValueStore.setBool(true, key: key, transaction: writeTx)
    }
}

// MARK: - Database Observation

extension GetStartedBannerViewController: UIDatabaseSnapshotDelegate {
    public func uiDatabaseSnapshotWillUpdate() {}

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        if databaseChanges.didUpdateThreads {
            updateContent()
        }
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        updateContent()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
        updateContent()
    }
}
