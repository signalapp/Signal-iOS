//
//  EMTranslationKit.mm
//  EMMA Translation Kit
//
//  Objective-C++ bridge implementation
//

#import "EMTranslationKit.h"

// Include C++ headers
#include "../Native/translation_engine.h"

using namespace emma::translation;

// MARK: - Translation Result

@interface EMTranslationResult ()

- (instancetype)initWithCppResult:(const TranslationResult&)result;

@end

@implementation EMTranslationResult

- (instancetype)initWithCppResult:(const TranslationResult&)result {
    if (self = [super init]) {
        _translatedText = [NSString stringWithUTF8String:result.translated_text.c_str()];
        _confidence = result.confidence;
        _inferenceTimeUs = result.inference_time_us;
        _usedNetwork = result.used_network;
    }
    return self;
}

@end

// MARK: - Translation Engine

@interface EMTranslationEngine () {
    TranslationEngine *_cppEngine;
}
@end

@implementation EMTranslationEngine

+ (instancetype)sharedEngine {
    static EMTranslationEngine *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EMTranslationEngine alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _cppEngine = new TranslationEngine();
        _networkFallbackEnabled = YES;
    }
    return self;
}

- (void)dealloc {
    if (_cppEngine) {
        delete _cppEngine;
        _cppEngine = nullptr;
    }
}

- (BOOL)initializeWithModelPath:(NSString *)modelPath {
    if (!_cppEngine || !modelPath) {
        return NO;
    }

    std::string path = [modelPath UTF8String];
    return _cppEngine->initialize(path);
}

- (nullable EMTranslationResult *)translateText:(NSString *)sourceText
                                      fromLanguage:(NSString *)sourceLang
                                        toLanguage:(NSString *)targetLang {
    if (!_cppEngine || !sourceText || !sourceLang || !targetLang) {
        return nil;
    }

    std::string src_text = [sourceText UTF8String];
    std::string src_lang = [sourceLang UTF8String];
    std::string tgt_lang = [targetLang UTF8String];

    TranslationResult result = _cppEngine->translate(src_text, src_lang, tgt_lang);

    return [[EMTranslationResult alloc] initWithCppResult:result];
}

- (BOOL)isModelLoaded {
    if (!_cppEngine) {
        return NO;
    }
    return _cppEngine->is_model_loaded();
}

- (BOOL)isLanguagePairSupportedFrom:(NSString *)sourceLang to:(NSString *)targetLang {
    if (!_cppEngine || !sourceLang || !targetLang) {
        return NO;
    }

    std::string src_lang = [sourceLang UTF8String];
    std::string tgt_lang = [targetLang UTF8String];

    return _cppEngine->is_language_pair_supported(src_lang, tgt_lang);
}

- (void)setNetworkFallbackEnabled:(BOOL)enabled {
    _networkFallbackEnabled = enabled;

    if (_cppEngine) {
        _cppEngine->set_network_fallback_enabled(enabled);
    }
}

@end
