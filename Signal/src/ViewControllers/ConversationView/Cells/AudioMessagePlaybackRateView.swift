//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

// MARK: - AudioPlaybackRate

enum AudioPlaybackRate: Float {
    case slow = 0.5
    case normal = 1
    case fast = 1.5
    case extraFast = 2
}

// MARK: - AudioMessagePlaybackRateView

class AudioMessagePlaybackRateView: ManualLayoutViewWithLayer {

    private let threadUniqueId: String
    private let audioAttachment: AudioAttachment
    private let isIncoming: Bool

    private var playbackRate: AudioPlaybackRate

    private let label = CVLabel()
    private let imageView = CVImageView()

    init(
        threadUniqueId: String,
        audioAttachment: AudioAttachment,
        playbackRate: AudioPlaybackRate,
        isIncoming: Bool
    ) {
        self.threadUniqueId = threadUniqueId
        self.audioAttachment = audioAttachment
        self.isIncoming = isIncoming
        self.playbackRate = playbackRate
        super.init(name: "AudioMessagePlaybackRateView")

        // layoutBlocks get called once per frame change.
        // no need to set one up per subview added, just
        // have a single block that triggers an update to
        // the frames of all the subviews.
        addSubview(imageView)
        addSubview(label, withLayoutBlock: { [weak self] _ in
            self?.setSubviewFrames()
        })

        // start invisible
        self.alpha = 0
        self.backgroundColor = _backgroundColor
        self.layer.cornerRadius = Constants.cornerRadius

        Self.playbackRateLabelConfig(
            playbackRate: playbackRate,
            color: textColor
        ).applyForRendering(label: label)
        self.imageView.image = Constants.image?.asTintedImage(color: textColor)
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    // MARK: - Animating Changes

    private var isVisible: Bool = false {
        didSet {
            self.alpha = isVisible ? 1 : 0
        }
    }
    private var isAnimatingVisibility: Bool?

    public func setVisibility(
        _ visible: Bool,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        // NOTE: can't use `isHidden` state because ManualStackView gets
        // unhappy if one of its subviews hides. Use alpha instead.
        guard isVisible != visible, isAnimatingVisibility != visible else {
            completion?()
            return
        }

        let fromScale = CATransform3DScale(
            CATransform3DIdentity,
            visible ? 0 : 1,
            visible ? 0 : 1,
            1
        )
        let toScale = CATransform3DScale(
            CATransform3DIdentity,
            visible ? 1 : 0,
            visible ? 1 : 0,
            1
        )
        layer.transform = toScale

        let wrappedCompletion = {
            self.isAnimatingVisibility = nil
            self.isVisible = visible
            completion?()
        }

        guard animated else {
            wrappedCompletion()
            return
        }

        // Make it visible so we can see the animation.
        isVisible = true
        isAnimatingVisibility = visible

        CATransaction.begin()
        layer.removeAnimation(forKey: Constants.animationName)

        let animation = Self.createSpringAnimation()
        animation.fillMode = .forwards
        animation.fromValue = fromScale
        animation.toValue = toScale

        CATransaction.setCompletionBlock(wrappedCompletion)
        layer.add(animation, forKey: Constants.animationName)
        CATransaction.commit()
    }

    public func setPlaybackRate(
        _ playbackRate: AudioPlaybackRate,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        guard self.playbackRate != playbackRate else {
            completion?()
            return
        }
        self.playbackRate = playbackRate

        let setContent = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.setSubviewFrames()
            Self.playbackRateLabelConfig(
                playbackRate: strongSelf.playbackRate,
                color: strongSelf.textColor
            ).applyForRendering(label: strongSelf.label)
        }

        // Don't interrupt the appearance animation.
        guard animated, self.isVisible, self.isAnimatingVisibility == nil else {
            setContent()
            completion?()
            return
        }

        CATransaction.begin()
        layer.removeAnimation(forKey: Constants.animationName)

        let animation = Self.createSpringAnimation()
        let fromScale = CATransform3DScale(
            CATransform3DIdentity,
            1,
            1,
            1
        )
        animation.fromValue = fromScale
        let toScale = CATransform3DScale(
            CATransform3DIdentity,
            Constants.changeAnimationScale,
            Constants.changeAnimationScale,
            1
        )
        animation.toValue = toScale
        animation.autoreverses = true

        CATransaction.setCompletionBlock {
            completion?()
        }
        layer.add(animation, forKey: Constants.animationName)
        CATransaction.commit()

        // Schedule the actual text update to happen halfway through,
        // right at the reversal point.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.animationDuration,
            execute: setContent
        )
        return
    }

    private static func createSpringAnimation() -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: "transform")
        animation.damping = Constants.animationDamping
        animation.stiffness = Constants.animationStiffness
        animation.mass = Constants.animationMass
        animation.duration = Constants.animationDuration
        animation.speed = Constants.animationSpeed
        return animation
    }

    // MARK: - Tapping

    public func handleTap(
        sender: UITapGestureRecognizer,
        itemModel: CVItemModel,
        componentDelegate: CVComponentDelegate?
    ) -> Bool {
        guard
            let attachmentId = audioAttachment.attachmentStream?.uniqueId,
            cvAudioPlayer.audioPlaybackState(forAttachmentId: attachmentId) == .playing
        else {
            return false
        }
        // Check that the tap is within the bounding box, but
        // expand that to a minimum height/width if its too small.
        let location = sender.location(in: self)
        let tapTargetBounds = bounds.insetBy(
            dx: -0.5 * max(0, Constants.minTapTargetSize - bounds.width),
            dy: -0.5 * max(0, Constants.minTapTargetSize - bounds.height)
        )
        guard tapTargetBounds.contains(location) else {
            return false
        }
        let newPlaybackRate = playbackRate.next
        self.cvAudioPlayer.setPlaybackRate(newPlaybackRate.rawValue, forThreadUniqueId: threadUniqueId)

        // Hold off updates until we animate the change.
        let animationCompletion = componentDelegate?.cvc_beginCellAnimation(
            maximumDuration: Constants.maxAnimationDuration
        )

        let reloadGroup = DispatchGroup()

        // First write the update to the db, this persists the change and ensures the
        // reload we do afterwards pulls the updated rate.
        reloadGroup.enter()
        itemModel.databaseStorage.asyncWrite(
            block: {
                itemModel.threadAssociatedData.updateWith(
                    audioPlaybackRate: newPlaybackRate.rawValue,
                    updateStorageService: true,
                    transaction: $0
                )
            },
            completion: {
                reloadGroup.leave()
            })

        // Trigger the animation which also updates the playback rate value.
        reloadGroup.enter()
        setPlaybackRate(newPlaybackRate) {
            reloadGroup.leave()
            animationCompletion?()
        }

        reloadGroup.notify(queue: .main) { [weak componentDelegate] in
            // Once the animation _and_ the db update complete, issue a reload.
            // This reloads _everything_, which is way overkill, but there's no easy way
            // to reload only ThreadAssociatedData without a heavy refactor.
            // This only happens on direct user input, anyway, so its probably not a
            // big deal since it therefore only happens on human timescales.
            componentDelegate?.cvc_enqueueReloadWithoutCaches()
        }

        return true
    }

    // MARK: - Sizing

    public static func measure(maxWidth: CGFloat) -> CGSize {
        // Always size this view for the max playback rate size.
        let labelConfig = Self.playbackRateLabelConfig(
            playbackRate: AudioPlaybackRate.rateForLargestDisplayText,
            color: .white // Color doesn't matter for sizing.
        )
        let nonLabelWidth = Constants.imageSize + Constants.margins.totalWidth
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: maxWidth - nonLabelWidth)

        let height = Constants.margins.totalHeight + max(labelSize.height, Constants.imageSize)

        return CGSize(
            width: labelSize.width + nonLabelWidth,
            height: height
        )
    }

    // MARK: - Laying out subviews

    private func setSubviewFrames() {
        let labelConfig = Self.playbackRateLabelConfig(
            playbackRate: playbackRate,
            color: .white // Color doesn't matter for sizing.
        )
        let labelSize = CVText.measureLabel(
            config: labelConfig,
            maxWidth: bounds.width
        )
        let labelWidth = labelSize.width
        let imageSize = Constants.imageSize

        // We want the label and image as a whole to be centered,
        // so pad each side with remaining width equally.
        let contentWidth = labelWidth + imageSize
        let sidePadding = (bounds.width - contentWidth) / 2

        label.frame = CGRect(
            x: sidePadding,
            y: (bounds.height - labelSize.height) / 2,
            width: labelWidth,
            height: labelSize.height
        )
        imageView.frame = CGRect(
            x: sidePadding + labelWidth,
            y: (bounds.height - imageSize) / 2,
            width: imageSize,
            height: imageSize
        )
    }

    // MARK: - Colors

    private lazy var _backgroundColor = isIncoming
        ? (Theme.isDarkThemeEnabled ? UIColor.ows_white : .ows_black).withAlphaComponent(0.08)
        : UIColor.ows_whiteAlpha20

    private lazy var textColor: UIColor = isIncoming
        ? (Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray60)
        : .ows_white

    // MARK: - Configs

    private static func playbackRateLabelConfig(
        playbackRate: AudioPlaybackRate,
        color: UIColor
    ) -> CVLabelConfig {
        let text = playbackRate.displayText
        // Limit the max font size to avoid overlap.
        var font = Constants.font
        if font.pointSize > Constants.maxFontSize {
            font = font.withSize(Constants.maxFontSize)
        }
        font = font.ows_semibold
        return CVLabelConfig(
            text: text,
            font: font,
            textColor: color,
            textAlignment: .right
        )
    }

    fileprivate enum Constants {
        static let cornerRadius: CGFloat = 6
        static var font: UIFont { UIFont.ows_dynamicTypeFootnote }
        static let maxFontSize: CGFloat = 20

        static var imageSize: CGFloat {
            switch UIApplication.shared.preferredContentSizeCategory {
            case .extraSmall, .small, .medium, .large, .extraLarge:
                return 10
            default:
                return 16
            }
        }
        static var image: UIImage? {
            switch UIApplication.shared.preferredContentSizeCategory {
            case .extraSmall, .small, .medium, .large, .extraLarge:
                return UIImage(named: "x-10")
            default:
                return UIImage(named: "x-16")
            }
        }
        static let margins = UIEdgeInsets(hMargin: 8, vMargin: 2)

        static let animationName = "scale"
        static let animationDuration: TimeInterval = 0.15
        static let animationDamping: CGFloat = 1.15
        static let animationStiffness: CGFloat = 100
        static let animationMass: CGFloat = 1
        static let animationSpeed: Float = 1
        static let changeAnimationScale: CGFloat = 1.3

        static var maxAnimationDuration: TimeInterval {
            return animationDuration * 2 // 2x for autoreverse
        }

        static let minTapTargetSize: CGFloat = 44
    }
}

// MARK: - AudioPlaybackRate extension

extension AudioPlaybackRate {
    init(rawValue: Float) {
        switch rawValue {
        case _ where rawValue <= 0.5:
            self = .slow
        case _ where rawValue < 1.5:
            self = .normal
        case _ where rawValue < 2:
            self = .fast
        default:
            self = .extraFast
        }
    }

    var next: AudioPlaybackRate {
        switch self {
        case .slow:
            return .normal
        case .normal:
            return .fast
        case .fast:
            return .extraFast
        case .extraFast:
            return .slow
        }
    }

    var displayText: String {
        // Instead of dealing with float formatting, just
        // hardcode since there's only 4 cases anyway.
        switch self {
        case .slow:
            return LocalizationNotNeeded(".5")
        case .normal:
            return LocalizationNotNeeded("1")
        case .fast:
            return LocalizationNotNeeded("1.5")
        case .extraFast:
            return LocalizationNotNeeded("2")
        }
    }

    static var rateForLargestDisplayText: AudioPlaybackRate {
        return .fast
    }
}
