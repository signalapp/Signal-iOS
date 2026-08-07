//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class ImageAttachmentPrepViewController: AttachmentPrepViewController, ImageEditorViewDelegate {

    private let model: ImageEditorModel
    weak var stickerSheetDelegate: StickerPickerSheetDelegate?

    private lazy var editorView = ImageEditorView(model: model, delegate: self)

    override init?(attachmentApprovalItem: AttachmentApprovalItem) {
        guard let imageEditorModel = attachmentApprovalItem.imageEditorModel else {
            owsFailDebug("imageEditorModel is empty.")
            return nil
        }

        self.model = imageEditorModel

        super.init(attachmentApprovalItem: attachmentApprovalItem)
    }

    override var contentView: UIView {
        editorView
    }

    override func prepareContentView() {
        editorView.hasRoundedCorners = true
        editorView.contentMode = .scaleToFill
        editorView.textInteractionModes = [.tap, .move]
        editorView.configureSubviews()
    }

    override var shouldHideControls: Bool {
        editorView.shouldHideControls || super.shouldHideControls
    }

    override var canSaveMedia: Bool {
        if model.isDirty {
            return true
        }
        return super.canSaveMedia
    }

    // MARK: - Tools

    override func activatePenTool() {
        let viewController = ImageEditorViewController(model: model, stickerSheetDelegate: stickerSheetDelegate)
        presentMediaTool(viewController: viewController)
    }

    override func activateCropTool() {
        guard let srcImage = ImageEditorCanvasView.loadSrcImage(model: model) else {
            owsFailDebug("Couldn't load src image.")
            return
        }

        // We want to render a preview image that "flattens" all of the brush strokes, text items,
        // into the background image without applying the transform (e.g. rotating, etc.), so we
        // use a default transform.
        let previewTransform = ImageEditorTransform.defaultTransform(srcImageSizePixels: model.srcImageSizePixels)
        guard let previewImage = ImageEditorCanvasView.renderForOutput(model: model, transform: previewTransform) else {
            owsFailDebug("Couldn't generate preview image.")
            return
        }

        let cropTool = ImageEditorCropViewController(model: model, srcImage: srcImage, previewImage: previewImage)
        presentMediaTool(viewController: cropTool)
    }

    // MARK: - ImageEditorViewDelegate

    private func openTextTool(with textItem: ImageEditorTextItem, isNewItem: Bool, editText: Bool) {
        let textEditor = ImageEditorViewController(model: model, stickerSheetDelegate: stickerSheetDelegate)
        textEditor.selectTextItem(textItem, isNewItem: isNewItem, startEditing: editText)
        presentMediaTool(viewController: textEditor)
    }

    func imageEditorViewModelDidChange(_ imageEditorView: ImageEditorView) {
        // Updated model might have different image size / aspect ratio
        // and we need to re-configure scrolling.
        view.setNeedsLayout()
    }

    func imageEditorView(_: ImageEditorView, didRequestAddTextItem textItem: ImageEditorTextItem) {
        openTextTool(with: textItem, isNewItem: true, editText: true)
    }

    func imageEditorView(_: ImageEditorView, didTapTextItem textItem: ImageEditorTextItem) {
        openTextTool(with: textItem, isNewItem: false, editText: false)
    }

    func imageEditorView(_ imageEditorView: ImageEditorView, didMoveTextItem textItem: ImageEditorTextItem) {
        openTextTool(with: textItem, isNewItem: false, editText: false)
    }

    func imageEditorViewDidUpdateSelection(_ imageEditorView: ImageEditorView) { }

    func imageEditorDidRequestToolbarVisibilityUpdate(_: ImageEditorView) {
        prepDelegate?.attachmentPrepViewControllerDidRequestUpdateControlsVisibility(self, completion: nil)
    }
}
