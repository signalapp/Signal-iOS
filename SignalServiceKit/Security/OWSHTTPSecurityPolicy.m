//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSHTTPSecurityPolicy.h"
#import <AssertMacros.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSHTTPSecurityPolicy

+ (instancetype)sharedPolicy {
    static OWSHTTPSecurityPolicy *httpSecurityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        httpSecurityPolicy = [[self alloc]
            initWithPinnedCertificates:[NSSet setWithArray:@[ [self certificateDataForService:@"signal-messenger"] ]]];
    });
    return httpSecurityPolicy;
}

+ (instancetype)systemDefault {
    return [[self alloc] initWithPinnedCertificates:[NSSet set]];
}

- (instancetype)initWithPinnedCertificates:(NSSet<NSData *> *)certificates {
    self = [super init];
    if (self) {
        _pinnedCertificates = [certificates copy];
    }
    return self;
}

+ (NSData *)dataFromCertificateFileForService:(NSString *)service {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:service ofType:@"cer"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        OWSFail(@"Missing signing certificate for service %@", service);
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    OWSAssert(data.length > 0);
    
    return data;
}

+ (NSData *)certificateDataForService:(NSString *)service {
    SecCertificateRef certRef = [self newCertificateForService:service];
    NSData *result = (__bridge_transfer NSData *)SecCertificateCopyData(certRef);
    CFRelease(certRef);
    return result;
}

+ (SecCertificateRef)newCertificateForService:(NSString *)service CF_RETURNS_RETAINED {
    NSData *certificateData = [self dataFromCertificateFileForService:service];
    SecCertificateRef certRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certificateData));
    OWSAssert(certRef);
    return certRef;
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(nullable NSString *)domain {
    NSMutableArray *policies = [NSMutableArray array];
    [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];

    if (SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies) != errSecSuccess) {
        OWSLogError(@"The trust policy couldn't be set.");
        return NO;
    }

    if ([self.pinnedCertificates count] > 0) {
        NSMutableArray *pinnedCertificates = [NSMutableArray array];
        for (NSData *certificateData in self.pinnedCertificates) {
            [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(
                                              NULL, (__bridge CFDataRef)certificateData)];
        }

        if (SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates) != errSecSuccess) {
            OWSLogError(@"The anchor certificates couldn't be set.");
            return NO;
        }
    } else {
        // Use SecTrust's default set of anchor certificates.
    }

    if (!AFServerTrustIsValid(serverTrust)) {
        return NO;
    }

    return YES;
}

static BOOL AFServerTrustIsValid(SecTrustRef serverTrust) {
    BOOL isValid = NO;
    SecTrustResultType result;
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);

    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);

_out:
    return isValid;
}

@end

NS_ASSUME_NONNULL_END
