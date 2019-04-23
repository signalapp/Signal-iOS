//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StickerUtils : NSObject

+ (nullable NSData *)stickerKeyForPackKey:(NSData *)packKey;

@end

NS_ASSUME_NONNULL_END
