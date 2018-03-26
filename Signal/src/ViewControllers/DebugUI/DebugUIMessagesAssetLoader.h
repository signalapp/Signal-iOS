//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMessagesUtils.h"

NS_ASSUME_NONNULL_BEGIN

@interface DebugUIMessagesAssetLoader : NSObject

@property (nonatomic) NSString *filename;
@property (nonatomic) NSString *mimeType;

@property (nonatomic) ActionPrepareBlock prepareBlock;

@property (nonatomic, nullable) NSString *filePath;

#pragma mark -

+ (instancetype)jpegInstance;
+ (instancetype)gifInstance;
+ (instancetype)mp3Instance;
+ (instancetype)mp4Instance;
+ (instancetype)portraitPngInstance;
+ (instancetype)landscapePngInstance;
+ (instancetype)largePngInstance;
+ (instancetype)tinyPdfInstance;
+ (instancetype)largePdfInstance;
+ (instancetype)missingPngInstance;
+ (instancetype)missingPdfInstance;
+ (instancetype)oversizeTextInstance;

@end

NS_ASSUME_NONNULL_END
