//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
class WidePhotoCellSeparator: UIView { }

/// This is the collection view cell for "list mode" in All Media.
class WidePhotoCell: UICollectionViewCell, MediaTileCell {
    static let reuseIdentifier = "WidePhotoCell"
    var item: PhotoGridItem?

    // This determines whether corners are rounded.
    private var isFirstInGroup: Bool = false
    private var isLastInGroup: Bool = false

    // We have to mess with constraints when toggling selection mode.
    private var imageViewLeadingConstraintWithSelectionButton: NSLayoutConstraint!
    private var imageViewLeadingConstraintWithoutSelectionButton: NSLayoutConstraint!

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    /// Wraps two text views. It shows "Filename * Sender Name".
    private let filenameSenderView: FilenameSenderView = {
        let view = FilenameSenderView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13, *) {
            label.textColor = .secondaryLabel
        } else {
            label.textColor = .ows_gray45
        }
        return label
    }()

    /// Since UICollectionView doesn't support separators, we have to do it ourselves. Show the
    /// separator at the bottom of each item except when last in a section.
    private let separator: WidePhotoCellSeparator = {
        let view = WidePhotoCellSeparator()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderWidth = 1.0
        if #available(iOS 13, *) {
            view.layer.borderColor = UIColor.separator.cgColor
        } else {
            view.layer.borderColor = UIColor(rgbHex: 0x3c3c43).withAlphaComponent(0.3).cgColor
        }
        return view
    }()

    private let selectionButton: SelectionButton = {
        SelectionButton()
    }()

    private let selectedMaskView = UIView()

    // TODO(george): This will change when dynamic text support is added.
    static let desiredHeight = 64.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var desiredSelectionOutlineColor: UIColor {
        return UIColor.ows_gray20
    }

    @available(iOS 13.0, *)
    private var dynamicDesiredSelectionOutlineColor: UIColor {
        return UIColor { _ in
            Theme.isDarkThemeEnabled ? UIColor.ows_gray25 : UIColor.ows_gray20
        }
    }

    private lazy var selectionMaskColor: UIColor = {
        if #available(iOS 13, *) {
            return UIColor { _ in
                Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray15
            }
        } else {
            return .ows_gray15
        }
    }()

    private func setupViews() {
        selectedMaskView.alpha = 0.3
        selectedMaskView.backgroundColor = selectionMaskColor
        selectedMaskView.isHidden = true

        contentView.addSubview(selectedMaskView)
        contentView.addSubview(imageView)
        contentView.addSubview(filenameSenderView)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(selectionButton)
        contentView.addSubview(separator)

        if #available(iOS 13.0, *) {
            selectionButton.outlineColor = dynamicDesiredSelectionOutlineColor
            contentView.backgroundColor = UIColor(dynamicProvider: { _ in
                Theme.isDarkThemeEnabled ? .ows_gray80 : .white
            })
        } else {
            selectionButton.outlineColor = desiredSelectionOutlineColor
            contentView.backgroundColor = .white
        }

        imageViewLeadingConstraintWithSelectionButton = imageView.leadingAnchor.constraint(equalTo: selectionButton.trailingAnchor, constant: 13)
        imageViewLeadingConstraintWithoutSelectionButton = imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)

        NSLayoutConstraint.activate([
            selectionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            selectionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionButton.widthAnchor.constraint(equalToConstant: 24),
            selectionButton.heightAnchor.constraint(equalToConstant: 24),

            imageViewLeadingConstraintWithoutSelectionButton,
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            filenameSenderView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            filenameSenderView.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 19),
            filenameSenderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: filenameSenderView.bottomAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: filenameSenderView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -13),

            separator.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
            separator.heightAnchor.constraint(equalToConstant: 0.33),
            separator.leadingAnchor.constraint(equalTo: filenameSenderView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        selectedMaskView.autoPinEdgesToSuperviewEdges()
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        imageView.image = nil
        selectedMaskView.isHidden = true
        selectionButton.reset()
    }

    func indexPathDidChange(_ indexPath: IndexPath, itemCount: Int) {
        isFirstInGroup = (indexPath.item == 0)
        isLastInGroup = (indexPath.item + 1 == itemCount)

        let topCorners = isFirstInGroup ? [CACornerMask.layerMinXMinYCorner, CACornerMask.layerMaxXMinYCorner] : []
        let bottomCorners = isLastInGroup ? [CACornerMask.layerMinXMaxYCorner, CACornerMask.layerMaxXMaxYCorner] : []
        let corners = topCorners + bottomCorners

        let radius = CGFloat(10.0)
        contentView.layer.maskedCorners = CACornerMask(corners)
        contentView.layer.cornerRadius = radius

        selectedMaskView.layer.maskedCorners = CACornerMask(corners)
        selectedMaskView.layer.cornerRadius = radius

        separator.isHidden = isLastInGroup
    }

    private func setUpAccessibility(item: PhotoGridItem?) {
        self.isAccessibilityElement = true

        if let item {
            self.accessibilityLabel = [
                item.type.localizedString,
                MediaTileDateFormatter.formattedDateString(for: item.photoMetadata?.creationDate)
            ]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else {
            self.accessibilityLabel = ""
        }
    }

    public func makePlaceholder() {
        imageView.image = nil
        setUpAccessibility(item: nil)
    }

    public func configure(item: PhotoGridItem) {
        self.item = item

        // PHCachingImageManager returns multiple progressively better
        // thumbnails in the async block. We want to avoid calling
        // `configure(item:)` multiple times because the high-quality image eventually applied
        // last time it was called will be momentarily replaced by a progression of lower
        // quality images.
        imageView.image = item.asyncThumbnail { [weak self] image in
            guard let self else { return }

            guard let currentItem = self.item else {
                return
            }

            guard currentItem === item else {
                return
            }

            if image == nil {
                Logger.debug("image == nil")
            }
            self.imageView.image = image
        }

        if let metadata = item.photoMetadata {
            filenameSenderView.filename = metadata.filename
            if filenameSenderView.filename == nil {
                filenameSenderView.senderName = metadata.sender
            } else {
                filenameSenderView.senderName = metadata.abbreviatedSender
            }

            if let date = metadata.formattedDate {
                subtitleLabel.text = "\(metadata.formattedSize) · \(item.type.formattedType) · \(date)"
            } else {
                subtitleLabel.text = "\(metadata.formattedSize) · \(item.type.formattedType)"
            }
        } else {
            filenameSenderView.filename = nil
            filenameSenderView.senderName = nil
            subtitleLabel.text = ""
        }
        setUpAccessibility(item: item)
    }

    func mediaPresentationContext(collectionView: UICollectionView,
                                  in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard let mediaSuperview = imageView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(imageView.frame, from: mediaSuperview)
        let clippingAreaInsets = UIEdgeInsets(top: collectionView.adjustedContentInset.top, leading: 0, bottom: 0, trailing: 0)

        return MediaPresentationContext(
            mediaView: imageView,
            presentationFrame: presentationFrame,
            clippingAreaInsets: clippingAreaInsets
        )
    }

    private var _allowsMultipleSelection = false
    var allowsMultipleSelection: Bool { _allowsMultipleSelection }

    func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool) {
        _allowsMultipleSelection = allowed
        updateSelectionState(animated: animated)
    }

    override public var isSelected: Bool {
        didSet {
            updateSelectionState(animated: false)
        }
    }

    private func updateSelectionState(animated: Bool) {
        selectedMaskView.isHidden = !isSelected
        selectionButton.isSelected = isSelected
        if !_allowsMultipleSelection {
            selectionButton.allowsMultipleSelection = false
        }
        if animated {
            UIView.animate(withDuration: 0.15) {
                self.updateLayoutForSelectionStateChange()
            } completion: { _ in
                self.didUpdateLayoutForSelectionStateChange()
            }
        } else {
            updateLayoutForSelectionStateChange()
            didUpdateLayoutForSelectionStateChange()
        }
    }

    private func updateLayoutForSelectionStateChange() {
        if _allowsMultipleSelection {
            NSLayoutConstraint.deactivate([self.imageViewLeadingConstraintWithoutSelectionButton])
            NSLayoutConstraint.activate([self.imageViewLeadingConstraintWithSelectionButton])
        } else {
            NSLayoutConstraint.deactivate([self.imageViewLeadingConstraintWithSelectionButton])
            NSLayoutConstraint.activate([self.imageViewLeadingConstraintWithoutSelectionButton])
        }
        self.layoutIfNeeded()
    }

    private func didUpdateLayoutForSelectionStateChange() {
        if _allowsMultipleSelection {
            self.selectionButton.allowsMultipleSelection = true
        }
    }
}

