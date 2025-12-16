//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import Combine

// MARK: - CallQualitySurveyIssuesViewController

final class CallQualitySurveyIssuesViewController: CallQualitySurveySheetViewController {
    private var sizeChangeSubscription: AnyCancellable?

    private let headerContainer = UIView()
    private let bottomStackView = UIStackView()
    private lazy var continueButton = UIButton(
        configuration: .largePrimary(title: CommonStrings.continueButton),
        primaryAction: .init { [weak sheetNav] _ in
            sheetNav?.doneSelectingIssues()
        }
    )
    private lazy var customIssueEntry = UIButton(
        configuration: customIssueButtonConfig(customText: nil),
        primaryAction: .init { [weak self] _ in
            self?.didTapCustomIssue()
        }
    )

    private let collectionView: UICollectionView = {
        let layout = CenteredFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 10
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

    private var selectedItems = Set<Item>()
    private var customIssue: String? {
        didSet {
            updateViewState()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_ISSUES_SHEET_TITLE",
            comment: "Title for the sheet in the call quality survey where issues with the call can be selected"
        )

        let headerLabel = UILabel()
        headerLabel.text = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_ISSUES_HEADER",
            comment: "Header text on the call quality survey issues screen"
        )
        headerLabel.font = .dynamicTypeSubheadline
        headerLabel.textColor = .Signal.secondaryLabel
        headerLabel.textAlignment = .center
        headerContainer.addSubview(headerLabel)
        headerLabel.autoPinEdgesToSuperviewMargins(with: .init(
            top: 0,
            leading: 36,
            bottom: 24,
            trailing: 36
        ))
        view.addSubview(headerContainer)
        headerContainer.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        headerContainer.layoutMargins = .zero
        headerContainer.preservesSuperviewLayoutMargins = true

        view.addSubview(collectionView)

        collectionView.backgroundColor = nil
        collectionView.autoPinWidthToSuperview()
        collectionView.autoPinEdge(.top, to: .bottom, of: headerContainer)
        collectionView.contentInset = .init(
            top: 0,
            leading: 8,
            bottom: 24,
            trailing: 8,
        )
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self

        bottomStackView.axis = .vertical
        bottomStackView.spacing = 24
        bottomStackView.isLayoutMarginsRelativeArrangement = true
        bottomStackView.directionalLayoutMargins = .init(hMargin: 12, vMargin: 0)
        view.addSubview(bottomStackView)
        bottomStackView.autoPinEdge(.top, to: .bottom, of: collectionView)
        bottomStackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)

        bottomStackView.addArrangedSubview(customIssueEntry)
        customIssueEntry.isHiddenInStackView = true
        customIssueEntry.contentHorizontalAlignment = .leading

        bottomStackView.addArrangedSubview(continueButton)

