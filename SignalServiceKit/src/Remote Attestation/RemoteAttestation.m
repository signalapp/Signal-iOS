//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "RemoteAttestation.h"
#import "NSError+OWSOperation.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "RemoteAttestationQuote.h"
#import "RemoteAttestationSigningCertificate.h"
#import "SSKEnvironment.h"
#import "TSNetworkManager.h"
#import <Curve25519Kit/Curve25519.h>
#import <HKDFKit/HKDFKit.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorUserInfoKey const RemoteAttestationErrorKey_Reason = @"RemoteAttestationErrorKey_Reason";
NSErrorDomain const RemoteAttestationErrorDomain = @"SignalServiceKit.RemoteAttestation";

NSError *RemoteAttestationErrorMakeWithReason(NSInteger code, NSString *reason)
{
    OWSCFailDebug(@"Error: %@", reason);
    return [NSError errorWithDomain:RemoteAttestationErrorDomain
                               code:code
                           userInfo:@{ RemoteAttestationErrorKey_Reason : reason }];
}

NSString *NSStringForRemoteAttestationService(RemoteAttestationService value) {
    switch (value) {
        case RemoteAttestationServiceContactDiscovery:
            return @"ContactDiscovery";
        case RemoteAttestationServiceKeyBackup:
            return @"KeyBackup";
    }
}

@interface RemoteAttestationAuth ()

@property (nonatomic) NSString *username;
@property (nonatomic) NSString *password;

@end

#pragma mark -

@implementation RemoteAttestationAuth

@end

#pragma mark -

@interface RemoteAttestationKeys ()

@property (nonatomic) ECKeyPair *clientEphemeralKeyPair;
@property (nonatomic) NSData *serverEphemeralPublic;
@property (nonatomic) NSData *serverStaticPublic;

@property (nonatomic) OWSAES256Key *clientKey;
@property (nonatomic) OWSAES256Key *serverKey;

@end

#pragma mark -

@implementation RemoteAttestationKeys

- (nullable RemoteAttestationKeys *)initWithClientEphemeralKeyPair:(ECKeyPair *)clientEphemeralKeyPair
                                             serverEphemeralPublic:(NSData *)serverEphemeralPublic
                                                serverStaticPublic:(NSData *)serverStaticPublic
                                                             error:(NSError **)error
{
    self = [super init];
    
    if (!clientEphemeralKeyPair) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"Missing clientEphemeralKeyPair");
        return nil;
    }
    if (serverEphemeralPublic.length < 1) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"Invalid serverEphemeralPublic");
        return nil;
    }
    if (serverStaticPublic.length < 1) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"Invalid serverStaticPublic");
        return nil;
    }
    _clientEphemeralKeyPair = clientEphemeralKeyPair;
    _serverEphemeralPublic = serverEphemeralPublic;
    _serverStaticPublic = serverStaticPublic;
    if (![self deriveKeys]) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"failed to derive keys");
        return nil;
    }
    return self;
}

