//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class CallQualitySurveyRatingViewController: CallQualitySurveySheetViewController {
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_RATING_TITLE",
            comment: "Title for the initial rating screen in the call quality survey"
        )

        view.addSubview(stackView)
        // Don't pin the bottom edge because we need to use this view to
        // calculate the height to pass to the sheet presentation controller
        // via customSheetHeight(context:)
        stackView.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.axis = .vertical
        stackView.spacing = 32

        let headerLabel = UILabel()
        headerLabel.text = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_RATING_HEADER",
            comment: "Header text explaining the purpose of the call quality survey"
        )
        headerLabel.font = .dynamicTypeSubheadline
        headerLabel.textColor = .Signal.secondaryLabel
        headerLabel.numberOfLines = 0
        headerLabel.textAlignment = .center
        let header = UIView()
        header.addSubview(headerLabel)
        headerLabel.autoPinEdgesToSuperviewEdges(with: .init(hMargin: 32, vMargin: 0))
        stackView.addArrangedSubview(header)

        let thumbsDown = makeButton(
            image: .thumbsDown,
            tintColor: .Signal.red,
            label: OWSLocalizedString(
                "CALL_QUALITY_SURVEY_HAD_ISSUES_BUTTON",
                comment: "Button label for indicating the call had issues in the call quality survey"
            )
        ) { [weak sheetNav] in
            sheetNav?.didTapHadIssues()
        }
        let thumbsUp = makeButton(
            image: .thumbsUp,
            tintColor: .Signal.ultramarine,
            label: OWSLocalizedString(
                "CALL_QUALITY_SURVEY_GREAT_BUTTON",
                comment: "Button label for indicating the call did not have issues in the call quality survey"
            )
        ) { [weak sheetNav] in
            // [Call Quality Survey] TODO: Pass selected items
            sheetNav?.doneSelectingIssues()
        }

        // Zero-width spacer views with .equalSpacing distribution makes the
        // space between the buttons the same as that on the outer edges.
        let hStack = UIStackView(arrangedSubviews: [
            UIView(),
            thumbsDown,
            thumbsUp,
            UIView(),
        ])
        hStack.axis = .horizontal
        hStack.distribution = .equalSpacing
        hStack.alignment = .top

        stackView.addArrangedSubview(hStack)
    }

    private func makeButton(
        image: ImageResource,
        tintColor: UIColor,
        label text: String,
        action: @escaping () -> Void
    ) -> UIView {
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .Signal.secondaryGroupedBackground

        let button = UIButton(
            configuration: config,
            primaryAction: .init { _ in action() }
        )
        button.autoSetDimensions(to: .square(72))

        let imageView = UIImageView(image: UIImage(resource: image))
        button.addSubview(imageView)
        imageView.autoCenterInSuperview()
        imageView.autoSetDimensions(to: .square(36))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = tintColor
        imageView.isUserInteractionEnabled = false

        let label = UILabel()
        label.text = text
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.label
        label.numberOfLines = 2
        label.textAlignment = .center
        label.autoSetDimension(.width, toSize: 144)

        let stackView = UIStackView(arrangedSubviews: [button, label])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .center
        return stackView
    }

    @available(iOS 16.0, *)
    override func customSheetHeight() -> CGFloat? {
        stackView.bounds.height
    }
}
