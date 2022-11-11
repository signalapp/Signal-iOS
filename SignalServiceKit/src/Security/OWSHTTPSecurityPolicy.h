//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>
#import <Security/SecTrust.h>

NS_ASSUME_NONNULL_BEGIN

extern NSData *SSKTextSecureServiceCertificateData(void);
extern NSData *SSKSignalMessengerCertificateData(void);

/// A simplified version of AFNetworking's AFSecurityPolicy.
@interface OWSHTTPSecurityPolicy : NSObject

+ (instancetype)sharedPolicy;
+ (instancetype)systemDefault;

- (instancetype)initWithPinnedCertificates:(NSSet<NSData *> *)certificates;

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(nullable NSString *)domain;

@end

NS_ASSUME_NONNULL_END
