//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

/// This is the collection view cell for "list mode" in All Media.
class WidePhotoCell: MediaTileListModeCell {
    static let reuseIdentifier = "WidePhotoCell"

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
        label.textColor = .secondaryLabel
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        willSetupViews()

        contentView.addSubview(imageView)
        contentView.addSubview(filenameSenderView)
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
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

            separator.leadingAnchor.constraint(equalTo: filenameSenderView.leadingAnchor)
        ])

        let constraintWithSelectionButton = imageView.leadingAnchor.constraint(equalTo: selectionButton.trailingAnchor, constant: 13)
        let constraintWithoutSelectionButton = imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)

        super.setupViews(constraintWithSelectionButton: constraintWithSelectionButton,
                         constraintWithoutSelectionButton: constraintWithoutSelectionButton)
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        imageView.image = nil
    }

    private func setUpAccessibility(item: PhotoGridItem?) {
        self.isAccessibilityElement = true

        if let item {
            self.accessibilityLabel = [
                item.type.localizedString,
                MediaTileDateFormatter.formattedDateString(for: item.mediaMetadata?.creationDate)
            ]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else {
            self.accessibilityLabel = ""
        }
    }

    override public func makePlaceholder() {
        imageView.image = nil
        setUpAccessibility(item: nil)
    }

    override public func configure(item allMediaItem: AllMediaItem, spoilerReveal: SpoilerRevealState) {
        switch allMediaItem {
        case .graphic(let photoGridItem):
            super.configure(item: .graphic(photoGridItem), spoilerReveal: spoilerReveal)
            reallyConfigure(photoGridItem)
        default:
            owsFail("Unexpected item type \(allMediaItem)")
        }
    }

    private var photoGridItem: PhotoGridItem? {
        switch item {
        case .graphic(let result):
            return result
        case .none:
            return nil
        default:
            return nil
        }
    }

    private func reallyConfigure(_ item: PhotoGridItem) {
        // PHCachingImageManager returns multiple progressively better
        // thumbnails in the async block. We want to avoid calling
        // `configure(item:)` multiple times because the high-quality image eventually applied
        // last time it was called will be momentarily replaced by a progression of lower
        // quality images.
        imageView.image = item.asyncThumbnail { [weak self] image in
            guard let self else { return }

            guard let currentItem = self.photoGridItem else {
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

        if let metadata = item.mediaMetadata {
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

    override func mediaPresentationContext(collectionView: UICollectionView,
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
}

extension MediaMetadata {
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
                                               name: .themeDidChange,
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

        middleDotLabel.setContentHuggingHorizontalHigh()
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
    private func themeDidChange() {
        filenameLabel.textColor = Theme.primaryTextColor
        middleDotLabel.textColor = Theme.primaryTextColor
        senderNameLabel.textColor = Theme.primaryTextColor
    }
}
