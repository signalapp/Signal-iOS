//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFingerprint.h"
#import "NSData+Base64.h"
#import "OWSError.h"
#import "OWSFingerprintProtos.pb.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIImage.h>

NS_ASSUME_NONNULL_BEGIN

static uint32_t const OWSFingerprintHashingVersion = 0;
static uint32_t const OWSFingerprintScannableFormatVersion = 1;
static uint32_t const OWSFingerprintDefaultHashIterations = 5200;

@interface OWSFingerprint ()

@property (nonatomic, readonly) NSUInteger hashIterations;
@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) NSData *myFingerprintData;
@property (nonatomic, readonly) NSData *theirFingerprintData;
@property (nonatomic, readonly) NSString *theirName;

@end

@implementation OWSFingerprint

- (instancetype)initWithMyStableId:(NSString *)myStableId
                     myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                     theirStableId:(NSString *)theirStableId
                  theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                         theirName:(NSString *)theirName
                    hashIterations:(uint32_t)hashIterations
{
    OWSAssert(theirIdentityKeyWithoutKeyType.length == 32);
    OWSAssert(myIdentityKeyWithoutKeyType.length == 32);

    self = [super init];
    if (!self) {
        return self;
    }

    _myStableIdData = [myStableId dataUsingEncoding:NSUTF8StringEncoding];
    _myIdentityKey = [myIdentityKeyWithoutKeyType prependKeyType];
    _theirStableId = theirStableId;
    _theirStableIdData = [theirStableId dataUsingEncoding:NSUTF8StringEncoding];
    _theirIdentityKey = [theirIdentityKeyWithoutKeyType prependKeyType];
    _theirName = theirName;
    _hashIterations = hashIterations;

    _myFingerprintData = [self dataForStableId:_myStableIdData publicKey:_myIdentityKey];
    _theirFingerprintData = [self dataForStableId:_theirStableIdData publicKey:_theirIdentityKey];

    return self;
}

+ (instancetype)fingerprintWithMyStableId:(NSString *)myStableId
                            myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableId:(NSString *)theirStableId
                         theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                                theirName:(NSString *)theirName
                           hashIterations:(uint32_t)hashIterations
{
    return [[self alloc] initWithMyStableId:myStableId
                              myIdentityKey:myIdentityKeyWithoutKeyType
                              theirStableId:theirStableId
                           theirIdentityKey:theirIdentityKeyWithoutKeyType
                                  theirName:theirName
                             hashIterations:hashIterations];
}

+ (instancetype)fingerprintWithMyStableId:(NSString *)myStableId
                            myIdentityKey:(NSData *)myIdentityKeyWithoutKeyType
                            theirStableId:(NSString *)theirStableId
                         theirIdentityKey:(NSData *)theirIdentityKeyWithoutKeyType
                                theirName:(NSString *)theirName
{
    return [[self alloc] initWithMyStableId:myStableId
                              myIdentityKey:myIdentityKeyWithoutKeyType
                              theirStableId:theirStableId
                           theirIdentityKey:theirIdentityKeyWithoutKeyType
                                  theirName:theirName
                             hashIterations:OWSFingerprintDefaultHashIterations];
}

