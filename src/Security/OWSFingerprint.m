//  Created by Michael Kirk on 9/14/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFingerprint.h"
#import "NSData+Base64.h"
#import "OWSError.h"
#import "OWSFingerprintProtos.pb.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIImage.h>

NS_ASSUME_NONNULL_BEGIN

static uint32_t const OWSFingerprintVersion = 0;
static uint32_t const OWSFingerprintDefaultHashIterations = 5200;

@interface OWSFingerprint ()

@property (nonatomic, readonly) NSUInteger hashIterations;
@property (nonatomic, readonly) NSString *text;

@end

@implementation OWSFingerprint

- (instancetype)initWithMyStableId:(NSString *)myStableId
                     myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                     theirStableId:(NSString *)theirStableId
                  theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                    hashIterations:(uint32_t)hashIterations
{
    self = [super init];
    if (!self) {
        return self;
    }

    _myStableIdData = [myStableId dataUsingEncoding:NSUTF8StringEncoding];
    _myIdentityKey = [myIdentityKeyWithoutKeyType prependKeyType];
    _theirStableId = theirStableId;
    _theirStableIdData = [theirStableId dataUsingEncoding:NSUTF8StringEncoding];
    _theirIdentityKey = [theirIdentityKeyWithoutKeyType prependKeyType];
    _hashIterations = hashIterations;
    _text = [self generateText];
    _image = [self generateImage];

    return self;
}

+ (instancetype)fingerprintWithMyStableId:(NSString *)myStableId
                            myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableId:(NSString *)theirStableId
                         theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                           hashIterations:(uint32_t)hashIterations
{
    return [[self alloc] initWithMyStableId:myStableId
                              myIdentityKey:myIdentityKeyWithoutKeyType
                              theirStableId:theirStableId
                           theirIdentityKey:theirIdentityKeyWithoutKeyType
                             hashIterations:hashIterations];
}

+ (instancetype)fingerprintWithMyStableId:(NSString *)myStableId
                            myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableId:(NSString *)theirStableId
                         theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
{
    return [[self alloc] initWithMyStableId:myStableId
                              myIdentityKey:myIdentityKeyWithoutKeyType
                              theirStableId:theirStableId
                           theirIdentityKey:theirIdentityKeyWithoutKeyType
                             hashIterations:OWSFingerprintDefaultHashIterations];
}

