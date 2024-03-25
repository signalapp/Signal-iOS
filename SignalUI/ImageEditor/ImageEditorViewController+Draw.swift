//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

// MARK: - Draw Tool

extension ImageEditorViewController {

    private func initializeDrawToolUIIfNecessary() {
        guard !drawToolUIInitialized else { return }

        view.addSubview(drawToolbar)
        drawToolbar.autoPinWidthToSuperview()
        drawToolbar.autoPinEdge(.bottom, to: .top, of: bottomBar)

        view.addGestureRecognizer(drawToolGestureRecognizer)

        drawToolUIInitialized = true
    }

    func updateDrawToolControlsVisibility() {
        drawToolbar.alpha = topBar.alpha
        strokeWidthSliderContainer.alpha = topBar.alpha
    }

    func updateDrawToolUIVisibility() {
        let visible = mode == .draw

        if visible {
            initializeDrawToolUIIfNecessary()
        } else {
            guard drawToolUIInitialized else { return }
        }

        drawToolbar.isHidden = !visible
        drawToolGestureRecognizer.isEnabled = visible

        if visible {
            currentStrokeType = drawToolbar.strokeTypeButton.isSelected ? .highlighter : .pen
        }
    }

    static var highligherStrokeOpacity: CGFloat = 0.5

    @objc
    func handleDrawToolGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        owsAssertDebug(mode == .draw, "Incorrect mode [\(mode)]")

        let removeCurrentStroke = {
            if let stroke = self.currentStroke {
                self.model.remove(item: stroke)
            }
            self.currentStroke = nil
            self.currentStrokeSamples.removeAll()
        }
        let tryToAppendStrokeSample = { (locationInView: CGPoint) in
            let view = self.imageEditorView.gestureReferenceView
            let viewBounds = view.bounds
            let newSample = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
                                                                    viewBounds: viewBounds,
                                                                    model: self.model,
                                                                    transform: self.model.currentTransform())

            if let prevSample = self.currentStrokeSamples.last,
                prevSample == newSample {
                // Ignore duplicate samples.
                return
            }
            self.currentStrokeSamples.append(newSample)
        }

        var strokeColor = drawToolbar.colorPickerView.selectedValue.color
        if currentStrokeType == .highlighter {
            strokeColor = strokeColor.withAlphaComponent(Self.highligherStrokeOpacity)
        }
        let unitStrokeWidth = currentStrokeUnitWidth()

        switch gestureRecognizer.state {
        case .began:
            setStrokeWidthSlider(revealed: false)

            removeCurrentStroke()

            // Apply the location history of the gesture so that the stroke reflects
            // the touch's movement before the gesture recognized.
            for location in gestureRecognizer.locationHistory {
                tryToAppendStrokeSample(location)
            }

            let locationInView = gestureRecognizer.location(in: imageEditorView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            let stroke = ImageEditorStrokeItem(color: strokeColor,
                                               strokeType: currentStrokeType,
                                               unitSamples: currentStrokeSamples,
                                               unitStrokeWidth: unitStrokeWidth)
            model.append(item: stroke)
            currentStroke = stroke

        case .changed, .ended:
            let locationInView = gestureRecognizer.location(in: imageEditorView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            guard let lastStroke = self.currentStroke else {
                owsFailDebug("Missing last stroke.")
                removeCurrentStroke()
                return
            }

            // Model items are immutable; we _replace_ the
            // stroke item rather than modify it.
            let stroke = ImageEditorStrokeItem(itemId: lastStroke.itemId,
                                               color: strokeColor,
                                               strokeType: currentStrokeType,
                                               unitSamples: currentStrokeSamples,
                                               unitStrokeWidth: unitStrokeWidth)
            model.replace(item: stroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                currentStroke = nil
                currentStrokeSamples.removeAll()
            } else {
                currentStroke = stroke
            }
        default:
            removeCurrentStroke()
        }
    }

    class DrawToolbar: UIView {

        let colorPickerView: ColorPickerBarView

        let strokeTypeButton = RoundMediaButton(
            image: UIImage(imageLiteralResourceName: "brush-pen"),
            backgroundStyle: .blur
        )

        init(currentColor: ColorPickerBarColor) {
            self.colorPickerView = ColorPickerBarView(currentColor: currentColor)
            super.init(frame: .zero)

            layoutMargins.top = 0
            layoutMargins.bottom = 2

            strokeTypeButton.setImage(UIImage(imageLiteralResourceName: "brush-highlighter"), for: .selected)

            // A container with width capped at a predefined size,
            // centered in superview and constrained to layout margins.
            let stackViewLayoutGuide = UILayoutGuide()
            addLayoutGuide(stackViewLayoutGuide)
            addConstraints([
                stackViewLayoutGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
                stackViewLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
                stackViewLayoutGuide.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                stackViewLayoutGuide.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor) ])
            addConstraint({
                let constraint = stackViewLayoutGuide.widthAnchor.constraint(equalToConstant: ImageEditorViewController.preferredToolbarContentWidth)
                constraint.priority = .defaultHigh
                return constraint
            }())

            // I had to use a custom layout guide because stack view isn't centered
            // but instead has slight offset towards the trailing edge.
            let stackView = UIStackView(arrangedSubviews: [ colorPickerView, strokeTypeButton ])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.alignment = .center
            stackView.spacing = 8
            addSubview(stackView)
            addConstraints([
                stackView.leadingAnchor.constraint(equalTo: stackViewLayoutGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: stackViewLayoutGuide.trailingAnchor,
                                                    constant: strokeTypeButton.layoutMargins.trailing),
                stackView.topAnchor.constraint(equalTo: stackViewLayoutGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: stackViewLayoutGuide.bottomAnchor) ])
        }

        @available(iOS, unavailable, message: "Use init(currentColor:)")
        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
