//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "CDSSigningCertificate.h"
#import "NSData+Base64.h"
#import "NSData+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface CDSSigningCertificate ()

@property (nonatomic) SecPolicyRef policy;
@property (nonatomic) SecTrustRef trust;
@property (nonatomic) SecKeyRef publicKey;

@end

#pragma mark -

@implementation CDSSigningCertificate

- (instancetype)init
{
    if (self = [super init]) {
        _policy = NULL;
        _trust = NULL;
        _publicKey = NULL;
    }

    return self;
}

- (void)dealloc
{
    if (_policy) {
        CFRelease(_policy);
        _policy = NULL;
    }
    if (_trust) {
        CFRelease(_trust);
        _trust = NULL;
    }
    if (_publicKey) {
        CFRelease(_publicKey);
        _publicKey = NULL;
    }
}

+ (nullable CDSSigningCertificate *)parseCertificateFromPem:(NSString *)certificatePem
{
    OWSAssert(certificatePem);

    CDSSigningCertificate *signingCertificate = [CDSSigningCertificate new];

    NSArray<NSData *> *_Nullable anchorCertificates = [self anchorCertificates];
    if (anchorCertificates.count < 1) {
        OWSProdLogAndFail(@"%@ Could not load anchor certificates.", self.logTag);
        return nil;
    }

    NSArray<NSData *> *_Nullable certificateDerDatas = [self convertPemToDer:certificatePem];

    if (certificateDerDatas.count < 1) {
        OWSProdLogAndFail(@"%@ Could not parse PEM.", self.logTag);
        return nil;
    }

    NSMutableArray *certificates = [NSMutableArray new];
    for (NSData *certificateDerData in certificateDerDatas) {
        SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certificateDerData));
        if (!certificate) {
            OWSProdLogAndFail(@"%@ Could not load DER.", self.logTag);
            return nil;
        }
        [certificates addObject:(__bridge_transfer id)certificate];
    }

    SecPolicyRef policy = SecPolicyCreateBasicX509();
    signingCertificate.policy = policy;
    if (!policy) {
        DDLogError(@"%@ Could not create policy.", self.logTag);
        return nil;
    }

    SecTrustRef trust;
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certificates, policy, &trust);
    signingCertificate.trust = trust;
    if (status != errSecSuccess) {
        DDLogError(@"%@ trust could not be created.", self.logTag);
        return nil;
    }
    if (!trust) {
        DDLogError(@"%@ Could not create trust.", self.logTag);
        return nil;
    }

    // TODO:
    status = SecTrustSetNetworkFetchAllowed(trust, NO);
    if (status != errSecSuccess) {
        DDLogError(@"%@ trust fetch could not be configured.", self.logTag);
        return nil;
    }

    // TODO:
    status = SecTrustSetAnchorCertificatesOnly(trust, YES);
    if (status != errSecSuccess) {
        DDLogError(@"%@ trust anchor certs could not be configured.", self.logTag);
        return nil;
    }

    NSMutableArray *pinnedCertificates = [NSMutableArray array];
    for (NSData *certificateData in anchorCertificates) {
        SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certificateData));
        if (!certificate) {
            OWSProdLogAndFail(@"%@ Could not load DER.", self.logTag);
            return nil;
        }
        if (![self verifyDistinguishedName:certificate]) {
            OWSProdLogAndFail(@"%@ Certificate has invalid name.", self.logTag);
            return nil;
        }

        [pinnedCertificates addObject:(__bridge_transfer id)certificate];
    }
    status = SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)pinnedCertificates);
    if (status != errSecSuccess) {
        DDLogError(@"%@ The anchor certificates couldn't be set.", self.logTag);
        return nil;
    }

    SecTrustResultType result;
    status = SecTrustEvaluate(trust, &result);
    if (status != errSecSuccess) {
        DDLogError(@"%@ Could not evaluate certificates.", self.logTag);
        return nil;
    }

    // TODO:
    BOOL isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
    if (!isValid) {
        DDLogError(@"%@ Certificate evaluation failed.", self.logTag);
        return nil;
    }

    SecKeyRef publicKey = SecTrustCopyPublicKey(trust);
    signingCertificate.publicKey = publicKey;
    if (!publicKey) {
        DDLogError(@"%@ Could not extract public key.", self.logTag);
        return nil;
    }

    return signingCertificate;
}