// Returns YES on success.
- (BOOL)deriveKeys
{
    NSData *ephemeralToEphemeral;
    NSData *ephemeralToStatic;
    @try {
        ephemeralToEphemeral =
            [Curve25519 throws_generateSharedSecretFromPublicKey:self.serverEphemeralPublic andKeyPair:self.clientEphemeralKeyPair];
        ephemeralToStatic =
            [Curve25519 throws_generateSharedSecretFromPublicKey:self.serverStaticPublic andKeyPair:self.clientEphemeralKeyPair];
    } @catch (NSException *exception) {
        OWSFailDebug(@"could not generate shared secrets: %@", exception);
        return NO;
    }

    NSData *masterSecret = [ephemeralToEphemeral dataByAppendingData:ephemeralToStatic];
    NSData *publicKeys = [NSData join:@[
        self.clientEphemeralKeyPair.publicKey,
        self.serverEphemeralPublic,
        self.serverStaticPublic,
    ]];

    NSData *_Nullable derivedMaterial;
    @try {
        derivedMaterial =
            [HKDFKit throws_deriveKey:masterSecret info:nil salt:publicKeys outputSize:(int)kAES256_KeyByteLength * 2];
    } @catch (NSException *exception) {
        OWSFailDebug(@"could not derive service key: %@", exception);
        return NO;
    }

    if (!derivedMaterial) {
        OWSFailDebug(@"missing derived service key.");
        return NO;
    }
    if (derivedMaterial.length != kAES256_KeyByteLength * 2) {
        OWSFailDebug(@"derived service key has unexpected length.");
        return NO;
    }

    NSData *_Nullable clientKeyData =
        [derivedMaterial subdataWithRange:NSMakeRange(kAES256_KeyByteLength * 0, kAES256_KeyByteLength)];
    OWSAES256Key *_Nullable clientKey = [OWSAES256Key keyWithData:clientKeyData];
    if (!clientKey) {
        OWSFailDebug(@"clientKey has unexpected length.");
        return NO;
    }

    NSData *_Nullable serverKeyData =
        [derivedMaterial subdataWithRange:NSMakeRange(kAES256_KeyByteLength * 1, kAES256_KeyByteLength)];
    OWSAES256Key *_Nullable serverKey = [OWSAES256Key keyWithData:serverKeyData];
    if (!serverKey) {
        OWSFailDebug(@"serverKey has unexpected length.");
        return NO;
    }

    self.clientKey = clientKey;
    self.serverKey = serverKey;

    return YES;
}

@end

#pragma mark -

@interface SignatureBodyEntity : NSObject

@property (nonatomic) NSData *isvEnclaveQuoteBody;
@property (nonatomic) NSString *isvEnclaveQuoteStatus;
@property (nonatomic) NSString *timestamp;
@property (nonatomic) NSNumber *version;

@end

#pragma mark -

@implementation SignatureBodyEntity

@end

#pragma mark -

@interface NSDictionary (RemoteAttestation)

@end

#pragma mark -

@implementation NSDictionary (RemoteAttestation)

- (nullable NSString *)stringForKey:(NSString *)key
{
    NSString *_Nullable valueString = self[key];
    if (![valueString isKindOfClass:[NSString class]]) {
        OWSFailDebug(@"couldn't parse string for key: %@", key);
        return nil;
    }
    return valueString;
}

- (nullable NSNumber *)numberForKey:(NSString *)key
{
    NSNumber *_Nullable value = self[key];
    if (![value isKindOfClass:[NSNumber class]]) {
        OWSFailDebug(@"couldn't parse number for key: %@", key);
        return nil;
    }
    return value;
}

- (nullable NSData *)base64DataForKey:(NSString *)key
{
    NSString *_Nullable valueString = self[key];
    if (![valueString isKindOfClass:[NSString class]]) {
        OWSFailDebug(@"couldn't parse base 64 value for key: %@", key);
        return nil;
    }
    NSData *_Nullable valueData = [[NSData alloc] initWithBase64EncodedString:valueString options:0];
    if (!valueData) {
        OWSFailDebug(@"couldn't decode base 64 value for key: %@", key);
        return nil;
    }
    return valueData;
}

- (nullable NSData *)base64DataForKey:(NSString *)key expectedLength:(NSUInteger)expectedLength
{
    NSData *_Nullable valueData = [self base64DataForKey:key];
    if (valueData && valueData.length != expectedLength) {
        OWSLogDebug(@"decoded base 64 value for key: %@, has unexpected length: %lu != %lu",
            key,
            (unsigned long)valueData.length,
            (unsigned long)expectedLength);
        OWSFailDebug(@"decoded base 64 value for key has unexpected length: %lu != %lu",
            (unsigned long)valueData.length,
            (unsigned long)expectedLength);
        return nil;
    }
    return valueData;
}

@end

#pragma mark -

@implementation RemoteAttestation

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

- (instancetype)initWithCookies:(NSArray<NSHTTPCookie *> *)cookies
                           keys:(RemoteAttestationKeys *)keys
                      requestId:(NSData *)requestId
                    enclaveName:(NSString *)enclaveName
                           auth:(RemoteAttestationAuth *)auth
{
    self = [super init];

    _cookies = cookies;
    _keys = keys;
    _requestId = requestId;
    _enclaveName = enclaveName;
    _auth = auth;

    return self;
}

