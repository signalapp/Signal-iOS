//
//  TranslationIntegration.swift
//  Example: Translation with On-Device Priority and Network Fallback
//
//  This file demonstrates SWORDCOMM's translation architecture:
//  PRIMARY: On-device CoreML translation (private, offline)
//  FALLBACK: Network translation (only when on-device unavailable)
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Translation Priority Architecture

/*

SWORDCOMM Translation Priority:

1. ✅ ON-DEVICE (CoreML) - PRIMARY
   - Uses OPUS-MT model converted to CoreML
   - 100% private (never leaves device)
   - Works offline
   - Fast (~50-100ms inference)
   - Supports: Danish ↔ English (primary language pair)

2. ⚠️ NETWORK FALLBACK - SECONDARY
   - Used only when:
     * CoreML model not loaded
     * Unsupported language pair
     * On-device translation fails
   - Requires internet connection
   - Slower latency
   - Should be minimal usage

*/


// MARK: - Example 1: Translation Manager with Priority

@available(iOS 15.0, *)
class SWORDCOMMTranslationPriorityManager {

    static let shared = SWORDCOMMTranslationPriorityManager()

    private let onDeviceEngine = EMTranslationEngine.shared()
    private var translationStats = TranslationStats()

    struct TranslationStats {
        var totalTranslations: Int = 0
        var onDeviceTranslations: Int = 0
        var networkTranslations: Int = 0

        var onDevicePercentage: Double {
            guard totalTranslations > 0 else { return 0.0 }
            return Double(onDeviceTranslations) / Double(totalTranslations) * 100.0
        }
    }

    private init() {}

    /// Translate text with on-device priority
    func translateText(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        completion: @escaping (TranslationResult?) -> Void
    ) {
        translationStats.totalTranslations += 1

        // PRIORITY 1: Try on-device translation first
        if onDeviceEngine.isModelLoaded() {
            Logger.info("[SWORDCOMM Translation] Attempting on-device translation")

            if let result = tryOnDeviceTranslation(text, from: sourceLanguage, to: targetLanguage) {
                Logger.info("[SWORDCOMM Translation] ✓ On-device translation succeeded")
                translationStats.onDeviceTranslations += 1
                completion(result)
                return
            }

            Logger.warn("[SWORDCOMM Translation] On-device translation failed, trying fallback")
        } else {
            Logger.warn("[SWORDCOMM Translation] CoreML model not loaded, using network fallback")
        }

        // PRIORITY 2: Network fallback (only if on-device failed or unavailable)
        if UserDefaults.standard.bool(forKey: "SWORDCOMM.NetworkFallbackEnabled") {
            Logger.info("[SWORDCOMM Translation] Using network fallback")
            tryNetworkTranslation(text, from: sourceLanguage, to: targetLanguage) { result in
                if result != nil {
                    self.translationStats.networkTranslations += 1
                }
                completion(result)
            }
        } else {
            Logger.warn("[SWORDCOMM Translation] Network fallback disabled, translation failed")
            completion(nil)
        }
    }

    /// Try on-device CoreML translation
    private func tryOnDeviceTranslation(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) -> TranslationResult? {
        let startTime = Date()

        // Use CoreML engine
        guard let result = onDeviceEngine.translateText(
            text,
            fromLanguage: sourceLanguage,
            toLanguage: targetLanguage
        ) else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(startTime) * 1000  // Convert to ms

        Logger.info("[SWORDCOMM Translation] On-device translation: \(elapsed)ms")

        return TranslationResult(
            translatedText: result.translatedText,
            confidence: result.confidence,
            inferenceTimeUs: Int(elapsed * 1000),  // Convert to microseconds
            usedNetwork: false  // Mark as on-device
        )
    }

    /// Try network translation (fallback only)
    private func tryNetworkTranslation(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        completion: @escaping (TranslationResult?) -> Void
    ) {
        // Check network availability first
        guard isNetworkAvailable() else {
            Logger.warn("[SWORDCOMM Translation] Network unavailable, translation failed")
            completion(nil)
            return
        }

        Logger.warn("[SWORDCOMM Translation] ⚠️ Using network fallback (on-device preferred)")

        // Perform network translation
        // In production, this would call your translation API
        performNetworkTranslation(text, from: sourceLanguage, to: targetLanguage, completion: completion)
    }

    /// Check network availability
    private func isNetworkAvailable() -> Bool {
        // In production, use Network framework or Reachability
        // For example:
        // return NetworkMonitor.shared.isConnected
        return true  // Simplified
    }