// PEM is just a series of blocks of base-64 encoded DER data.
//
// https://en.wikipedia.org/wiki/Privacy-Enhanced_Mail
+ (nullable NSArray<NSData *> *)convertPemToDer:(NSString *)pemString
{
    NSMutableArray<NSData *> *certificateDatas = [NSMutableArray new];

    NSError *error;
    // We use ? for non-greedy matching.
    NSRegularExpression *_Nullable regex = [NSRegularExpression
        regularExpressionWithPattern:@"-----BEGIN.*?-----(.+?)-----END.*?-----"
                             options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                               error:&error];
    if (!regex || error) {
        OWSProdLogAndFail(@"%@ could parse regex: %@.", self.logTag, error);
        return nil;
    }

    [regex enumerateMatchesInString:pemString
                            options:0
                              range:NSMakeRange(0, pemString.length)
                         usingBlock:^(NSTextCheckingResult *_Nullable result, NSMatchingFlags flags, BOOL *stop) {
                             if (result.numberOfRanges != 2) {
                                 OWSProdLogAndFail(@"%@ invalid PEM regex match.", self.logTag);
                                 return;
                             }
                             NSString *_Nullable derString = [pemString substringWithRange:[result rangeAtIndex:1]];
                             if (derString.length < 1) {
                                 OWSProdLogAndFail(@"%@ empty PEM match.", self.logTag);
                                 return;
                             }
                             // dataFromBase64String will ignore whitespace, which is
                             // necessary.
                             NSData *_Nullable derData = [NSData dataFromBase64String:derString];
                             if (derData.length < 1) {
                                 OWSProdLogAndFail(@"%@ could not parse PEM match.", self.logTag);
                                 return;
                             }
                             [certificateDatas addObject:derData];
                         }];

    return certificateDatas;
}

+ (nullable NSArray<NSData *> *)anchorCertificates
{
    // We need to use an Intel certificate as the anchor for IAS verification.
    NSData *_Nullable anchorCertificate = [self certificateDataForService:@"ias-root"];
    if (!anchorCertificate) {
        OWSProdLogAndFail(@"%@ could not load anchor certificate.", self.logTag);
        return nil;
    }
    return @[ anchorCertificate ];
}

+ (nullable NSData *)certificateDataForService:(NSString *)service
{
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:service ofType:@"cer"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        OWSProdLogAndFail(@"%@ could not locate certificate file.", self.logTag);
        return nil;
    }

    NSData *_Nullable certificateData = [NSData dataWithContentsOfFile:path];
    return certificateData;
}

- (BOOL)verifySignatureOfBody:(NSString *)body signature:(NSData *)theirSignature
{
    BOOL result = NO;

    // TODO: Which algorithm should we be using?
    DDLogVerbose(@"%@ kSecKeyAlgorithmRSASignatureDigestPSSSHA256.", self.logTag);
    result = result ||
        [self verifySignatureOfBody:body
                          signature:theirSignature
                          algorithm:kSecKeyAlgorithmRSASignatureDigestPSSSHA256];
    DDLogVerbose(@"%@ kSecKeyAlgorithmRSASignatureMessagePSSSHA256.", self.logTag);
    result = result ||
        [self verifySignatureOfBody:body
                          signature:theirSignature
                          algorithm:kSecKeyAlgorithmRSASignatureMessagePSSSHA256];
    return result;
}

// TODO: This method requires iOS 10.
- (BOOL)verifySignatureOfBody:(NSString *)body signature:(NSData *)signature algorithm:(SecKeyAlgorithm)algorithm
{
    OWSAssert(body.length > 0);
    OWSAssert(signature.length > 0);
    OWSAssert(self.publicKey);

    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];

    BOOL canSign = SecKeyIsAlgorithmSupported(self.publicKey, kSecKeyOperationTypeVerify, algorithm);
    if (!canSign) {
        OWSProdLogAndFail(@"%@ signature algorithm is not supported.", self.logTag);
        return NO;
    }

    CFErrorRef error = NULL;
    BOOL isValid = SecKeyVerifySignature(
        self.publicKey, algorithm, (__bridge CFDataRef)bodyData, (__bridge CFDataRef)signature, &error);
    if (error) {
        NSError *nsError = CFBridgingRelease(error);
        // TODO:
        DDLogError(@"%@ signature verification failed: %@.", self.logTag, nsError);
        //        OWSProdLogAndFail(@"%@ signature verification failed: %@.", self.logTag, nsError);
        return NO;
    }
    if (!isValid) {
        OWSProdLogAndFail(@"%@ signatures do not match.", self.logTag);
        return NO;
    }
    DDLogVerbose(@"%@ signature verification succeeded.", self.logTag);
    return YES;
}

+ (BOOL)verifyDistinguishedName:(SecCertificateRef)certificate
{
    OWSAssert(certificate);

    NSString *expectedDistinguishedName
        = @"CN=Intel SGX Attestation Report Signing,O=Intel Corporation,L=Santa Clara,ST=CA,C=US";

    // The Security framework doesn't offer access to certificate details like the name.
    // TODO: Use OpenSSL to extract the name.
    return YES;
}

@end

NS_ASSUME_NONNULL_END