- (BOOL)matchesLogicalFingerprintsData:(NSData *)data error:(NSError **)error
{
    OWSFingerprintProtosLogicalFingerprints *logicalFingerprints;
    @try {
        logicalFingerprints = [OWSFingerprintProtosLogicalFingerprints parseFromData:data];
    } @catch (NSException *exception) {
        if ([exception.name isEqualToString:@"InvalidProtocolBuffer"]) {
            NSString *description = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILURE_INVALID_QRCODE", @"alert body");
            *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
            return NO;
        } else {
            // Sync log in case we bail.
            DDLogError(@"%@ parsing QRCode data failed with error: %@", self.logTag, exception);
            @throw exception;
        }
    }

    if (logicalFingerprints.version < OWSFingerprintScannableFormatVersion) {
        DDLogWarn(@"%@ Verification failed. They're running an old version.", self.logTag);
        NSString *description
            = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_OLD_REMOTE_VERSION", @"alert body");
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    if (logicalFingerprints.version > OWSFingerprintScannableFormatVersion) {
        DDLogWarn(@"%@ Verification failed. We're running an old version.", self.logTag);
        NSString *description = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_WITH_OLD_LOCAL_VERSION", @"alert body");
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    // Their local is *our* remote.
    OWSFingerprintProtosLogicalFingerprint *localFingerprint = logicalFingerprints.remoteFingerprint;
    OWSFingerprintProtosLogicalFingerprint *remoteFingerprint = logicalFingerprints.localFingerprint;

    if (![remoteFingerprint.identityData isEqual:[self scannableData:self.theirFingerprintData]]) {
        DDLogWarn(@"%@ Verification failed. We have the wrong fingerprint for them", self.logTag);
        NSString *descriptionFormat = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_I_HAVE_WRONG_KEY_FOR_THEM",
            @"Alert body when verifying with {{contact name}}");
        NSString *description = [NSString stringWithFormat:descriptionFormat, self.theirName];
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    if (![localFingerprint.identityData isEqual:[self scannableData:self.myFingerprintData]]) {
        DDLogWarn(@"%@ Verification failed. They have the wrong fingerprint for us", self.logTag);
        NSString *descriptionFormat = NSLocalizedString(@"PRIVACY_VERIFICATION_FAILED_THEY_HAVE_WRONG_KEY_FOR_ME",
            @"Alert body when verifying with {{contact name}}");
        NSString *description = [NSString stringWithFormat:descriptionFormat, self.theirName];
        *error = OWSErrorWithCodeDescription(OWSErrorCodePrivacyVerificationFailure, description);
        return NO;
    }

    DDLogWarn(@"%@ Verification Succeeded.", self.logTag);
    return YES;
}

- (NSString *)text
{
    NSString *myDisplayString = [self stringForFingerprintData:self.myFingerprintData];
    NSString *theirDisplayString = [self stringForFingerprintData:self.theirFingerprintData];

    if ([theirDisplayString compare:myDisplayString] == NSOrderedAscending) {
        return [NSString stringWithFormat:@"%@%@", theirDisplayString, myDisplayString];
    } else {
        return [NSString stringWithFormat:@"%@%@", myDisplayString, theirDisplayString];
    }
}

/**
 * Formats numeric fingerprint, 3 lines in groups of 5 digits.
 */
- (NSString *)displayableText
{
    NSString *input = self.text;

    NSMutableArray<NSString *> *lines = [NSMutableArray new];

    NSUInteger lineLength = self.text.length / 3;
    for (uint i = 0; i < 3; i++) {
        NSString *line = [input substringWithRange:NSMakeRange(i * lineLength, lineLength)];

        NSMutableArray<NSString *> *chunks = [NSMutableArray new];
        for (uint i = 0; i < line.length / 5; i++) {
            NSString *nextChunk = [line substringWithRange:NSMakeRange(i * 5, 5)];
            [chunks addObject:nextChunk];
        }
        [lines addObject:[chunks componentsJoinedByString:@" "]];
    }

    return [lines componentsJoinedByString:@"\n"];
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
 * @param stableIdData
 *      Immutable global identifier e.g. Signal Identifier, an e164 formatted phone number encoded as UTF-8 data
 * @param publicKey
 *      The current public key for <stableId>
 * @return
 *      All-number textual representation
 */
- (NSData *)dataForStableId:(NSData *)stableIdData publicKey:(NSData *)publicKey
{
    OWSAssert(stableIdData);
    OWSAssert(publicKey);

    NSData *versionData = [self dataFromShort:OWSFingerprintHashingVersion];
    NSMutableData *hash = [NSMutableData dataWithData:versionData];
    [hash appendData:publicKey];
    [hash appendData:stableIdData];

    NSMutableData *_Nullable digestData = [[NSMutableData alloc] initWithLength:CC_SHA512_DIGEST_LENGTH];
    if (!digestData) {
        @throw [NSException exceptionWithName:NSGenericException reason:@"Couldn't allocate buffer." userInfo:nil];
    }
    for (int i = 0; i < self.hashIterations; i++) {
        [hash appendData:publicKey];

        if (hash.length >= UINT32_MAX) {
            @throw [NSException exceptionWithName:@"Oversize Data" reason:@"Oversize hash." userInfo:nil];
        }

        CC_SHA512(hash.bytes, (uint32_t)hash.length, digestData.mutableBytes);
        // TODO get rid of this loop-allocation
        hash = [digestData copy];
    }

    return [hash copy];
}


- (NSString *)stringForFingerprintData:(NSData *)data
{
    OWSAssert(data);

    return [NSString stringWithFormat:@"%@%@%@%@%@%@",
                     [self encodedChunkFromData:data offset:0],
                     [self encodedChunkFromData:data offset:5],
                     [self encodedChunkFromData:data offset:10],
                     [self encodedChunkFromData:data offset:15],
                     [self encodedChunkFromData:data offset:20],
                     [self encodedChunkFromData:data offset:25]];
}

- (NSString *)encodedChunkFromData:(NSData *)data offset:(uint)offset
{
    OWSAssert(data);

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

- (NSData *)scannableData:(NSData *)data
{
    return [data subdataWithRange:NSMakeRange(0, 32)];
}

- (nullable UIImage *)image
{
    OWSFingerprintProtosLogicalFingerprintsBuilder *logicalFingerprintsBuilder =
        [OWSFingerprintProtosLogicalFingerprintsBuilder new];

    logicalFingerprintsBuilder.version = OWSFingerprintScannableFormatVersion;

    OWSFingerprintProtosLogicalFingerprintBuilder *remoteFingerprintBuilder =
        [OWSFingerprintProtosLogicalFingerprintBuilder new];

    remoteFingerprintBuilder.identityData = [self scannableData:self.theirFingerprintData];
    logicalFingerprintsBuilder.remoteFingerprint = [remoteFingerprintBuilder build];

    OWSFingerprintProtosLogicalFingerprintBuilder *localFingerprintBuilder =
        [OWSFingerprintProtosLogicalFingerprintBuilder new];

    localFingerprintBuilder.identityData = [self scannableData:self.myFingerprintData];
    logicalFingerprintsBuilder.localFingerprint = [localFingerprintBuilder build];

    // Build ByteMode QR (Latin-1 encodable data)
    NSData *fingerprintData = [logicalFingerprintsBuilder build].data;

    DDLogDebug(@"%@ Building fingerprint with data: %@", self.logTag, fingerprintData);

    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    [filter setValue:fingerprintData forKey:@"inputMessage"];

    CIImage *ciImage = [filter outputImage];
    if (!ciImage) {
        DDLogError(@"%@ Failed to create QR image from fingerprint text: %@", self.logTag, self.text);
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

@end

NS_ASSUME_NONNULL_END
