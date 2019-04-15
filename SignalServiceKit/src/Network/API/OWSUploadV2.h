//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;

// This class can be safely accessed and used from any thread.
@interface OWSUploadV2 : NSObject

@property (nonatomic, nullable) NSString *urlPath;

// On success, yields an instance of OWSUploadV2.
+ (AnyPromise *)uploadAvatarToService:(NSData *_Nullable)avatarData clearLocalAvatar:(dispatch_block_t)clearLocalAvatar;

@end

NS_ASSUME_NONNULL_END
