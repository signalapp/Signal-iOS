//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFSecurityPolicy.h>

NS_ASSUME_NONNULL_BEGIN

extern NSData *SSKTextSecureServiceCertificateData(void);

@interface OWSHTTPSecurityPolicy : AFSecurityPolicy

+ (instancetype)sharedPolicy;

@end

NS_ASSUME_NONNULL_END
