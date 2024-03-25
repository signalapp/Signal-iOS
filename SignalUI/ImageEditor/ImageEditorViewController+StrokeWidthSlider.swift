//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

extension ImageEditorViewController {

    func updateStrokeWidthSliderValue() {
        strokeWidthSlider.value = strokeWidthValues[currentStrokeType] ?? 1
        updateStrokeWidthPreviewSize()
    }

    private func setupStrokeWidthPreviewIfNecessary() {
        guard strokeWidthSliderIsTrackingObservation == nil else { return }

        view.addSubview(strokeWidthPreviewDot)
        strokeWidthPreviewDot.autoHCenterInSuperview()
        strokeWidthPreviewDot.autoVCenterInSuperview()

        strokeWidthSliderIsTrackingObservation = strokeWidthSlider.observe(\.isTracking, options: [.new]) { [weak self] _, _ in
            self?.updateStrokeWidthPreviewVisibility()
        }
        updateStrokeWidthPreviewVisibility()
    }

    private func updateStrokeWidthPreviewVisibility() {
        strokeWidthPreviewDot.alpha = strokeWidthSlider.isTracking ? 1 : 0
    }

    func updateStrokeWidthPreviewSize() {
        guard let strokeWidthPreviewDotSize = strokeWidthPreviewDotSize else { return }

        let unitStrokeWidth = currentStrokeUnitWidth()
        let viewSize = imageEditorView.gestureReferenceView.bounds.size
        let strokeWidth = ImageEditorStrokeItem.strokeWidth(forUnitStrokeWidth: unitStrokeWidth,
                                                            dstSize: viewSize)
        var dotSize = max(strokeWidth, 1)
        if currentStrokeType != .blur {
            dotSize += 2 * strokeWidthPreviewDot.layer.borderWidth
        }
        strokeWidthPreviewDotSize.constant = dotSize
    }

    func updateStrokeWidthPreviewColor() {
        switch currentStrokeType {
        case .pen: strokeWidthPreviewDot.backgroundColor = model.color.color
        case .highlighter: strokeWidthPreviewDot.backgroundColor = model.color.color.withAlphaComponent(Self.highligherStrokeOpacity)
        case .blur: strokeWidthPreviewDot.backgroundColor = .white
        }
    }

    @objc
    func strokeTypeButtonTapped(sender: UIButton) {
        owsAssertDebug(currentStroke == nil)
        drawToolbar.strokeTypeButton.isSelected = !drawToolbar.strokeTypeButton.isSelected
        currentStrokeType = drawToolbar.strokeTypeButton.isSelected ? .highlighter : .pen
    }

    @objc
    func handleSliderContainerTap(_ gesture: UITapGestureRecognizer) {
        setStrokeWidthSlider(revealed: !strokeWidthSliderRevealed)

        // Hide slider after delay if user doesn't interact with it.
        if strokeWidthSliderRevealed {
            owsAssertDebug(hideStrokeWidthSliderTimer == nil)

            hideStrokeWidthSliderTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                self.setStrokeWidthSlider(revealed: false)
            }
        }
    }

    @objc
    func handleSliderTouchEvents(slider: UISlider) {
        guard slider.isTracking != strokeWidthSliderRevealed else { return }

        setStrokeWidthSlider(revealed: slider.isTracking)
    }

    @objc
    func handleSliderValueChanged(slider: UISlider) {
        strokeWidthValues[currentStrokeType] = slider.value
        updateStrokeWidthPreviewSize()
    }

    func setStrokeWidthSlider(revealed: Bool) {
        guard strokeWidthSliderRevealed != revealed else { return }

        strokeWidthSliderRevealed = revealed
        updateStrokeWidthSliderPosition()

        if strokeWidthSliderRevealed {
            setupStrokeWidthPreviewIfNecessary()
        }

        if let timer = hideStrokeWidthSliderTimer {
            timer.invalidate()
            hideStrokeWidthSliderTimer = nil
        }
    }

    private func updateStrokeWidthSliderPosition() {
        strokeWidthSliderPosition?.constant = strokeWidthSliderRevealed
        ? strokeWidthSliderContainer.bounds.height/2 - 12
        : 0
        UIView.animate(withDuration: 0.2) {
            if !self.strokeWidthSliderRevealed {
                self.strokeWidthPreviewDot.alpha = 0
            }
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }
}
