//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// The initial presentation is intended to be indistinguishable from the Launch Screen.
// After a delay we present some "loading" UI so the user doesn't think the app is frozen.
@objc
public class LoadingViewController: UIViewController {

    var logoView: UIImageView!
    var topLabel: UILabel!
    var bottomLabel: UILabel!

    override public func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.ows_materialBlue

        self.logoView = UIImageView(image: #imageLiteral(resourceName: "logoSignal"))
        view.addSubview(logoView)

        logoView.autoCenterInSuperview()
        logoView.autoPinToSquareAspectRatio()
        logoView.autoMatch(.width, to: .width, of: view, withMultiplier: 1/3)

        self.topLabel = buildLabel()
        topLabel.alpha = 0
        topLabel.font = UIFont.ows_dynamicTypeTitle2
        topLabel.text = NSLocalizedString("DATABASE_VIEW_OVERLAY_TITLE", comment: "Title shown while the app is updating its database.")

        self.bottomLabel = buildLabel()
        bottomLabel.alpha = 0
        bottomLabel.font = UIFont.ows_dynamicTypeBody
        bottomLabel.text = NSLocalizedString("DATABASE_VIEW_OVERLAY_SUBTITLE", comment: "Subtitle shown while the app is updating its database.")

        let labelStack = UIStackView(arrangedSubviews: [topLabel, bottomLabel])
        labelStack.axis = .vertical
        labelStack.alignment = .center
        labelStack.spacing = 8
        view.addSubview(labelStack)

        labelStack.autoPinEdge(.top, to: .bottom, of: logoView, withOffset: 20)
        labelStack.autoPinLeadingToSuperviewMargin()
        labelStack.autoPinTrailingToSuperviewMargin()
        labelStack.setCompressionResistanceHigh()
        labelStack.setContentHuggingHigh()
    }

    var isShowingTopLabel = false
    var isShowingBottomLabel = false
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // We only show the "loading" UI if it's a slow launch. Otherwise this ViewController
        // should be indistinguishable from the launch screen.
        let kTopLabelThreshold: TimeInterval = 5
        DispatchQueue.main.asyncAfter(deadline: .now() + kTopLabelThreshold) { [weak self] in
            guard let strongSelf = self else {
                return
            }

            guard !strongSelf.isShowingTopLabel else {
                return
            }

            strongSelf.isShowingTopLabel = true
            UIView.animate(withDuration: 0.1) {
                strongSelf.topLabel.alpha = 1
            }
            UIView.animate(withDuration: 0.9, delay: 2, options: [.autoreverse, .repeat, .curveEaseInOut], animations: {
                strongSelf.topLabel.alpha = 0.2
            }, completion: nil)
        }

        let kBottomLabelThreshold: TimeInterval = 15
        DispatchQueue.main.asyncAfter(deadline: .now() + kBottomLabelThreshold) { [weak self] in
            guard let strongSelf = self else {
                return
            }
            guard !strongSelf.isShowingBottomLabel else {
                return
            }

            strongSelf.isShowingBottomLabel = true
            UIView.animate(withDuration: 0.1) {
                strongSelf.bottomLabel.alpha = 1
            }
        }
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: 

    private func buildLabel() -> UILabel {
        let label = UILabel()

        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        return label
    }
}