+ (void)getRemoteAttestationAuthForService:(RemoteAttestationService)service
                                   success:(void (^)(RemoteAttestationAuth *))successHandler
                                   failure:(void (^)(NSError *error))failureHandler
{
    if (!self.tsAccountManager.isRegisteredAndReady) {
        return failureHandler(OWSErrorMakeGenericError(@"Not registered."));
    }

    if (SSKDebugFlags.internalLogging) {
        OWSLogInfo(@"service: %@", NSStringForRemoteAttestationService(service));
    }

    TSRequest *request = [OWSRequestFactory remoteAttestationAuthRequestForService:service];
    [[TSNetworkManager shared] makeRequest:request
      success:^(NSURLSessionDataTask *task, id responseDict) {

        if (SSKDebugFlags.internalLogging) {
            OWSAssertDebug([task.response isKindOfClass:NSHTTPURLResponse.class]);
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            OWSLogInfo(@"statusCode: %lu", (unsigned long) response.statusCode);
            for (NSString *header in response.allHeaderFields) {
                if ([response respondsToSelector:@selector(valueForHTTPHeaderField:)]) {
                    NSString *_Nullable headerValue = [response valueForHTTPHeaderField:header];
                    OWSLogInfo(@"Header: %@ -> %@", header, headerValue);
                } else {
                    OWSLogInfo(@"Header: %@", header);
                }
            }
            
#if TESTABLE_BUILD
            [TSNetworkManager logCurlForTask:task];
#endif
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
              RemoteAttestationAuth *_Nullable auth = [self parseAuthParams:responseDict];
              if (!auth) {
                  OWSLogError(@"remote attestation auth could not be parsed: %@", responseDict);
                  NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                  failureHandler(error);
                  return;
              }

              successHandler(auth);
          });
      }
      failure:^(NSURLSessionDataTask *task, NSError *error) {
          NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
          OWSLogVerbose(@"remote attestation auth failure: %lu", (unsigned long)response.statusCode);
          failureHandler(error);
      }];
}

