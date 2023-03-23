//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public class LinkPreviewFetcher {

    private let linkPreviewManager: LinkPreviewManager
    private let schedulers: Schedulers
    private let onlyParseIfEnabled: Bool

    public init(
        linkPreviewManager: LinkPreviewManager,
        schedulers: Schedulers,
        onlyParseIfEnabled: Bool = true,
        linkPreviewDraft: OWSLinkPreviewDraft? = nil
    ) {
        self.linkPreviewManager = linkPreviewManager
        self.schedulers = schedulers
        self.onlyParseIfEnabled = onlyParseIfEnabled
        if let linkPreviewDraft {
            self._currentState = (.loaded(linkPreviewDraft), linkPreviewDraft.url)
        } else {
            self._currentState = (.none, nil)
        }
    }

    // MARK: - State

    public enum State {
        /// There's no link preview. Perhaps the text doesn't contain a URL, or
        /// perhaps the user explicitly dismissed the link preview.
        case none

        /// There's a URL in the text, and the link preview is currently loading.
        case loading

        /// There's a URL in the text, and the link preview has finished loading.
        case loaded(OWSLinkPreviewDraft)

        /// There's a URL in the text, but we couldn't load a link preview for it.
        case failed(Error)
    }

    private var _currentState: (State, URL?) {
        didSet {
            onStateChange?()
        }
    }

    /// Invoked when `currentState` is updated.
    public var onStateChange: (() -> Void)?

    public var currentState: State { _currentState.0 }

    /// The URL that we fetched/are fetching/failed to fetch.
    public var currentUrl: URL? { _currentState.1 }

    /// If false, the user tapped the "X" to dismiss the link preview.
    private var isEnabled = true

    /// Dismiss the current link preview (if any).
    ///
    /// This also disables future fetch attempts for this instance, regardless
    /// of whether or not link previews are enabled.
    public func disable() {
        isEnabled = false
        _currentState = (.none, nil)
    }

    public var linkPreviewDraftIfLoaded: OWSLinkPreviewDraft? {
        switch currentState {
        case .none, .loading, .failed:
            return nil
        case .loaded(let linkPreviewDraft):
            return linkPreviewDraft
        }
    }

    // MARK: - Fetching

    /// Updates the user-provided text that may contain a URL.
    ///
    /// - Parameter rawText: An entire blob of text entered by the user, such as
    /// in the conversation input text field.
    ///
    /// - Parameter enableIfEmpty: If true, link preview fetches will be
    /// re-enabled if the provided text is empty.
    ///
    /// - Parameter prependSchemeIfNeeded: If true, an "https://" scheme will be
    /// prepended to `rawText` if it doesn't have another scheme. This is useful
    /// for text fields dedicated to URL entry.
    public func update(_ rawText: String, enableIfEmpty: Bool = false, prependSchemeIfNeeded: Bool = false) {
        let filteredText = (rawText as NSString).ows_stripped()

        if enableIfEmpty, filteredText.isEmpty {
            isEnabled = true
        }

        let proposedUrl = validUrl(in: rawText, prependSchemeIfNeeded: prependSchemeIfNeeded)

        if currentUrl == proposedUrl {
            return
        }

        guard let proposedUrl else {
            _currentState = (.none, nil)
            return
        }

        _currentState = (.loading, proposedUrl)

        linkPreviewManager.fetchLinkPreview(for: proposedUrl)
            .done(on: schedulers.main) { [weak self] linkPreviewDraft in
                guard let self = self else { return }
                // Obsolete callback.
                guard self.currentUrl == proposedUrl else { return }

                self._currentState = (.loaded(linkPreviewDraft), proposedUrl)
            }
            .catch(on: schedulers.main) { [weak self] error in
                guard let self = self else { return }
                // Obsolete callback.
                guard self.currentUrl == proposedUrl else { return }

                self._currentState = (.failed(error), proposedUrl)
            }
    }

    private func validUrl(in filteredText: String, prependSchemeIfNeeded: Bool) -> URL? {
        var filteredText = filteredText

        if !isEnabled {
            return nil
        }

        if filteredText.isEmpty {
            return nil
        }

        if onlyParseIfEnabled, !linkPreviewManager.areLinkPreviewsEnabledWithSneakyTransaction {
            return nil
        }

        if prependSchemeIfNeeded {
            self.prependSchemeIfNeeded(to: &filteredText)
        }

        return LinkValidator.firstLinkPreviewURL(in: filteredText)
    }

    private func prependSchemeIfNeeded(to text: inout String) {
        // Prepend HTTPS if address is missing one…
        let schemePrefix = "https://"
        guard text.range(of: schemePrefix, options: [ .caseInsensitive, .anchored ]) == nil else {
            return
        }
        // …and it doesn't appear to have any other protocol specified.
        guard text.range(of: "://") == nil else {
            return
        }
        text.insert(contentsOf: schemePrefix, at: text.startIndex)
    }
}