        if #available(iOS 16.0, *) {
            sizeChangeSubscription = collectionView
                .publisher(for: \.contentSize)
                .removeDuplicates()
                .sink { [weak self] contentSize in
                    // idk why, but without the dispatch, expansion happens
                    // without an animation, but shrinking does
                    DispatchQueue.main.async {
                        self?.reloadHeight()
                    }
                }
        }

        let cellRegistration = UICollectionView.CellRegistration<CapsuleCell, Item> { cell, _, item in
            // TODO: Account for selected icons
            cell.configure(title: item.title, image: item.image)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
        }

        loadInitialSnapshot()
        updateViewState()
    }

    override func customSheetHeight() -> CGFloat? {
        let headerHeight = headerContainer.height
        let collectionViewHeight = collectionView.contentSize.height + collectionView.contentInset.totalHeight
        let bottomStackHeight = bottomStackView.height
        return headerHeight + collectionViewHeight + bottomStackHeight
    }

    private func loadInitialSnapshot() {
        // TODO: Typealiases?
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems([.audio, .video, .callDropped, .other])
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func updateSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])

        // Audio
        snapshot.appendItems([.audio])
        let audioSubItems: [Item] = [.audioStuttering, .audioLocalEcho, .audioRemoteEcho, .audioDrop]
        if self.selectedItems.contains(.audio) {
            snapshot.appendItems(audioSubItems)
        } else {
            audioSubItems.forEach { self.selectedItems.remove($0) }
        }

        // Video
        snapshot.appendItems([.video])
        let videoSubItems: [Item] = [.videoNoCamera, .videoLowQuality, .videoLowResolution]
        if self.selectedItems.contains(.video) {
            snapshot.appendItems(videoSubItems)
        } else {
            videoSubItems.forEach { self.selectedItems.remove($0) }
        }

        snapshot.appendItems([.callDropped, .other])

        let oldSnapshot = self.dataSource?.snapshot()

        self.dataSource?.apply(snapshot, animatingDifferences: true)

        if #available(iOS 16, *) {
            // Sheets self-size on iOS 16+
        } else if
            let oldSnapshot,
            let sheet = sheetNav?.sheetPresentationController,
            snapshot.itemIdentifiers.count > oldSnapshot.itemIdentifiers.count
        {
            // Audio or video was selected, expanding the content with more.
            // Expand the sheet to accommodate.
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = .large
            }
        }
    }

    private func updateViewState() {
        customIssueEntry.configuration = customIssueButtonConfig(customText: customIssue)

        let hasSelectedCustomIssue = self.selectedItems.contains(.other)
        let emptyCustomIssueText = self.customIssue.isEmptyOrNil
        let missingCustomIssue = hasSelectedCustomIssue && emptyCustomIssueText

        let noIssuesSelected = self.selectedItems.isEmpty

        let disableContinueButton = missingCustomIssue || noIssuesSelected
        continueButton.isEnabled = !disableContinueButton

        let customIssueEntryShouldBeHidden = !self.selectedItems.contains(.other)
        if customIssueEntryShouldBeHidden != customIssueEntry.isHiddenInStackView {
            UIView.animate(withDuration: 0.3) {
                self.customIssueEntry.isHiddenInStackView = customIssueEntryShouldBeHidden
                DispatchQueue.main.async {
                    self.reloadHeight()
                }
            }
        }
    }

    private func customIssueButtonConfig(customText: String?) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .Signal.secondaryGroupedBackground

        if let customText {
            config.title = customText
            config.baseForegroundColor = .Signal.label
        } else {
            config.title = CallQualitySurveyCustomIssueViewController.placeholderText
            config.baseForegroundColor = .Signal.secondaryLabel
        }

        config.cornerStyle = .capsule
        config.titleAlignment = .leading
        config.contentInsets = .init(hMargin: 16, vMargin: 13)
        config.titleLineBreakMode = .byTruncatingTail
        return config
    }

    private func didTapCustomIssue() {
        let vc = CallQualitySurveyCustomIssueViewController(issue: self.customIssue)
        vc.surveyDelegate = self
        present(OWSNavigationController(rootViewController: vc), animated: true)
    }

    private enum Item: Hashable {
        case audio
        case audioStuttering
        case audioLocalEcho
        case audioRemoteEcho
        case audioDrop
        case video
        case videoNoCamera
        case videoLowQuality
        case videoLowResolution
        case callDropped
        case other

        var title: String {
            switch self {
            case .audio:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_AUDIO",
                    comment: "Label for audio issue option in call quality survey"
                )
            case .audioStuttering:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_AUDIO_STUTTERING",
                    comment: "Label for audio stuttering issue option in call quality survey"
                )
            case .audioLocalEcho:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_AUDIO_LOCAL_ECHO",
                    comment: "Label for local echo issue option in call quality survey, indicating the user heard an echo"
                )
            case .audioRemoteEcho:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_AUDIO_REMOTE_ECHO",
                    comment: "Label for remote echo issue option in call quality survey, indicating other participants heard an echo"
                )
            case .audioDrop:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_AUDIO_DROP",
                    comment: "Label for audio dropout issue option in call quality survey"
                )
            case .video:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_VIDEO",
                    comment: "Label for video issue option in call quality survey"
                )
            case .videoNoCamera:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_VIDEO_NO_CAMERA",
                    comment: "Label for camera not working issue option in call quality survey"
                )
            case .videoLowQuality:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_VIDEO_LOW_QUALITY",
                    comment: "Label for poor video quality issue option in call quality survey"
                )
            case .videoLowResolution:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_VIDEO_LOW_RESOLUTION",
                    comment: "Label for low resolution video issue option in call quality survey"
                )
            case .callDropped:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_CALL_DROPPED",
                    comment: "Label for call dropped issue option in call quality survey"
                )
            case .other:
                OWSLocalizedString(
                    "CALL_QUALITY_SURVEY_ISSUE_OTHER",
                    comment: "Label for custom issue option in call quality survey"
                )
            }
        }

        var image: ImageResource {
            switch self {
            case .audio, .audioStuttering, .audioLocalEcho, .audioRemoteEcho, .audioDrop:
                    .speaker
            case .video, .videoNoCamera, .videoLowQuality, .videoLowResolution:
                    .video
            case .callDropped:
                    .xCircle
            case .other:
                    .errorCircle
            }
        }
    }

    private enum Section: Hashable {
        case main
    }
}

