//
//  EMTranslationKit.h
//  EMMA Translation Kit
//
//  Objective-C bridge for C++ translation components
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Translation Result

@interface EMTranslationResult : NSObject

@property (nonatomic, strong, readonly) NSString *translatedText;
@property (nonatomic, assign, readonly) float confidence;
@property (nonatomic, assign, readonly) uint64_t inferenceTimeUs;
@property (nonatomic, assign, readonly) BOOL usedNetwork;

@end

// MARK: - Translation Engine

@interface EMTranslationEngine : NSObject

+ (instancetype)sharedEngine;

- (BOOL)initializeWithModelPath:(NSString *)modelPath;
- (nullable EMTranslationResult *)translateText:(NSString *)sourceText
                                      fromLanguage:(NSString *)sourceLang
                                        toLanguage:(NSString *)targetLang;

- (BOOL)isModelLoaded;
- (BOOL)isLanguagePairSupportedFrom:(NSString *)sourceLang to:(NSString *)targetLang;

@property (nonatomic, assign) BOOL networkFallbackEnabled;

@end

NS_ASSUME_NONNULL_END
