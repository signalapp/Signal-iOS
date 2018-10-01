//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCertificateExpiration.h"
#import "OWSFileSystem.h"
#import <CommonCrypto/CommonCrypto.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <openssl/x509.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCertificateExpiration

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

+ (nullable NSDate *)expirationDataForCertificate:(NSData *)certificateData
{
    OWSAssertDebug(certificateData);

    NSString *temporaryFilePath = [OWSFileSystem temporaryFilePath];
    [certificateData writeToFile:temporaryFilePath atomically:YES];
    OWSLogInfo(@"temporaryFilePath: %@", temporaryFilePath);

    OWSLogInfo(@"certificateData: %@", certificateData.hexadecimalString);
    NSString *pemString = [[NSString alloc] initWithData:certificateData encoding:NSUTF8StringEncoding];
    OWSLogInfo(@"pemString: %@", pemString);
    [DDLog flushLog];

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

    ASN1_TIME *not_after = X509_get_notAfter(certificateX509);
    OWSAssert(not_after);

    BIO *b = BIO_new(BIO_s_mem());
    int rc = ASN1_TIME_print(b, not_after);
    if (rc <= 0) {
        OWSLogError(@"ASN1_TIME_print() failed.");
        BIO_free(b);
        return nil;
    }

    const NSUInteger kASN1TimeBufferLength = 128;
    char buffer[kASN1TimeBufferLength];
    rc = BIO_gets(b, buffer, kASN1TimeBufferLength);
    if (rc <= 0) {
        OWSLogError(@"BIO_gets() failed.");
        BIO_free(b);
        return nil;
    }
    BIO_free(b);

    return nil;
}
@end

NS_ASSUME_NONNULL_END