    /// Perform actual network translation
    private func performNetworkTranslation(
        _ text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        completion: @escaping (TranslationResult?) -> Void
    ) {
        // Example: Call translation API
        let url = URL(string: "https://your-translation-api.com/translate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "source_language": sourceLanguage,
            "target_language": targetLanguage
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let translatedText = json["translated_text"] as? String else {
                Logger.error("[SWORDCOMM Translation] Network translation failed")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let result = TranslationResult(
                translatedText: translatedText,
                confidence: 0.8,  // Network translation confidence
                inferenceTimeUs: 0,
                usedNetwork: true  // Mark as network
            )

            DispatchQueue.main.async {
                completion(result)
            }
        }

        task.resume()
    }

    /// Get translation statistics
    func getStatistics() -> TranslationStats {
        return translationStats
    }

    /// Log translation statistics
    func logStatistics() {
        let stats = translationStats
        Logger.info("""
        [SWORDCOMM Translation Stats]
        Total translations: \(stats.totalTranslations)
        On-device: \(stats.onDeviceTranslations) (\(String(format: "%.1f", stats.onDevicePercentage))%)
        Network fallback: \(stats.networkTranslations) (\(String(format: "%.1f", 100.0 - stats.onDevicePercentage))%)
        """)
    }
}


// MARK: - Example 2: Message Cell with Translation Priority

@available(iOS 15.0, *)
class MessageCellWithTranslation: UITableViewCell {

    private let messageLabel = UILabel()
    private let translationView = SWORDCOMMMessageTranslationView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(messageLabel)
        contentView.addSubview(translationView)

        // Layout constraints...
    }

    func configure(with message: String, shouldTranslate: Bool) {
        messageLabel.text = message

        if shouldTranslate {
            // Use priority manager for translation
            let manager = SWORDCOMMTranslationPriorityManager.shared
            let sourceLanguage = UserDefaults.standard.string(forKey: "SWORDCOMM.SourceLanguage") ?? "da"
            let targetLanguage = UserDefaults.standard.string(forKey: "SWORDCOMM.TargetLanguage") ?? "en"

            manager.translateText(
                message,
                from: sourceLanguage,
                to: targetLanguage
            ) { [weak self] result in
                guard let self = self, let result = result else {
                    return
                }

                // Show translation with indicator
                self.translationView.showTranslation(
                    result.translatedText,
                    confidence: result.confidence
                )

                // Log translation method
                if result.usedNetwork {
                    Logger.debug("[SWORDCOMM] Translation used network fallback")
                } else {
                    Logger.debug("[SWORDCOMM] Translation used on-device CoreML")
                }
            }
        } else {
            translationView.hideTranslation()
        }
    }
}


// MARK: - Example 3: Translation Settings View with Statistics

@available(iOS 15.0, *)
struct TranslationSettingsWithStats: View {
    @AppStorage("SWORDCOMM.AutoTranslate") private var autoTranslate = false
    @AppStorage("SWORDCOMM.NetworkFallbackEnabled") private var networkFallback = true
    @State private var translationStats: SWORDCOMMTranslationPriorityManager.TranslationStats?