+ (nullable RemoteAttestationAuth *)parseAuthParams:(id)response
{
    if (![response isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *responseDict = response;
    NSString *_Nullable password = [responseDict stringForKey:@"password"];
    if (password.length < 1) {
        OWSFailDebug(@"missing or empty password.");
        return nil;
    }

    NSString *_Nullable username = [responseDict stringForKey:@"username"];
    if (username.length < 1) {
        OWSFailDebug(@"missing or empty username.");
        return nil;
    }

    RemoteAttestationAuth *result = [RemoteAttestationAuth new];
    result.username = username;
    result.password = password;
    return result;
}

+ (BOOL)verifyIasSignatureWithCertificates:(NSString *)certificates
                             signatureBody:(NSString *)signatureBody
                                 signature:(NSData *)signature
                                 quoteData:(NSData *)quoteData
                                     error:(NSError **)error
{
    OWSAssertDebug(certificates.length > 0);
    OWSAssertDebug(signatureBody.length > 0);
    OWSAssertDebug(signature.length > 0);
    OWSAssertDebug(quoteData);

    NSError *signingError;
    RemoteAttestationSigningCertificate *_Nullable certificate =
        [RemoteAttestationSigningCertificate parseCertificateFromPem:certificates error:&signingError];
    if (signingError) {
        *error = signingError;
        return NO;
    }

    if (!certificate) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"could not parse signing certificate.");
        return NO;
    }
    if (![certificate verifySignatureOfBody:signatureBody signature:signature]) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"could not verify signature.");
        return NO;
    }

    SignatureBodyEntity *_Nullable signatureBodyEntity = [self parseSignatureBodyEntity:signatureBody];
    if (!signatureBodyEntity) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"could not parse signature body.");
        return NO;
    }

    // Compare the first N bytes of the quote data with the signed quote body.
    const NSUInteger kQuoteBodyComparisonLength = 432;
    if (signatureBodyEntity.isvEnclaveQuoteBody.length < kQuoteBodyComparisonLength) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"isvEnclaveQuoteBody has unexpected length.");
        return NO;
    }
    // NOTE: This version is separate from and does _NOT_ match the quote version.
    const NSUInteger kSignatureBodyVersion = 3;
    if (![signatureBodyEntity.version isEqual:@(kSignatureBodyVersion)]) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"signatureBodyEntity has unexpected version.");
        return NO;
    }
    if (quoteData.length < kQuoteBodyComparisonLength) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"quoteData has unexpected length.");
        return NO;
    }
    NSData *isvEnclaveQuoteBodyForComparison =
        [signatureBodyEntity.isvEnclaveQuoteBody subdataWithRange:NSMakeRange(0, kQuoteBodyComparisonLength)];
    NSData *quoteDataForComparison = [quoteData subdataWithRange:NSMakeRange(0, kQuoteBodyComparisonLength)];
    if (![isvEnclaveQuoteBodyForComparison ows_constantTimeIsEqualToData:quoteDataForComparison]) {
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"isvEnclaveQuoteBody and quoteData do not match.");
        return NO;
    }

    if (![@"OK" isEqualToString:signatureBodyEntity.isvEnclaveQuoteStatus]) {
        NSString *reason =
            [NSString stringWithFormat:@"invalid isvEnclaveQuoteStatus: %@", signatureBodyEntity.isvEnclaveQuoteStatus];
        *error = RemoteAttestationErrorMakeWithReason(RemoteAttestationAssertionError, reason);
        return NO;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSSSS"];

    // Specify parsing locale
    // from: https://developer.apple.com/library/archive/qa/qa1480/_index.html
    // Q:  I'm using NSDateFormatter to parse an Internet-style date, but this fails for some users in some regions.
    // I've set a specific date format string; shouldn't that force NSDateFormatter to work independently of the user's
    // region settings? A: No. While setting a date format string will appear to work for most users, it's not the right
    // solution to this problem. There are many places where format strings behave in unexpected ways. [...]
    NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setLocale:enUSPOSIXLocale];
    NSDate *timestampDate = [dateFormatter dateFromString:signatureBodyEntity.timestamp];
    if (!timestampDate) {
        OWSFailDebug(@"Could not parse signature body timestamp: %@", signatureBodyEntity.timestamp);
        *error = RemoteAttestationErrorMakeWithReason(
            RemoteAttestationAssertionError, @"could not parse signature body timestamp.");
        return NO;
    }

    // Only accept signatures from the last 24 hours.
    NSDateComponents *dayComponent = [[NSDateComponents alloc] init];
    dayComponent.day = 1;
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *timestampDatePlus1Day = [calendar dateByAddingComponents:dayComponent toDate:timestampDate options:0];

    NSDate *now = [NSDate new];
    BOOL isExpired = [now isAfterDate:timestampDatePlus1Day];

    if (isExpired) {
        if (SSKDebugFlags.internalLogging) {
            OWSLogInfo(@"signatureBody: %@", signatureBody);
            OWSLogInfo(@"signature: %@", signature);
        }
        if (SSKFeatureFlags.isUsingProductionService) {
            OWSFailDebug(@"Signature is expired: %@", signatureBodyEntity.timestamp);
            *error = RemoteAttestationErrorMakeWithReason(
                                                          RemoteAttestationAssertionError, @"Signature is expired.");
            return NO;
        }
    }

    return YES;
}

