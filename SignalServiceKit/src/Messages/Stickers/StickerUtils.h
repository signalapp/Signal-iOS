//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StickerUtils : NSObject

+ (nullable NSData *)stickerKeyForPackKey:(NSData *)packKey;

+ (nullable NSData *)decryptStickerData:(NSData *)dataToDecrypt
                                withKey:(NSData *)key
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
