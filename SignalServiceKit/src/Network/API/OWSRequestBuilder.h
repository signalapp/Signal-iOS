//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSRequest;

@interface OWSRequestBuilder : NSObject

+ (TSRequest *)profileNameSetRequestWithEncryptedPaddedName:(nullable NSData *)encryptedPaddedName;

@end

NS_ASSUME_NONNULL_END
