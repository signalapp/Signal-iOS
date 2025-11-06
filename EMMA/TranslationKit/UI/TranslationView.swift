//
//  TranslationView.swift
//  EMMA TranslationKit UI
//
//  SwiftUI component for displaying message translations
//

import SwiftUI

/// Message translation display with confidence indicator
@available(iOS 15.0, *)
public struct TranslationView: View {
    let originalText: String
    let originalLanguage: String
    let targetLanguage: String
    @State private var translationResult: TranslationResult?
    @State private var isLoading: Bool = false
    @State private var error: String?

    public init(
        originalText: String,
        originalLanguage: String,
        targetLanguage: String
    ) {
        self.originalText = originalText
        self.originalLanguage = originalLanguage
        self.targetLanguage = targetLanguage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text("Translation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if let result = translationResult {
                    ConfidenceBadge(confidence: result.confidence)
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            // Translation content
            if let result = translationResult {
                VStack(alignment: .leading, spacing: 8) {
                    // Translated text
                    Text(result.translatedText)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)

                    // Metadata
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Text(languageFlag(originalLanguage))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(languageFlag(targetLanguage))
                        }
                        .font(.system(size: 12))

                        if result.usedNetwork {
                            HStack(spacing: 4) {
                                Image(systemName: "network")
                                    .font(.system(size: 10))
                                Text("Network")
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 10))
                                Text("On-device")
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(formatInferenceTime(result.inferenceTimeUs))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } else if let error = error {
                // Error state
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundColor(.red)

                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            } else if isLoading {
                // Loading state
                HStack(spacing: 12) {
                    ProgressView()

                    Text("Translating...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .task {
            await performTranslation()
        }
    }

    private func performTranslation() async {
        isLoading = true
        error = nil

        do {
            let engine = EMTranslationEngine.shared()

            // Perform translation on background thread
            let result = await Task.detached {
                engine.translateText(
                    originalText,
                    fromLanguage: originalLanguage,
                    toLanguage: targetLanguage
                )
            }.value

            await MainActor.run {
                if let result = result {
                    translationResult = TranslationResult(
                        translatedText: result.translatedText,
                        confidence: result.confidence,
                        inferenceTimeUs: result.inferenceTimeUs,
                        usedNetwork: result.usedNetwork
                    )
                } else {
                    error = "Translation failed"
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func languageFlag(_ code: String) -> String {
        switch code.lowercased() {
        case "da", "danish":
            return "🇩🇰"
        case "en", "english":
            return "🇬🇧"
        case "de", "german":
            return "🇩🇪"
        case "fr", "french":
            return "🇫🇷"
        case "es", "spanish":
            return "🇪🇸"
        default:
            return "🌐"
        }
    }

    private func formatInferenceTime(_ timeUs: UInt64) -> String {
        if timeUs < 1000 {
            return "\(timeUs)μs"
        } else if timeUs < 1_000_000 {
            return String(format: "%.1fms", Double(timeUs) / 1000.0)
        } else {
            return String(format: "%.2fs", Double(timeUs) / 1_000_000.0)
        }
    }
}

// MARK: - Translation Result Model

public struct TranslationResult {
    let translatedText: String
    let confidence: Double
    let inferenceTimeUs: UInt64
    let usedNetwork: Bool
}

// MARK: - Confidence Badge

@available(iOS 15.0, *)
private struct ConfidenceBadge: View {
    let confidence: Double

    private var color: Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.5 {
            return .yellow
        } else {
            return .orange
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(String(format: "%.0f%%", confidence * 100))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
}

// MARK: - Inline Translation Bubble

/// Compact inline translation display for message cells
@available(iOS 15.0, *)
public struct InlineTranslationBubble: View {
    let translatedText: String
    let confidence: Double
    @State private var isExpanded: Bool = false

    public init(translatedText: String, confidence: Double) {
        self.translatedText = translatedText
        self.confidence = confidence
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with toggle
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)

                    Text("Translation available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Expanded translation
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(translatedText)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color.blue.opacity(0.06))
                        .cornerRadius(6)

                    HStack {
                        Circle()
                            .fill(confidenceColor)
                            .frame(width: 4, height: 4)

                        Text("Confidence: \(Int(confidence * 100))%")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
    }

    private var confidenceColor: Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.5 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Translation Settings View

@available(iOS 15.0, *)
public struct TranslationSettingsView: View {
    @State private var autoTranslateEnabled: Bool = true
    @State private var networkFallbackEnabled: Bool = true
    @State private var selectedSourceLanguage: String = "da"
    @State private var selectedTargetLanguage: String = "en"

    private let languages = [
        ("da", "Danish", "🇩🇰"),
        ("en", "English", "🇬🇧"),
        ("de", "German", "🇩🇪"),
        ("fr", "French", "🇫🇷"),
        ("es", "Spanish", "🇪🇸")
    ]

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Translation Options")) {
                Toggle("Auto-translate messages", isOn: $autoTranslateEnabled)

                Toggle("Use network fallback", isOn: $networkFallbackEnabled)
                    .disabled(!autoTranslateEnabled)
            }

            Section(header: Text("Language Preferences")) {
                Picker("Source Language", selection: $selectedSourceLanguage) {
                    ForEach(languages, id: \.0) { code, name, flag in
                        HStack {
                            Text(flag)
                            Text(name)
                        }
                        .tag(code)
                    }
                }

                Picker("Target Language", selection: $selectedTargetLanguage) {
                    ForEach(languages, id: \.0) { code, name, flag in
                        HStack {
                            Text(flag)
                            Text(name)
                        }
                        .tag(code)
                    }
                }
            }

            Section(header: Text("Model Status")) {
                HStack {
                    Text("On-device model")
                    Spacer()
                    if EMTranslationEngine.shared().isModelLoaded() {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Loaded")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Not loaded")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .font(.system(size: 15))
            }
        }
        .navigationTitle("Translation Settings")
    }
}

// MARK: - Preview

@available(iOS 15.0, *)
struct TranslationView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Full translation view
                TranslationView(
                    originalText: "Hej, hvordan har du det?",
                    originalLanguage: "da",
                    targetLanguage: "en"
                )

                // Inline bubble (collapsed)
                InlineTranslationBubble(
                    translatedText: "Hello, how are you?",
                    confidence: 0.92
                )

                // Settings view
                NavigationView {
                    TranslationSettingsView()
                }
                .frame(height: 400)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}