extension PhotoMetadata {
    var formattedSize: String {
        let byteCount = Int64(byteSize)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    var formattedDate: String? {
        guard let creationDate else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale.current
        return dateFormatter.string(from: creationDate)
    }
}

class FilenameSenderView: UIView {
    var filename: String? {
        didSet {
            filenameLabel.text = filename ?? ""
            updateLabelsVisibility()
        }
    }

    var senderName: String? {
        didSet {
            senderNameLabel.text = senderName ?? ""
            updateLabelsVisibility()
        }
    }

    private let filenameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = Theme.primaryTextColor
        return label
    }()

    private let middleDotLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = " · "
        label.textColor = Theme.primaryTextColor
        return label
    }()

    private let senderNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = Theme.primaryTextColor
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupLabels()
        setupConstraints()
        updateLabelsVisibility()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLabels() {
        addSubview(filenameLabel)
        addSubview(middleDotLabel)
        addSubview(senderNameLabel)
    }

    private lazy var senderLabelToMiddleDotLeadingConstraint: NSLayoutConstraint = {
        senderNameLabel.leadingAnchor.constraint(equalTo: middleDotLabel.trailingAnchor)
    }()
    private lazy var senderLabelToSuperviewLeadingConstraint: NSLayoutConstraint = {
        senderNameLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor)
    }()

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            filenameLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            filenameLabel.topAnchor.constraint(equalTo: self.topAnchor),
            filenameLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            middleDotLabel.leadingAnchor.constraint(equalTo: filenameLabel.trailingAnchor),
            middleDotLabel.topAnchor.constraint(equalTo: self.topAnchor),
            middleDotLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            senderNameLabel.topAnchor.constraint(equalTo: self.topAnchor),
            senderNameLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            senderNameLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])

        filenameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func updateLabelsVisibility() {
        if senderName == nil && filename == nil {
            // Have nothing to show
            middleDotLabel.isHidden = true
            senderNameLabel.isHidden = true
            filenameLabel.isHidden = true
        } else if senderName != nil && filename != nil {
            // Have both
            senderNameLabel.isHidden = false
            middleDotLabel.isHidden = false
            filenameLabel.isHidden = false

            NSLayoutConstraint.deactivate([
                senderLabelToSuperviewLeadingConstraint
            ])
            NSLayoutConstraint.activate([
                senderLabelToMiddleDotLeadingConstraint
            ])
        } else {
            // Show only the sender name. You'd get here if there was a filename but no sender name, but that isn't supported.
            senderNameLabel.isHidden = false
            middleDotLabel.isHidden = true
            filenameLabel.isHidden = true

            NSLayoutConstraint.deactivate([
                senderLabelToMiddleDotLeadingConstraint
            ])
            NSLayoutConstraint.activate([
                senderLabelToSuperviewLeadingConstraint
            ])
        }
    }

    @objc
    func themeDidChange() {
        filenameLabel.textColor = Theme.primaryTextColor
        middleDotLabel.textColor = Theme.primaryTextColor
        senderNameLabel.textColor = Theme.primaryTextColor
    }
}
