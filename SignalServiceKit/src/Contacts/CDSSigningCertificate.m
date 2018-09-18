//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "CDSSigningCertificate.h"
#import "Cryptography.h"
#import "NSData+OWS.h"
#import <CommonCrypto/CommonCrypto.h>
#import <openssl/x509.h>

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
    OWSAssertDebug(certificatePem);

    CDSSigningCertificate *signingCertificate = [CDSSigningCertificate new];

    NSArray<NSData *> *_Nullable anchorCertificates = [self anchorCertificates];
    if (anchorCertificates.count < 1) {
        OWSFailDebug(@"Could not load anchor certificates.");
        return nil;
    }

    NSArray<NSData *> *_Nullable certificateDerDatas = [self convertPemToDer:certificatePem];

    if (certificateDerDatas.count < 1) {
        OWSFailDebug(@"Could not parse PEM.");
        return nil;
    }

    // The leaf is always the first certificate.
    NSData *_Nullable leafCertificateData = [certificateDerDatas firstObject];
    if (!leafCertificateData) {
        OWSFailDebug(@"Could not extract leaf certificate data.");
        return nil;
    }
    if (![self verifyDistinguishedNameOfCertificate:leafCertificateData]) {
        OWSFailDebug(@"Leaf certificate has invalid name.");
        return nil;
    }

    NSMutableArray *certificates = [NSMutableArray new];
    for (NSData *certificateDerData in certificateDerDatas) {
        SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certificateDerData));
        if (!certificate) {
            OWSFailDebug(@"Could not load DER.");
            return nil;
        }
        [certificates addObject:(__bridge_transfer id)certificate];
    }

    SecPolicyRef policy = SecPolicyCreateBasicX509();
    signingCertificate.policy = policy;
    if (!policy) {
        OWSFailDebug(@"Could not create policy.");
        return nil;
    }

    SecTrustRef trust;
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certificates, policy, &trust);
    signingCertificate.trust = trust;
    if (status != errSecSuccess) {
        OWSFailDebug(@"trust could not be created.");
        return nil;
    }
    if (!trust) {
        OWSFailDebug(@"Could not create trust.");
        return nil;
    }

    status = SecTrustSetNetworkFetchAllowed(trust, NO);
    if (status != errSecSuccess) {
        OWSFailDebug(@"trust fetch could not be configured.");
        return nil;
    }

    status = SecTrustSetAnchorCertificatesOnly(trust, YES);
    if (status != errSecSuccess) {
        OWSFailDebug(@"trust anchor certs could not be configured.");
        return nil;
    }

    NSMutableArray *pinnedCertificates = [NSMutableArray array];
    for (NSData *certificateData in anchorCertificates) {
        SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certificateData));
        if (!certificate) {
            OWSFailDebug(@"Could not load DER.");
            return nil;
        }

        [pinnedCertificates addObject:(__bridge_transfer id)certificate];
    }
    status = SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)pinnedCertificates);
    if (status != errSecSuccess) {
        OWSFailDebug(@"The anchor certificates couldn't be set.");
        return nil;
    }

    SecTrustResultType result;
    status = SecTrustEvaluate(trust, &result);
    if (status != errSecSuccess) {
        OWSFailDebug(@"Could not evaluate certificates.");
        return nil;
    }

    // `kSecTrustResultUnspecified` is confusingly named.  It indicates success.
    // See the comments in the header where it is defined.
    BOOL isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
    if (!isValid) {
        OWSFailDebug(@"Certificate evaluation failed.");
        return nil;
    }

    SecKeyRef publicKey = SecTrustCopyPublicKey(trust);
    signingCertificate.publicKey = publicKey;
    if (!publicKey) {
        OWSFailDebug(@"Could not extract public key.");
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
        OWSFailDebug(@"could parse regex: %@.", error);
        return nil;
    }

    [regex enumerateMatchesInString:pemString
                            options:0
                              range:NSMakeRange(0, pemString.length)
                         usingBlock:^(NSTextCheckingResult *_Nullable result, NSMatchingFlags flags, BOOL *stop) {
                             if (result.numberOfRanges != 2) {
                                 OWSFailDebug(@"invalid PEM regex match.");
                                 return;
                             }
                             NSString *_Nullable derString = [pemString substringWithRange:[result rangeAtIndex:1]];
                             if (derString.length < 1) {
                                 OWSFailDebug(@"empty PEM match.");
                                 return;
                             }
                             // dataFromBase64String will ignore whitespace, which is
                             // necessary.
                             NSData *_Nullable derData = [NSData dataFromBase64String:derString];
                             if (derData.length < 1) {
                                 OWSFailDebug(@"could not parse PEM match.");
                                 return;
                             }
                             [certificateDatas addObject:derData];
                         }];

    return certificateDatas;
}

+ (nullable NSArray<NSData *> *)anchorCertificates
{
    static NSArray<NSData *> *anchorCertificates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We need to use an Intel certificate as the anchor for IAS verification.
        NSData *_Nullable anchorCertificate = [self certificateDataForService:@"ias-root"];
        if (!anchorCertificate) {
            OWSFailDebug(@"could not load anchor certificate.");
            OWSRaiseException(@"OWSSignalService_CouldNotLoadCertificate", @"%s", __PRETTY_FUNCTION__);
        } else {
            anchorCertificates = @[ anchorCertificate ];
        }
    });
    return anchorCertificates;
}

