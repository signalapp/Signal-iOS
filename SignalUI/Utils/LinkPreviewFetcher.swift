//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
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
    /// - Parameter body: An entire blob of text entered by the user, such as
    /// in the conversation input text field.
    ///
    /// - Parameter enableIfEmpty: If true, link preview fetches will be
    /// re-enabled if the provided text is empty.
    ///
    /// - Parameter prependSchemeIfNeeded: If true, an "https://" scheme will be
    /// prepended to `rawText` if it doesn't have another scheme. This is useful
    /// for text fields dedicated to URL entry.
    public func update(
        _ body: MessageBody,
        enableIfEmpty: Bool = false,
        prependSchemeIfNeeded: Bool = false
    ) {
        if enableIfEmpty, body.text.isEmpty {
            isEnabled = true
        }

        let proposedUrl = validUrl(in: body, prependSchemeIfNeeded: prependSchemeIfNeeded)

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

    private func validUrl(
        in body: MessageBody,
        prependSchemeIfNeeded: Bool
    ) -> URL? {
        if !isEnabled {
            return nil
        }

        if body.text.isEmpty {
            return nil
        }

        if onlyParseIfEnabled, !linkPreviewManager.areLinkPreviewsEnabledWithSneakyTransaction {
            return nil
        }

        var body = body
        if prependSchemeIfNeeded {
            body = self.prependingSchemeIfNeeded(to: body)
        }

        return LinkValidator.firstLinkPreviewURL(in: body)
    }

    private func prependingSchemeIfNeeded(to body: MessageBody) -> MessageBody {
        // Prepend HTTPS if address is missing one…
        let schemePrefix = "https://"
        guard body.text.range(of: schemePrefix, options: [ .caseInsensitive, .anchored ]) == nil else {
            return body
        }
        // …and it doesn't appear to have any other protocol specified.
        guard body.text.range(of: "://") == nil else {
            return body
        }
        let prefixLen = (schemePrefix as NSString).length

        var finalMentions = [NSRange: Aci]()
        for (range, aci) in body.ranges.mentions {
            finalMentions[range.offset(by: prefixLen)] = aci
        }

        return MessageBody(
            text: schemePrefix + body.text,
            ranges: MessageBodyRanges(
                mentions: finalMentions,
                orderedMentions: body.ranges.orderedMentions.map {
                    return $0.offset(by: prefixLen)
                },
                collapsedStyles: body.ranges.collapsedStyles.map {
                    return $0.offset(by: prefixLen)
                }
            )
        )
    }
}
