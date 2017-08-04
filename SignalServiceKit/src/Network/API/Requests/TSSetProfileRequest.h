//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSSetProfileRequest : TSRequest

- (nullable instancetype)initWithProfileName:(NSData *_Nullable)profileNameEncrypted
                                   avatarUrl:(NSString *_Nullable)avatarUrl
                                avatarDigest:(NSData *_Nullable)avatarDigest;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