- (BOOL)matchesCombinedFingerprintData:(NSData *)data error:(NSError **)error
{
    OWSFingerprintProtosCombinedFingerprint *combinedFingerprint;
    @try {
        combinedFingerprint = [OWSFingerprintProtosCombinedFingerprint parseFromData:data];
    } @catch (NSException *exception) {
        if ([exception.name isEqualToString:@"InvalidProtocolBuffer"]) {
            NSString *description = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILURE_INVALID_QRCODE", @"alert body");
            *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
            return NO;
        } else {
            // Sync log in case we bail.
            NSLog(@"%@ parsing QRCode data failed with error: %@", self.tag, exception);
            @throw exception;
        }
    }

    if (combinedFingerprint.version < OWSFingerprintVersion) {
        DDLogWarn(@"%@ Verification failed. We're running an old version.", self.tag);
        NSString *description
            = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_OLD_REMOTE_VERSION", @"alert body");
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    if (combinedFingerprint.version > OWSFingerprintVersion) {
        DDLogWarn(@"%@ Verification failed. They're running an old version.", self.tag);
        NSString *description = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_OLD_LOCAL_VERSION", @"alert body");
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    // Their local is *our* remote.
    OWSFingerprintProtosFingerprintData *localFingerprint = combinedFingerprint.remoteFingerprint;
    OWSFingerprintProtosFingerprintData *remoteFingerprint = combinedFingerprint.localFingerprint;

    if (![remoteFingerprint.identifier isEqual:self.theirStableIdData]) {
        DDLogWarn(@"%@ Verification failed. We're expecting a different contact.", self.tag);
        NSString *errorFormat = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_MISMATCHED_REMOTE_IDENTIFIER",
            @"Alert body {{expected phone number}}, {{actual phone number we found}}");
        NSString *expected = [[NSString alloc] initWithData:self.theirStableIdData encoding:NSUTF8StringEncoding];
        NSString *actual = [[NSString alloc] initWithData:remoteFingerprint.identifier encoding:NSUTF8StringEncoding];
        NSString *description = [NSString stringWithFormat:errorFormat, expected, actual];

        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    if (![localFingerprint.identifier isEqual:self.myStableIdData]) {
        DDLogWarn(@"%@ Verification failed. They presented the wrong fingerprint.", self.tag);
        NSString *errorFormat = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_MISMATCHED_LOCAL_IDENTIFIER",
            @"Alert body {{expected phone number}}, {{actual phone number we found}}");
        NSString *expected = [[NSString alloc] initWithData:self.myStableIdData encoding:NSUTF8StringEncoding];
        NSString *actual = [[NSString alloc] initWithData:localFingerprint.identifier encoding:NSUTF8StringEncoding];
        NSString *description = [NSString stringWithFormat:errorFormat, expected, actual];

        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    if (![localFingerprint.publicKey isEqual:self.myIdentityKey]) {
        DDLogWarn(@"%@ Verification failed. They have the wrong key for us", self.tag);
        NSString *description = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_MISMATCHED_KEYS", @"Alert body");
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    if (![remoteFingerprint.publicKey isEqual:self.theirIdentityKey]) {
        DDLogWarn(@"%@ Verification failed. We have the wrong key for them", self.tag);
        NSString *description = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_MISMATCHED_KEYS", @"Alert body");
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    DDLogWarn(@"%@ Verification Succeeded.", self.tag);
    return YES;
}


- (NSString *)generateText
{
    NSString *myDisplayString = [self stringForStableId:self.myStableIdData publicKey:self.myIdentityKey];
    NSString *theirDisplayString = [self stringForStableId:self.theirStableIdData publicKey:self.theirIdentityKey];

    if ([theirDisplayString compare:myDisplayString] == NSOrderedAscending) {
        return [NSString stringWithFormat:@"%@%@", theirDisplayString, myDisplayString];
    } else {
        return [NSString stringWithFormat:@"%@%@", myDisplayString, theirDisplayString];
    }
}

- (NSString *)displayableText
{
    NSString *input = self.text;

    NSMutableArray<NSString *> *chunks = [NSMutableArray new];
    for (uint i = 0; i < input.length / 5; i++) {
        NSString *nextChunk = [input substringWithRange:NSMakeRange(i * 5, 5)];
        [chunks addObject:nextChunk];
    }
    return [chunks componentsJoinedByString:@" "];
}


- (NSData *)dataFromShort:(uint32_t)aShort
{
    uint8_t bytes[] = {
        ((uint8_t)(aShort & 0xFF00) >> 8),
        (uint8_t)(aShort & 0x00FF)
    };

    return [NSData dataWithBytes:bytes length:2];
}

/**
 * An identifier for a mutable public key, belonging to an immutable identifier (stableId).
 *
 * This method is intended to be somewhat expensive to produce in order to be brute force adverse.
 *
 * @param stableId
 *      Immutable global identifier e.g. Signal Identifier, an e164 formatted phone number encoded as UTF-8 data
 * @param publicKey
 *      The current public key for <stableId>
 * @return
 *      All-number textual representation
 */
- (NSString *)stringForStableId:(NSData *)stableIdData publicKey:(NSData *)publicKey
{
    NSData *versionData = [self dataFromShort:OWSFingerprintVersion];
    NSMutableData *hash = [NSMutableData dataWithData:versionData];
    [hash appendData:publicKey];
    [hash appendData:stableIdData];

    uint8_t digest[CC_SHA512_DIGEST_LENGTH];
    for (int i = 0; i < self.hashIterations; i++) {
        [hash appendData:publicKey];
        CC_SHA512(hash.bytes, (unsigned int)hash.length, digest);
        // TODO get rid of this loop-allocation
        hash = [NSMutableData dataWithBytes:digest length:CC_SHA512_DIGEST_LENGTH];
    }

    return [NSString stringWithFormat:@"%@%@%@%@%@%@",
                     [self encodedChunkFromData:hash offset:0],
                     [self encodedChunkFromData:hash offset:5],
                     [self encodedChunkFromData:hash offset:10],
                     [self encodedChunkFromData:hash offset:15],
                     [self encodedChunkFromData:hash offset:20],
                     [self encodedChunkFromData:hash offset:25]];
}

- (NSString *)encodedChunkFromData:(NSData *)data offset:(uint)offset
{
    uint8_t fiveBytes[5];
    [data getBytes:fiveBytes range:NSMakeRange(offset, 5)];

    int chunk = [self uint64From5Bytes:fiveBytes] % 100000;
    return [NSString stringWithFormat:@"%05d", chunk];
}

- (int64_t)uint64From5Bytes:(uint8_t[])bytes
{
    int64_t result = ((bytes[0] & 0xffLL) << 32) |
           ((bytes[1] & 0xffLL) << 24) |
           ((bytes[2] & 0xffLL) << 16) |
           ((bytes[3] & 0xffLL) <<  8) |
           ((bytes[4] & 0xffLL));

    return result;
}

- (nullable UIImage *)generateImage
{
    OWSFingerprintProtosCombinedFingerprintBuilder *combinedFingerprintBuilder =
        [OWSFingerprintProtosCombinedFingerprintBuilder new];

    [combinedFingerprintBuilder setVersion:OWSFingerprintVersion];

    OWSFingerprintProtosFingerprintDataBuilder *remoteFingerprintDataBuilder =
        [OWSFingerprintProtosFingerprintDataBuilder new];
    [remoteFingerprintDataBuilder setPublicKey:self.theirIdentityKey];
    [remoteFingerprintDataBuilder setIdentifier:self.theirStableIdData];
    [combinedFingerprintBuilder setRemoteFingerprintBuilder:remoteFingerprintDataBuilder];

    OWSFingerprintProtosFingerprintDataBuilder *localFingerprintDataBuilder =
        [OWSFingerprintProtosFingerprintDataBuilder new];
    [localFingerprintDataBuilder setPublicKey:self.myIdentityKey];
    [localFingerprintDataBuilder setIdentifier:self.myStableIdData];
    [combinedFingerprintBuilder setLocalFingerprintBuilder:localFingerprintDataBuilder];

    // Build ByteMode QR (Latin-1 encodable data)
    NSData *fingerprintData = [combinedFingerprintBuilder build].data;
    DDLogDebug(@"%@ Building fingerprint with data: %@", self.tag, fingerprintData);

    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    [filter setValue:fingerprintData forKey:@"inputMessage"];

    CIImage *ciImage = [filter outputImage];
    if (!ciImage) {
        DDLogError(@"%@ Failed to create QR image from fingerprint text: %@", self.tag, self.text);
        return nil;
    }

    // UIImages backed by a CIImage won't render without antialiasing, so we convert the backign image to a CGImage,
    // which can be scaled crisply.
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
    UIImage *qrImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);

    return qrImage;
}

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
