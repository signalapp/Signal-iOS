//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSHTTPSecurityPolicy.h"
#import <AssertMacros.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSHTTPSecurityPolicy

+ (instancetype)sharedPolicy {
    static OWSHTTPSecurityPolicy *httpSecurityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        httpSecurityPolicy = [[self alloc] initWithOWSPolicy];
    });
    return httpSecurityPolicy;
}

- (instancetype)initWithOWSPolicy {
    self = [[super class] defaultPolicy];

    if (self) {
        self.pinnedCertificates = [NSSet setWithArray:@[
            [self.class certificateDataForService:@"textsecure"]
        ]];
    }

    return self;
}

+ (NSData *)dataFromCertificateFileForService:(NSString *)service
{
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

+ (SecCertificateRef)newCertificateForService:(NSString *)service CF_RETURNS_RETAINED
{
    NSData *certificateData = [self dataFromCertificateFileForService:service];
    SecCertificateRef certRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certificateData));
    OWSAssert(certRef);
    return certRef;
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(nullable NSString *)domain
{
    NSMutableArray *policies = [NSMutableArray array];
    [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];

    if (SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies) != errSecSuccess) {
        OWSLogError(@"The trust policy couldn't be set.");
        return NO;
    }

    NSMutableArray *pinnedCertificates = [NSMutableArray array];
    for (NSData *certificateData in self.pinnedCertificates) {
        [pinnedCertificates
            addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
    }

    if (SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates) != errSecSuccess) {
        OWSLogError(@"The anchor certificates couldn't be set.");
        return NO;
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

    isValid = (result == kSecTrustResultUnspecified);

_out:
    return isValid;
}

NSData *SSKTextSecureServiceCertificateData()
{
    return [OWSHTTPSecurityPolicy dataFromCertificateFileForService:@"textsecure"];
}

@end

NS_ASSUME_NONNULL_END