+ (nullable NSData *)certificateDataForService:(NSString *)service
{
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *path = [bundle pathForResource:service ofType:@"cer"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        OWSFailDebug(@"could not locate certificate file.");
        return nil;
    }

    NSData *_Nullable certificateData = [NSData dataWithContentsOfFile:path];
    return certificateData;
}

- (BOOL)verifySignatureOfBody:(NSString *)body signature:(NSData *)signature
{
    OWSAssertDebug(self.publicKey);

    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];

    size_t signedHashBytesSize = SecKeyGetBlockSize(self.publicKey);
    const void *signedHashBytes = [signature bytes];

    NSData *_Nullable hashData = [Cryptography computeSHA256Digest:bodyData];
    if (hashData.length != CC_SHA256_DIGEST_LENGTH) {
        OWSFailDebug(@"could not SHA256 for signature verification.");
        return NO;
    }
    size_t hashBytesSize = CC_SHA256_DIGEST_LENGTH;
    const void *hashBytes = [hashData bytes];

    OSStatus status = SecKeyRawVerify(
        self.publicKey, kSecPaddingPKCS1SHA256, hashBytes, hashBytesSize, signedHashBytes, signedHashBytesSize);

    BOOL isValid = status == errSecSuccess;
    if (!isValid) {
        OWSFailDebug(@"signatures do not match.");
        return NO;
    }
    return YES;
}

+ (BOOL)verifyDistinguishedNameOfCertificate:(NSData *)certificateData
{
    OWSAssertDebug(certificateData);

    // The Security framework doesn't offer access to certificate properties
    // with API available on iOS 9. We use OpenSSL to extract the name.
    NSDictionary<NSString *, NSString *> *_Nullable properties = [self propertiesForCertificate:certificateData];
    if (!properties) {
        OWSFailDebug(@"Could not retrieve certificate properties.");
        return NO;
    }
    //    NSString *expectedDistinguishedName
    //    = @"CN=Intel SGX Attestation Report Signing,O=Intel Corporation,L=Santa Clara,ST=CA,C=US";
    NSDictionary<NSString *, NSString *> *expectedProperties = @{
        @(SN_commonName) : // "CN"
            @"Intel SGX Attestation Report Signing",
        @(SN_organizationName) : // "O"
            @"Intel Corporation",
        @(SN_localityName) : // "L"
            @"Santa Clara",
        @(SN_stateOrProvinceName) : // "ST"
            @"CA",
        @(SN_countryName) : // "C"
            @"US",
    };

    if (![properties isEqualToDictionary:expectedProperties]) {
        OWSFailDebug(@"Unexpected certificate properties. %@ != %@", expectedProperties, properties);
        return NO;
    }
    return YES;
}

+ (nullable NSDictionary<NSString *, NSString *> *)propertiesForCertificate:(NSData *)certificateData
{
    OWSAssertDebug(certificateData);

    if (certificateData.length >= UINT32_MAX) {
        OWSFailDebug(@"certificate data is too long.");
        return nil;
    }
    const unsigned char *certificateDataBytes = (const unsigned char *)[certificateData bytes];
    X509 *_Nullable certificateX509 = d2i_X509(NULL, &certificateDataBytes, [certificateData length]);
    if (!certificateX509) {
        OWSFailDebug(@"could not parse certificate.");
        return nil;
    }

    X509_NAME *_Nullable subjectName = X509_get_subject_name(certificateX509);
    if (!subjectName) {
        OWSFailDebug(@"could not extract subject name.");
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *certificateProperties = [NSMutableDictionary new];
    for (NSString *oid in @[
             @(SN_commonName), // "CN"
             @(SN_organizationName), // "O"
             @(SN_localityName), // "L"
             @(SN_stateOrProvinceName), // "ST"
             @(SN_countryName), // "C"
         ]) {
        int nid = OBJ_txt2nid(oid.UTF8String);
        int index = X509_NAME_get_index_by_NID(subjectName, nid, -1);

        X509_NAME_ENTRY *_Nullable entry = X509_NAME_get_entry(subjectName, index);
        if (!entry) {
            OWSFailDebug(@"could not extract entry.");
            return nil;
        }

        ASN1_STRING *_Nullable entryData = X509_NAME_ENTRY_get_data(entry);
        if (!entryData) {
            OWSFailDebug(@"could not extract entry data.");
            return nil;
        }

        unsigned char *entryName = ASN1_STRING_data(entryData);
        if (entryName == NULL) {
            OWSFailDebug(@"could not extract entry string.");
            return nil;
        }
        NSString *_Nullable entryString = [NSString stringWithUTF8String:(char *)entryName];
        if (!entryString) {
            OWSFailDebug(@"could not parse entry name data.");
            return nil;
        }
        certificateProperties[oid] = entryString;
    }
    return certificateProperties;
}

@end

NS_ASSUME_NONNULL_END
