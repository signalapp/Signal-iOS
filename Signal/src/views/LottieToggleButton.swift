//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

@objc
class LottieToggleButton: UIButton {
    @objc
    var animationName: String? {
        didSet {
            updateAnimationView()
        }
    }

    @objc
    var animationSize: CGSize = .zero {
        didSet {
            updateAnimationView()
        }
    }

    override var isSelected: Bool {
        didSet {
            animationView?.currentProgress = isSelected ? 1 : 0
        }
    }

    @objc
    func setSelected(_ isSelected: Bool, animated: Bool) {
        AssertIsOnMainThread()
        guard let animationView = animationView else { return owsFailDebug("missing animation view") }

        if animated {
            animationView.play(
                fromProgress: animationView.currentProgress,
                toProgress: isSelected ? 1 : 0,
                loopMode: .playOnce
            ) { [weak self] complete in
                guard complete else { return }
                self?.isSelected = isSelected
            }
        } else {
            self.isSelected = isSelected
        }
    }

    private weak var animationView: AnimationView?
    private func updateAnimationView() {
        animationView?.removeFromSuperview()
        guard let animationName = animationName else { return }

        let animationView = AnimationView(name: animationName)
        self.animationView = animationView

        animationView.isUserInteractionEnabled = false
        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .forceFinish
        animationView.currentProgress = isSelected ? 1 : 0
        animationView.contentMode = .scaleAspectFit

        addSubview(animationView)

        if animationSize != .zero {
            animationView.autoSetDimensions(to: animationSize)
            animationView.autoCenterInSuperview()
        } else {
            animationView.autoPinEdgesToSuperviewEdges()
        }
    }
}
