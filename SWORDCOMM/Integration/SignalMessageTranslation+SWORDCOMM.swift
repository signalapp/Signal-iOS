//
//  SignalMessageTranslation+SWORDCOMM.swift
//  Signal-iOS SWORDCOMM Translation Integration
//
//  Helper for integrating SWORDCOMM translation into Signal message cells
//

import Foundation
import SwiftUI
import UIKit

/// SWORDCOMM Message Translation Manager for Signal
@available(iOS 15.0, *)
public class SWORDCOMMMessageTranslationManager {

    public static let shared = SWORDCOMMMessageTranslationManager()

    private let translationEngine = EMTranslationEngine.shared()
    private var translationCache: [String: CachedTranslation] = [:]

    private struct CachedTranslation {
        let translation: String
        let confidence: Double
        let timestamp: Date
    }

    private init() {}

    /// Check if translation should be performed for a message
    /// @param messageText The message text to check
    /// @param senderId The sender's ID (to avoid translating own messages)
    /// @param currentUserId The current user's ID
    /// @return true if translation should be performed
    public func shouldTranslate(messageText: String, senderId: String?, currentUserId: String?) -> Bool {
        // Don't translate if feature is disabled
        guard UserDefaults.standard.bool(forKey: "SWORDCOMM.AutoTranslate") else {
            return false
        }

        // Don't translate own messages
        if let senderId = senderId, let currentUserId = currentUserId, senderId == currentUserId {
            return false
        }

        // Don't translate very short messages
        guard messageText.count > 3 else {
            return false
        }

        // Check if message appears to be in source language (simple heuristic)
        // In production, use proper language detection
        return true
    }

    /// Translate a message asynchronously
    /// @param messageText The text to translate
    /// @param completion Completion handler with translation result
    public func translateMessage(
        _ messageText: String,
        completion: @escaping (TranslationResult?) -> Void
    ) {
        // Check cache first
        if let cached = translationCache[messageText],
           Date().timeIntervalSince(cached.timestamp) < 3600 { // 1 hour cache
            let result = TranslationResult(
                translatedText: cached.translation,
                confidence: cached.confidence,
                inferenceTimeUs: 0,
                usedNetwork: false
            )
            completion(result)
            return
        }

        // Perform translation on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }

            let sourceLanguage = UserDefaults.standard.string(forKey: "SWORDCOMM.SourceLanguage") ?? "da"
            let targetLanguage = UserDefaults.standard.string(forKey: "SWORDCOMM.TargetLanguage") ?? "en"

            guard let result = self.translationEngine.translateText(
                messageText,
                fromLanguage: sourceLanguage,
                toLanguage: targetLanguage
            ) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            // Cache the result
            self.translationCache[messageText] = CachedTranslation(
                translation: result.translatedText,
                confidence: result.confidence,
                timestamp: Date()
            )

            // Return on main queue
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Clear translation cache
    public func clearCache() {
        translationCache.removeAll()
    }
}

/// Translation view for message cells
@available(iOS 15.0, *)
public class SWORDCOMMMessageTranslationView: UIView {

    private var hostingController: UIHostingController<InlineTranslationBubble>?
    private var translation: String?
    private var confidence: Double = 0.0

    public init() {
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Display translation for a message
    /// @param translation The translated text
    /// @param confidence Translation confidence (0.0 to 1.0)
    public func showTranslation(_ translation: String, confidence: Double) {
        self.translation = translation
        self.confidence = confidence

        // Remove existing hosting controller if any
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        // Create new translation bubble
        let bubble = InlineTranslationBubble(
            translatedText: translation,
            confidence: confidence
        )

        let hosting = UIHostingController(rootView: bubble)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        hostingController = hosting
    }

    /// Hide the translation view
    public func hideTranslation() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil
        translation = nil
    }
}

// MARK: - UIView Extension for Message Cells

@available(iOS 15.0, *)
public extension UIView {

    /// Associated object key for translation view
    private static var translationViewKey: UInt8 = 0

