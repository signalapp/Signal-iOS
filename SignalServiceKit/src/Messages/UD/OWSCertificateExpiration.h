//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSCertificateExpiration : NSObject

+ (nullable NSDate *)expirationDataForCertificate:(NSData *)certificateData;

@end

NS_ASSUME_NONNULL_END