    var body: some View {
        Form {
            Section(header: Text("Translation Method")) {
                HStack {
                    Image(systemName: "brain")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("On-Device Translation")
                            .font(.headline)
                        Text("Primary method (private, offline)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                modelStatusRow

                Toggle("Enable Network Fallback", isOn: $networkFallback)
                    .onChange(of: networkFallback) { value in
                        if value {
                            Logger.info("[SWORDCOMM] Network fallback enabled")
                        } else {
                            Logger.warn("[SWORDCOMM] Network fallback disabled - translations may fail without on-device model")
                        }
                    }

                if networkFallback {
                    Text("⚠️ Network fallback should only be used when on-device translation is unavailable.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if let stats = translationStats {
                Section(header: Text("Translation Statistics")) {
                    HStack {
                        Text("Total Translations")
                        Spacer()
                        Text("\(stats.totalTranslations)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("On-Device")
                        Spacer()
                        Text("\(stats.onDeviceTranslations) (\(String(format: "%.1f", stats.onDevicePercentage))%)")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Network Fallback")
                        Spacer()
                        Text("\(stats.networkTranslations)")
                            .foregroundColor(.orange)
                    }

                    if stats.networkTranslations > stats.onDeviceTranslations {
                        Text("⚠️ Network usage is high. Consider downloading the on-device model for better privacy.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Section {
                Button("Download On-Device Model") {
                    downloadModel()
                }
                .disabled(EMTranslationEngine.shared().isModelLoaded())

                Button("Refresh Statistics") {
                    loadStatistics()
                }
            }
        }
        .navigationTitle("Translation Settings")
        .onAppear {
            loadStatistics()
        }
    }

    private var modelStatusRow: some View {
        let engine = EMTranslationEngine.shared()
        let modelLoaded = engine.isModelLoaded()

        return HStack {
            Text("Model Status")
            Spacer()
            Text(modelLoaded ? "✓ Loaded" : "⚠️ Not Loaded")
                .foregroundColor(modelLoaded ? .green : .orange)
        }
    }

    private func loadStatistics() {
        let stats = SWORDCOMMTranslationPriorityManager.shared.getStatistics()
        translationStats = stats

        // Log to console
        SWORDCOMMTranslationPriorityManager.shared.logStatistics()
    }

    private func downloadModel() {
        // Trigger model download
        Logger.info("[SWORDCOMM] Starting on-device model download")
        // In production: implement actual download logic
    }
}


// MARK: - Example 4: Translation with Retry Logic

@available(iOS 15.0, *)
class TranslationWithRetry {

    static func translateWithPriority(
        text: String,
        maxRetries: Int = 2,
        completion: @escaping (TranslationResult?) -> Void
    ) {
        let manager = SWORDCOMMTranslationPriorityManager.shared
        let sourceLanguage = UserDefaults.standard.string(forKey: "SWORDCOMM.SourceLanguage") ?? "da"
        let targetLanguage = UserDefaults.standard.string(forKey: "SWORDCOMM.TargetLanguage") ?? "en"

        attemptTranslation(
            text: text,
            from: sourceLanguage,
            to: targetLanguage,
            attempt: 1,
            maxRetries: maxRetries,
            completion: completion
        )
    }

    private static func attemptTranslation(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        attempt: Int,
        maxRetries: Int,
        completion: @escaping (TranslationResult?) -> Void
    ) {
        let manager = SWORDCOMMTranslationPriorityManager.shared

        manager.translateText(text, from: sourceLanguage, to: targetLanguage) { result in
            if let result = result {
                // Success
                completion(result)
            } else if attempt < maxRetries {
                // Retry
                Logger.warn("[SWORDCOMM] Translation attempt \(attempt) failed, retrying...")
                attemptTranslation(
                    text: text,
                    from: sourceLanguage,
                    to: targetLanguage,
                    attempt: attempt + 1,
                    maxRetries: maxRetries,
                    completion: completion
                )
            } else {
                // Failed after all retries
                Logger.error("[SWORDCOMM] Translation failed after \(attempt) attempts")
                completion(nil)
            }
        }
    }
}


// MARK: - Architecture Summary

/*

SWORDCOMM Translation Architecture:

┌─────────────────────────────────────────────────────────────┐
│ Message Received                                            │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
            ┌───────────────────────────────┐
            │ Should Translate?             │
            │ (Check settings, language)    │
            └───────────┬───────────────────┘
                        │
                        ▼
        ┌──────────────────────────────────────┐
        │ Translation Priority Manager         │
        └───────────┬──────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────┐
    │ 1. Try On-Device (CoreML)     │ ◄── PRIMARY METHOD
    │    - Private                  │     (90-100% of translations)
    │    - Offline                  │
    │    - Fast (~50-100ms)         │
    └───────────┬───────────────────┘
                │
                ├─ Success ──► Return Result (usedNetwork: false)
                │
                ▼ Failed or Unavailable
    ┌───────────────────────────────┐
    │ 2. Network Fallback           │ ◄── FALLBACK ONLY
    │    - Requires internet        │     (0-10% of translations)
    │    - Slower latency           │
    │    - Only when needed         │
    └───────────┬───────────────────┘
                │
                ├─ Success ──► Return Result (usedNetwork: true)
                │
                ▼ Failed
                Return nil (translation failed)


Key Principles:

1. On-Device First
   - Always try CoreML translation first
   - 100% private (data never leaves device)
   - Works completely offline

2. Network Fallback (Rare)
   - Only used when on-device unavailable
   - User can disable in settings
   - Should be < 10% of translations

3. User Transparency
   - Show translation method in UI
   - Display statistics (on-device % vs network %)
   - Allow user to download model for offline use

4. Performance
   - On-device: ~50-100ms
   - Network: ~500-2000ms
   - Cache results to avoid re-translation

5. Privacy
   - On-device is always preferred
   - Network fallback respects user settings
   - Clear indication when network is used

*/
