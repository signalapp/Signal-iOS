//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIMessagesUtils.h"

#ifdef USE_DEBUG_UI

NS_ASSUME_NONNULL_BEGIN

@interface DebugUIMessagesAssetLoader : NSObject

@property (nonatomic) NSString *filename;
@property (nonatomic) NSString *mimeType;

@property (nonatomic) ActionPrepareBlock prepareBlock;

@property (nonatomic, nullable) NSString *filePath;

- (NSString *)labelEmoji;

#pragma mark -

+ (instancetype)jpegInstance;
+ (instancetype)gifInstance;
+ (instancetype)largeGifInstance;
+ (instancetype)mp3Instance;
+ (instancetype)mp4Instance;
+ (instancetype)compactPortraitPngInstance;
+ (instancetype)compactLandscapePngInstance;
+ (instancetype)tallPortraitPngInstance;
+ (instancetype)wideLandscapePngInstance;
+ (instancetype)largePngInstance;
+ (instancetype)tinyPngInstance;
+ (instancetype)pngInstanceWithSize:(CGSize)size
                    backgroundColor:(UIColor *)backgroundColor
                          textColor:(UIColor *)textColor
                              label:(NSString *)label;
+ (instancetype)mediumFilesizePngInstance;
+ (instancetype)tinyPdfInstance;
+ (instancetype)largePdfInstance;
+ (instancetype)missingPngInstance;
+ (instancetype)missingPdfInstance;
+ (instancetype)oversizeTextInstance;
+ (instancetype)oversizeTextInstanceWithText:(NSString *)text;

#pragma mark -

+ (void)prepareAssetLoaders:(NSArray<DebugUIMessagesAssetLoader *> *)assetLoaders
                    success:(dispatch_block_t)success
                    failure:(dispatch_block_t)failure;

@end

NS_ASSUME_NONNULL_END

#endif