// MARK: - CallQualitySurveyCustomIssueViewController.Delegate

extension CallQualitySurveyIssuesViewController: CallQualitySurveyCustomIssueViewController.Delegate {
    func didEnterCustomIssue(_ issue: String) {
        self.customIssue = issue
    }
}

// MARK: - UICollectionViewDelegate

extension CallQualitySurveyIssuesViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
        self.selectedItems.insert(item)
        self.updateSnapshot()
        self.updateViewState()
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let item = dataSource?.itemIdentifier(for: indexPath) else { return }
        self.selectedItems.remove(item)
        self.updateSnapshot()
        self.updateViewState()
    }
}

// MARK: - CapsuleCell

private final class CapsuleCell: UICollectionViewCell {

    private let hStack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    private var icon: ImageResource?

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 6
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = .init(hMargin: 10, vMargin: 6)

        iconView.contentMode = .scaleAspectFit
        iconView.autoSetDimensions(to: .square(20))

        titleLabel.font = .dynamicTypeSubheadline

        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()
        hStack.addArrangedSubviews([iconView, titleLabel])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, image: ImageResource) {
        titleLabel.text = title
        icon = image
        updateAppearance()
    }

    private func updateAppearance() {
        if isSelected {
            iconView.image = UIImage(resource: .check20)
        } else {
            iconView.image = self.icon.map(UIImage.init(resource:))
        }

        if isHighlighted {
            contentView.backgroundColor = .tertiarySystemFill
            titleLabel.textColor = .Signal.label
            iconView.tintColor = .Signal.label
        } else if isSelected {
            contentView.backgroundColor = .Signal.accent
            titleLabel.textColor = .white
            iconView.tintColor =  .white
        } else {
            contentView.backgroundColor = .Signal.secondaryGroupedBackground
            titleLabel.textColor = .Signal.label
            iconView.tintColor = .Signal.label
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = height / 2
        layer.masksToBounds = true
    }
}

// MARK: - CenteredFlowLayout

private final class CenteredFlowLayout: UICollectionViewFlowLayout {
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard
            let attributes = super.layoutAttributesForElements(in: rect)?
                .map({ $0.copy() as! UICollectionViewLayoutAttributes }),
            let collectionView = collectionView
        else {
            return super.layoutAttributesForElements(in: rect)
        }

        // UICollectionViewFlowLayout is already figuring out what items can fit
        // on each row in the above super call, but it places them on the outer
        // edges. We need to place the items horizontally-centered.

        let rows = groupByRow(attributes: attributes)

        let availableWidth = collectionView.bounds.width - collectionView.contentInset.totalWidth

        for row in rows {
            let totalItemsWidth = row.map(\.frame.width).reduce(0, +)
            let totalSpacing = CGFloat(max(row.count - 1, 0)) * minimumInteritemSpacing
            let rowWidth = totalItemsWidth + totalSpacing

            let inset = max((availableWidth - rowWidth) / 2, 0)

            var x = inset
            for attribute in row {
                attribute.frame.x = x
                x += attribute.frame.width + minimumInteritemSpacing
            }
        }

        return attributes
    }

    private func groupByRow(attributes: [UICollectionViewLayoutAttributes]) -> [[UICollectionViewLayoutAttributes]] {
        // Sort by y then x
        let sorted = attributes
            .filter { $0.representedElementCategory == .cell }
            .sorted {
                if abs($0.frame.minY - $1.frame.minY) > 1 {
                    return $0.frame.minY < $1.frame.minY
                } else {
                    return $0.frame.minX < $1.frame.minX
                }
            }

        var rows: [[UICollectionViewLayoutAttributes]] = []
        var currentRow: [UICollectionViewLayoutAttributes] = []
        var currentY = sorted.first?.frame.minY ?? -CGFloat.greatestFiniteMagnitude

        for attribute in sorted {
            if attribute.frame.minY.fuzzyEquals(currentY) {
                currentRow.append(attribute)
            } else {
                // New row
                rows.append(currentRow)
                currentRow = [attribute]
                currentY = attribute.frame.minY
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
}
