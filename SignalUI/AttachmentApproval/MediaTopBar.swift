//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class MediaTopBar: UIView {

    // Custom layout guide is necessary to allow to adjust the top margin.
    // Usually one could just change layoutMargins.top but that approach
    // sometimes doesn't work for this view because top inset gets overridden by UIKit
    // since `preservesSuperviewLayoutMargins` is set to `true`.
    public let controlsLayoutGuide = UILayoutGuide()

    override public init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        translatesAutoresizingMaskIntoConstraints = false

        // Put controls as high up as possible. VC can change this later if
        // custom spacing is needed (eg Camera view).
        directionalLayoutMargins.top = 0

        installConstraints()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installConstraints() {
        addLayoutGuide(controlsLayoutGuide)

        let otherLayoutGuide: UILayoutGuide = if #available(iOS 26, *) {
            // Avoids stoplight buttons in windowed mode on iPad.
            layoutGuide(for: .margins(cornerAdaptation: .vertical))
        } else {
            layoutMarginsGuide
        }

        NSLayoutConstraint.activate([
            controlsLayoutGuide.topAnchor.constraint(equalTo: otherLayoutGuide.topAnchor),
            controlsLayoutGuide.leadingAnchor.constraint(equalTo: otherLayoutGuide.leadingAnchor),
            controlsLayoutGuide.trailingAnchor.constraint(equalTo: otherLayoutGuide.trailingAnchor),
            controlsLayoutGuide.bottomAnchor.constraint(equalTo: otherLayoutGuide.bottomAnchor),
        ])
    }

    public func install(in view: UIView) {
        view.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: view.topAnchor),
            leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