+ (nullable SignatureBodyEntity *)parseSignatureBodyEntity:(NSString *)signatureBody
{
    OWSAssertDebug(signatureBody.length > 0);

    NSError *error = nil;
    NSDictionary *_Nullable jsonDict =
        [NSJSONSerialization JSONObjectWithData:[signatureBody dataUsingEncoding:NSUTF8StringEncoding]
                                        options:0
                                          error:&error];
    if (error || ![jsonDict isKindOfClass:[NSDictionary class]]) {
        OWSFailDebug(@"could not parse signature body JSON: %@.", error);
        return nil;
    }
    NSString *_Nullable timestamp = [jsonDict stringForKey:@"timestamp"];
    if (timestamp.length < 1) {
        OWSFailDebug(@"could not parse signature timestamp.");
        return nil;
    }
    NSData *_Nullable isvEnclaveQuoteBody = [jsonDict base64DataForKey:@"isvEnclaveQuoteBody"];
    if (isvEnclaveQuoteBody.length < 1) {
        OWSFailDebug(@"could not parse signature isvEnclaveQuoteBody.");
        return nil;
    }
    NSString *_Nullable isvEnclaveQuoteStatus = [jsonDict stringForKey:@"isvEnclaveQuoteStatus"];
    if (isvEnclaveQuoteStatus.length < 1) {
        OWSFailDebug(@"could not parse signature isvEnclaveQuoteStatus.");
        return nil;
    }
    NSNumber *_Nullable version = [jsonDict numberForKey:@"version"];
    if (!version) {
        OWSFailDebug(@"could not parse signature version.");
        return nil;
    }

    SignatureBodyEntity *result = [SignatureBodyEntity new];
    result.isvEnclaveQuoteBody = isvEnclaveQuoteBody;
    result.isvEnclaveQuoteStatus = isvEnclaveQuoteStatus;
    result.timestamp = timestamp;
    result.version = version;
    return result;
}

+ (BOOL)verifyServerQuote:(RemoteAttestationQuote *)quote keys:(RemoteAttestationKeys *)keys mrenclave:(NSString *)mrenclave
{
    OWSAssertDebug(quote);
    OWSAssertDebug(keys);
    OWSAssertDebug(mrenclave.length > 0);

    if (quote.reportData.length < keys.serverStaticPublic.length) {
        OWSFailDebug(@"reportData has unexpected length: %lu != %lu.",
                     (unsigned long)quote.reportData.length,
                     (unsigned long)keys.serverStaticPublic.length);
        return NO;
    }

    NSData *_Nullable theirServerPublicStatic =
        [quote.reportData subdataWithRange:NSMakeRange(0, keys.serverStaticPublic.length)];
    if (theirServerPublicStatic.length != keys.serverStaticPublic.length) {
        OWSFailDebug(@"could not extract server public static.");
        return NO;
    }
    if (![keys.serverStaticPublic ows_constantTimeIsEqualToData:theirServerPublicStatic]) {
        OWSFailDebug(@"server public statics do not match.");
        return NO;
    }
    // It's easier to compare as hex data than parsing hexadecimal.
    NSData *_Nullable ourMrEnclaveHexData = [mrenclave dataUsingEncoding:NSUTF8StringEncoding];
    NSData *_Nullable theirMrEnclaveHexData =
        [quote.mrenclave.hexadecimalString dataUsingEncoding:NSUTF8StringEncoding];
    if (!ourMrEnclaveHexData || !theirMrEnclaveHexData
        || ![ourMrEnclaveHexData ows_constantTimeIsEqualToData:theirMrEnclaveHexData]) {
        OWSFailDebug(@"mrenclave does not match.");
        return NO;
    }
    if (quote.isDebugQuote) {
        OWSFailDebug(@"quote has invalid isDebugQuote value.");
        return NO;
    }
    return YES;
}

+ (nullable NSData *)decryptRequestId:(NSData *)encryptedRequestId
                   encryptedRequestIv:(NSData *)encryptedRequestIv
                  encryptedRequestTag:(NSData *)encryptedRequestTag
                                 keys:(RemoteAttestationKeys *)keys
{
    OWSAssertDebug(encryptedRequestId.length > 0);
    OWSAssertDebug(encryptedRequestIv.length > 0);
    OWSAssertDebug(encryptedRequestTag.length > 0);
    OWSAssertDebug(keys);

    OWSAES256Key *_Nullable key = keys.serverKey;
    if (!key) {
        OWSFailDebug(@"invalid server key.");
        return nil;
    }
    NSData *_Nullable decryptedData = [Cryptography decryptAESGCMWithInitializationVector:encryptedRequestIv
                                                                               ciphertext:encryptedRequestId
                                                              additionalAuthenticatedData:nil
                                                                                  authTag:encryptedRequestTag
                                                                                      key:key];
    if (!decryptedData) {
        OWSFailDebug(@"couldn't decrypt request id.");
        return nil;
    }
    return decryptedData;
}

@end

NS_ASSUME_NONNULL_END
