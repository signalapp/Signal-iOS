//
//  TranslationManager.swift
//  EMMA Translation Kit
//
//  Swift API for EMMA translation features
//

import Foundation

// MARK: - Translation Result (Swift)

public struct TranslationResult {
    public let translatedText: String
    public let confidence: Float
    public let inferenceTimeMs: Double
    public let usedNetwork: Bool

    init(from objcResult: EMTranslationResult) {
        self.translatedText = objcResult.translatedText
        self.confidence = objcResult.confidence
        self.inferenceTimeMs = Double(objcResult.inferenceTimeUs) / 1000.0
        self.usedNetwork = objcResult.usedNetwork
    }
}

// MARK: - Translation Manager

public class TranslationManager {

    // Singleton instance
    public static let shared = TranslationManager()

    private let engine = EMTranslationEngine.shared()

    // Configuration
    public var networkFallbackEnabled: Bool {
        get { return engine.networkFallbackEnabled }
        set { engine.networkFallbackEnabled = newValue }
    }

    // Translation cache
    private var translationCache: [String: TranslationResult] = [:]
    private let cacheQueue = DispatchQueue(label: "im.swordcomm.emma.translation.cache")

    // Statistics
    public private(set) var totalTranslations: Int = 0
    public private(set) var networkTranslations: Int = 0
    public private(set) var cacheHits: Int = 0

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Initialization

    public func initialize(modelPath: String) -> Bool {
        let success = engine.initialize(withModelPath: modelPath)
        if success {
            NSLog("[EMMA] Translation Manager initialized with model: %@", modelPath)
        } else {
            NSLog("[EMMA] Failed to initialize Translation Manager")
        }
        return success
    }

    public func initializeFromBundle(modelName: String) -> Bool {
        guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "mlmodel") else {
            NSLog("[EMMA] Model file not found in bundle: %@", modelName)
            return false
        }

        return initialize(modelPath: modelPath)
    }

    public var isModelLoaded: Bool {
        return engine.isModelLoaded()
    }

    // MARK: - Translation

    public func translate(
        _ text: String,
        from sourceLang: String = "da",
        to targetLang: String = "en"
    ) -> TranslationResult? {
        // Check cache first
        let cacheKey = "\(sourceLang):\(targetLang):\(text)"

        if let cachedResult = getCachedTranslation(key: cacheKey) {
            cacheHits += 1
            return cachedResult
        }

        // Perform translation
        guard let objcResult = engine.translateText(
            text,
            fromLanguage: sourceLang,
            toLanguage: targetLang
        ) else {
            return nil
        }

        let result = TranslationResult(from: objcResult)

        // Update statistics
        totalTranslations += 1
        if result.usedNetwork {
            networkTranslations += 1
        }

        // Cache the result
        cacheTranslation(key: cacheKey, result: result)

        return result
    }

    // Async translation
    public func translate(
        _ text: String,
        from sourceLang: String = "da",
        to targetLang: String = "en"
    ) async -> TranslationResult? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = self?.translate(text, from: sourceLang, to: targetLang)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Language Support

    public func isLanguagePairSupported(from sourceLang: String, to targetLang: String) -> Bool {
        return engine.isLanguagePairSupportedFrom(sourceLang, to: targetLang)
    }

    public var supportedLanguagePairs: [(source: String, target: String)] {
        // Currently only Danish -> English
        // In the future, this could be queried from the model
        return [("da", "en")]
    }

    // MARK: - Cache Management

    private func getCachedTranslation(key: String) -> TranslationResult? {
        return cacheQueue.sync {
            return translationCache[key]
        }
    }

    private func cacheTranslation(key: String, result: TranslationResult) {
        cacheQueue.async {
            // Limit cache size to 1000 entries
            if self.translationCache.count >= 1000 {
                self.translationCache.removeAll()
            }

            self.translationCache[key] = result
        }
    }

    public func clearCache() {
        cacheQueue.async {
            self.translationCache.removeAll()
            self.cacheHits = 0
        }

        NSLog("[EMMA] Translation cache cleared")
    }

    // MARK: - Statistics

    public var statistics: TranslationStatistics {
        return TranslationStatistics(
            totalTranslations: totalTranslations,
            networkTranslations: networkTranslations,
            onDeviceTranslations: totalTranslations - networkTranslations,
            cacheHits: cacheHits,
            networkFallbackRate: totalTranslations > 0 ? Float(networkTranslations) / Float(totalTranslations) : 0.0
        )
    }

    public func resetStatistics() {
        totalTranslations = 0
        networkTranslations = 0
        cacheHits = 0

        NSLog("[EMMA] Translation statistics reset")
    }
}

// MARK: - Translation Statistics

public struct TranslationStatistics {
    public let totalTranslations: Int
    public let networkTranslations: Int
    public let onDeviceTranslations: Int
    public let cacheHits: Int
    public let networkFallbackRate: Float

    public var description: String {
        return """
        Translation Statistics:
        - Total: \(totalTranslations)
        - On-Device: \(onDeviceTranslations)
        - Network: \(networkTranslations)
        - Cache Hits: \(cacheHits)
        - Network Fallback Rate: \(String(format: "%.1f%%", networkFallbackRate * 100))
        """
    }
}

// MARK: - Convenience Extensions

extension String {
    public func translateDanishToEnglish() async -> String? {
        let result = await TranslationManager.shared.translate(self, from: "da", to: "en")
        return result?.translatedText
    }
}