    /// Get or create SWORDCOMM translation view for this cell
    var emmaTranslationView: SWORDCOMMMessageTranslationView {
        if let existing = objc_getAssociatedObject(self, &Self.translationViewKey) as? SWORDCOMMMessageTranslationView {
            return existing
        }

        let translationView = SWORDCOMMMessageTranslationView()
        objc_setAssociatedObject(self, &Self.translationViewKey, translationView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return translationView
    }

    /// Add translation view to this message cell
    /// @param belowView The view to position the translation below (typically the message label)
    func addSWORDCOMMTranslation(below belowView: UIView) {
        let translationView = emmaTranslationView

        if translationView.superview == nil {
            addSubview(translationView)
            translationView.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                translationView.topAnchor.constraint(equalTo: belowView.bottomAnchor, constant: 4),
                translationView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                translationView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
            ])
        }
    }

    /// Remove SWORDCOMM translation view from this message cell
    func removeSWORDCOMMTranslation() {
        emmaTranslationView.removeFromSuperview()
    }
}

// MARK: - Integration Instructions

/*

 To integrate SWORDCOMM translation into Signal message cells:

 1. In message cell configuration (e.g., CVTextMessageView, MessageCell, etc.):

    func configureMessageCell(with messageText: String, senderId: String?) {
        // ... existing Signal cell setup ...

        // ┌──────────────────────────────────┐
        // │ SWORDCOMM Translation Integration     │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *) {
            configureSWORDCOMMTranslation(messageText: messageText, senderId: senderId)
        }
    }

    @available(iOS 15.0, *)
    private func configureSWORDCOMMTranslation(messageText: String, senderId: String?) {
        let manager = SWORDCOMMMessageTranslationManager.shared

        // Check if translation should be performed
        guard manager.shouldTranslate(
            messageText: messageText,
            senderId: senderId,
            currentUserId: getCurrentUserId()
        ) else {
            removeSWORDCOMMTranslation()
            return
        }

        // Add translation view below message label
        addSWORDCOMMTranslation(below: messageLabel) // Or appropriate text view

        // Perform translation
        manager.translateMessage(messageText) { [weak self] result in
            guard let self = self, let result = result else {
                return
            }

            // Display translation
            self.swordcommTranslationView.showTranslation(
                result.translatedText,
                confidence: result.confidence
            )
        }
    }


 2. To handle cell reuse (in prepareForReuse()):

    override func prepareForReuse() {
        super.prepareForReuse()

        // Remove translation view when cell is reused
        if #available(iOS 15.0, *) {
            removeSWORDCOMMTranslation()
        }
    }


 3. To add translation button (manual translation):

    private func addTranslationButton() {
        let button = UIButton(type: .system)
        button.setTitle("Translate", for: .normal)
        button.addTarget(self, action: #selector(translateButtonTapped), for: .touchUpInside)
        // ... add button to cell UI ...
    }

    @objc
    private func translateButtonTapped() {
        guard #available(iOS 15.0, *) else { return }

        let manager = SWORDCOMMMessageTranslationManager.shared
        manager.translateMessage(messageText) { [weak self] result in
            guard let self = self, let result = result else {
                return
            }

            self.addSWORDCOMMTranslation(below: self.messageLabel)
            self.swordcommTranslationView.showTranslation(
                result.translatedText,
                confidence: result.confidence
            )
        }
    }


 4. To detect language automatically:

    import NaturalLanguage

    private func detectLanguage(in text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let language = recognizer.dominantLanguage else {
            return nil
        }

        return language.rawValue // e.g., "da" for Danish, "en" for English
    }

    private func shouldTranslateBasedOnLanguage(messageText: String) -> Bool {
        guard let detected = detectLanguage(in: messageText) else {
            return false
        }

        let targetLanguage = UserDefaults.standard.string(forKey: "SWORDCOMM.TargetLanguage") ?? "en"

        // Only translate if detected language is different from target
        return detected != targetLanguage
    }

 */
