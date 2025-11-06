#ifndef EMMA_TRANSLATION_ENGINE_H
#define EMMA_TRANSLATION_ENGINE_H

#include <string>
#include <cstdint>

namespace emma {
namespace translation {

struct TranslationResult {
    std::string translated_text;
    float confidence;              // 0.0 - 1.0
    uint64_t inference_time_us;    // Microseconds
    bool used_network;             // true if network translation was used
};

class TranslationEngine {
public:
    TranslationEngine();
    ~TranslationEngine();

    // Initialize with model path
    // For iOS, model_path should point to app bundle resource
    bool initialize(const std::string& model_path);

    // Translate text
    // source_lang and target_lang use ISO 639-1 codes (e.g., "da", "en")
    TranslationResult translate(
        const std::string& source_text,
        const std::string& source_lang = "da",
        const std::string& target_lang = "en"
    );

    // Check if model is loaded and ready
    bool is_model_loaded() const;

    // Get supported language pairs
    bool is_language_pair_supported(
        const std::string& source_lang,
        const std::string& target_lang
    ) const;

    // Enable/disable network fallback
    void set_network_fallback_enabled(bool enabled);

private:
    bool load_model(const std::string& model_path);
    void unload_model();

    // On-device translation
    TranslationResult translate_on_device(
        const std::string& source_text,
        const std::string& source_lang,
        const std::string& target_lang
    );

    // Network translation (fallback)
    TranslationResult translate_via_network(
        const std::string& source_text,
        const std::string& source_lang,
        const std::string& target_lang
    );

    bool model_loaded_;
    bool network_fallback_enabled_;
    std::string model_path_;

    // iOS-specific: CoreML model handle would go here
    // void* coreml_model_; // MLModel* in actual implementation
};

} // namespace translation
} // namespace emma

#endif // EMMA_TRANSLATION_ENGINE_H
