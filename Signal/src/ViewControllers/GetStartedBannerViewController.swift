//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSGetStartedBannerViewControllerDelegate)
protocol GetStartedBannerViewControllerDelegate: class {
    func getStartedBannerDidTapInviteFriends(_ banner: GetStartedBannerViewController)
    func getStartedBannerDidTapCreateGroup(_ banner: GetStartedBannerViewController)
}

@objc(OWSGetStartedBannerViewController)
class GetStartedBannerViewController: UIViewController, UICollectionViewDelegateFlowLayout {

    // MARK: - Views

    private let header: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
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

    private let backdrop = GradientView(colors: [
        (color: .ows_whiteAlpha0, location: 0.0588),
        (color: .ows_white, location: 0.2059)
    ])

    // MARK: - Data

    @objc
    public var hasIncompleteCards: Bool { bannerContent.count > 0 }

    private weak var delegate: GetStartedBannerViewControllerDelegate?
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

    private func dismissFromParent() {
        UIView.animate(withDuration: 0.5) {
            self.view.alpha = 0
        } completion: { _ in
            self.view.removeFromSuperview()
            self.removeFromParent()
        }
    }

    func updateContent() {
        bannerContent = SDSDatabaseStorage.shared.uiRead { readTx in
            let activeCards = Self.getActiveCards(readTx: readTx)

            // If we have five or more threads, dismiss all cards
            if activeCards.count > 0, TSThread.anyCount(transaction: readTx) >= 5 {
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
            dismissFromParent()
            return
        }

        collectionView.performBatchUpdates {
            let oldBannerIds = oldValue.map { $0.identifier }
            let newBannerIds = bannerContent.map { $0.identifier }

            collectionView.deleteItems(
                at: oldBannerIds.enumerated()
                    .filter { newBannerIds.contains($0.element) == false }
                    .map { IndexPath(item: $0.offset, section: 0) })

            collectionView.insertItems(
                at: newBannerIds.enumerated()
                    .filter { oldBannerIds.contains($0.element) == false }
                    .map { IndexPath(item: $0.offset, section: 0) })
        }
    }
}

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

extension GetStartedBannerViewController {
    private static let keyValueStore = SDSKeyValueStore(collection: "GetStartedBannerViewController")
    private static let bannerState = "BannerState"
    private static let completePrefix = "CompletedCard."

    @objc(resetAllCardsWithTransaction:)
    static func resetAllCards(writeTx: SDSAnyWriteTransaction) {
        keyValueStore.removeAll(transaction: writeTx)
    }

    static func dismissAllCards(writeTx: SDSAnyWriteTransaction) {
        GetStartedBannerEntry.allCases.forEach { entry in
            let key = completePrefix + entry.identifier
            keyValueStore.setBool(true, key: key, transaction: writeTx)
        }
    }

    static private func getActiveCards(readTx: SDSAnyReadTransaction) -> [GetStartedBannerEntry] {
        return GetStartedBannerEntry.allCases.filter { entry in
            let key = completePrefix + entry.identifier
            let isComplete = keyValueStore.getBool(key, defaultValue: false, transaction: readTx)
            return !isComplete
        }
    }

    static private func completeCard(_ model: GetStartedBannerEntry, writeTx: SDSAnyWriteTransaction) {
        let key = Self.completePrefix + model.identifier
        Self.keyValueStore.setBool(true, key: key, transaction: writeTx)
    }
}
