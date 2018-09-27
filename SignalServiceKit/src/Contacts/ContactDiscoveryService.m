//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactDiscoveryService.h"
#import "CDSQuote.h"
#import "CDSSigningCertificate.h"
#import "Cryptography.h"
#import "NSData+OWS.h"
#import "NSDate+OWS.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import <Curve25519Kit/Curve25519.h>
#import <HKDFKit/HKDFKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RemoteAttestationAuth ()

@property (nonatomic) NSString *username;
@property (nonatomic) NSString *password;

@end

#pragma mark -

@implementation RemoteAttestationAuth

@end

#pragma mark -

@interface RemoteAttestationKeys ()

@property (nonatomic) ECKeyPair *keyPair;
@property (nonatomic) NSData *serverEphemeralPublic;
@property (nonatomic) NSData *serverStaticPublic;

@property (nonatomic) OWSAES256Key *clientKey;
@property (nonatomic) OWSAES256Key *serverKey;

@end

#pragma mark -

@implementation RemoteAttestationKeys

+ (nullable RemoteAttestationKeys *)keysForKeyPair:(ECKeyPair *)keyPair
                             serverEphemeralPublic:(NSData *)serverEphemeralPublic
                                serverStaticPublic:(NSData *)serverStaticPublic
{
    if (!keyPair) {
        OWSFailDebug(@"Missing keyPair");
        return nil;
    }
    if (serverEphemeralPublic.length < 1) {
        OWSFailDebug(@"Invalid serverEphemeralPublic");
        return nil;
    }
    if (serverStaticPublic.length < 1) {
        OWSFailDebug(@"Invalid serverStaticPublic");
        return nil;
    }
    RemoteAttestationKeys *keys = [RemoteAttestationKeys new];
    keys.keyPair = keyPair;
    keys.serverEphemeralPublic = serverEphemeralPublic;
    keys.serverStaticPublic = serverStaticPublic;
    if (![keys deriveKeys]) {
        return nil;
    }
    return keys;
}

// Returns YES on success.
- (BOOL)deriveKeys
{
    NSData *ephemeralToEphemeral;
    NSData *ephemeralToStatic;
    @try {
        ephemeralToEphemeral =
            [Curve25519 generateSharedSecretFromPublicKey:self.serverEphemeralPublic andKeyPair:self.keyPair];
        ephemeralToStatic =
            [Curve25519 generateSharedSecretFromPublicKey:self.serverStaticPublic andKeyPair:self.keyPair];
    } @catch (NSException *exception) {
        OWSFailDebug(@"could not generate shared secrets: %@", exception);
        return NO;
    }

    NSData *masterSecret = [ephemeralToEphemeral dataByAppendingData:ephemeralToStatic];
    NSData *publicKeys = [NSData join:@[
        self.keyPair.publicKey,
        self.serverEphemeralPublic,
        self.serverStaticPublic,
    ]];

    NSData *_Nullable derivedMaterial;
    @try {
        derivedMaterial =
            [HKDFKit deriveKey:masterSecret info:nil salt:publicKeys outputSize:(int)kAES256_KeyByteLength * 2];
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

@interface RemoteAttestation ()

@property (nonatomic) RemoteAttestationKeys *keys;
@property (nonatomic) NSArray<NSHTTPCookie *> *cookies;
@property (nonatomic) NSData *requestId;
@property (nonatomic) NSString *enclaveId;
@property (nonatomic) RemoteAttestationAuth *auth;

@end

#pragma mark -

@implementation RemoteAttestation

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

@interface NSDictionary (CDS)

@end

#pragma mark -

@implementation NSDictionary (CDS)

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

@implementation ContactDiscoveryService

+ (instancetype)shared
{
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ContactDiscoveryService alloc] initDefault];
    });
    return sharedInstance;
}


- (instancetype)initDefault
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

- (void)testService
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self
            performRemoteAttestationWithSuccess:^(RemoteAttestation *remoteAttestation) {
                OWSLogDebug(@"succeeded");
            }
            failure:^(NSError *error) {
                OWSLogDebug(@"failed with error: %@", error);
            }];
    });
}

- (void)performRemoteAttestationWithSuccess:(void (^)(RemoteAttestation *remoteAttestation))successHandler
                                    failure:(void (^)(NSError *error))failureHandler
{
    [self
        getRemoteAttestationAuthWithSuccess:^(RemoteAttestationAuth *auth) {
            [self performRemoteAttestationWithAuth:auth success:successHandler failure:failureHandler];
        }
                                    failure:failureHandler];
}

- (void)getRemoteAttestationAuthWithSuccess:(void (^)(RemoteAttestationAuth *))successHandler
                                    failure:(void (^)(NSError *error))failureHandler
{
    TSRequest *request = [OWSRequestFactory remoteAttestationAuthRequest];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseDict) {
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

- (nullable RemoteAttestationAuth *)parseAuthParams:(id)response
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

- (void)performRemoteAttestationWithAuth:(RemoteAttestationAuth *)auth
                                 success:(void (^)(RemoteAttestation *remoteAttestation))successHandler
                                 failure:(void (^)(NSError *error))failureHandler
{
    ECKeyPair *keyPair = [Curve25519 generateKeyPair];

    NSString *enclaveId = @"cd6cfc342937b23b1bdd3bbf9721aa5615ac9ff50a75c5527d441cd3276826c9";

    TSRequest *request = [OWSRequestFactory remoteAttestationRequest:keyPair
                                                           enclaveId:enclaveId
                                                        authUsername:auth.username
                                                        authPassword:auth.password];

    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseJson) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                RemoteAttestation *_Nullable attestation = [self parseAttestationResponseJson:responseJson
                                                                                     response:task.response
                                                                                      keyPair:keyPair
                                                                                    enclaveId:enclaveId
                                                                                         auth:auth];

                if (!attestation) {
                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                    failureHandler(error);
                    return;
                }

                successHandler(attestation);
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            OWSLogVerbose(@"remote attestation failure: %lu", (unsigned long)response.statusCode);
            failureHandler(error);
        }];
}

- (nullable RemoteAttestation *)parseAttestationResponseJson:(id)responseJson
                                                    response:(NSURLResponse *)response
                                                     keyPair:(ECKeyPair *)keyPair
                                                   enclaveId:(NSString *)enclaveId
                                                        auth:(RemoteAttestationAuth *)auth
{
    OWSAssertDebug(responseJson);
    OWSAssertDebug(response);
    OWSAssertDebug(keyPair);
    OWSAssertDebug(enclaveId.length > 0);

    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        OWSFailDebug(@"unexpected response type.");
        return nil;
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSArray<NSHTTPCookie *> *cookies =
        [NSHTTPCookie cookiesWithResponseHeaderFields:httpResponse.allHeaderFields forURL:[NSURL new]];
    if (cookies.count < 1) {
        OWSFailDebug(@"couldn't parse cookie.");
        return nil;
    }

    if (![responseJson isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *responseDict = responseJson;
    NSData *_Nullable serverEphemeralPublic =
        [responseDict base64DataForKey:@"serverEphemeralPublic" expectedLength:32];
    if (!serverEphemeralPublic) {
        OWSFailDebug(@"couldn't parse serverEphemeralPublic.");
        return nil;
    }
    NSData *_Nullable serverStaticPublic = [responseDict base64DataForKey:@"serverStaticPublic" expectedLength:32];
    if (!serverStaticPublic) {
        OWSFailDebug(@"couldn't parse serverStaticPublic.");
        return nil;
    }
    NSData *_Nullable encryptedRequestId = [responseDict base64DataForKey:@"ciphertext"];
    if (!encryptedRequestId) {
        OWSFailDebug(@"couldn't parse encryptedRequestId.");
        return nil;
    }
    NSData *_Nullable encryptedRequestIv = [responseDict base64DataForKey:@"iv" expectedLength:12];
    if (!encryptedRequestIv) {
        OWSFailDebug(@"couldn't parse encryptedRequestIv.");
        return nil;
    }
    NSData *_Nullable encryptedRequestTag = [responseDict base64DataForKey:@"tag" expectedLength:16];
    if (!encryptedRequestTag) {
        OWSFailDebug(@"couldn't parse encryptedRequestTag.");
        return nil;
    }
    NSData *_Nullable quoteData = [responseDict base64DataForKey:@"quote"];
    if (!quoteData) {
        OWSFailDebug(@"couldn't parse quote data.");
        return nil;
    }
    NSString *_Nullable signatureBody = [responseDict stringForKey:@"signatureBody"];
    if (![signatureBody isKindOfClass:[NSString class]]) {
        OWSFailDebug(@"couldn't parse signatureBody.");
        return nil;
    }
    NSData *_Nullable signature = [responseDict base64DataForKey:@"signature"];
    if (!signature) {
        OWSFailDebug(@"couldn't parse signature.");
        return nil;
    }
    NSString *_Nullable encodedCertificates = [responseDict stringForKey:@"certificates"];
    if (![encodedCertificates isKindOfClass:[NSString class]]) {
        OWSFailDebug(@"couldn't parse encodedCertificates.");
        return nil;
    }
    NSString *_Nullable certificates = [encodedCertificates stringByRemovingPercentEncoding];
    if (!certificates) {
        OWSFailDebug(@"couldn't parse certificates.");
        return nil;
    }

    RemoteAttestationKeys *_Nullable keys = [RemoteAttestationKeys keysForKeyPair:keyPair
                                                            serverEphemeralPublic:serverEphemeralPublic
                                                               serverStaticPublic:serverStaticPublic];
    if (!keys) {
        OWSFailDebug(@"couldn't derive keys.");
        return nil;
    }

    CDSQuote *_Nullable quote = [CDSQuote parseQuoteFromData:quoteData];
    if (!quote) {
        OWSFailDebug(@"couldn't parse quote.");
        return nil;
    }
    NSData *_Nullable requestId = [self decryptRequestId:encryptedRequestId
                                      encryptedRequestIv:encryptedRequestIv
                                     encryptedRequestTag:encryptedRequestTag
                                                    keys:keys];
    if (!requestId) {
        OWSFailDebug(@"couldn't decrypt request id.");
        return nil;
    }

    if (![self verifyServerQuote:quote keys:keys enclaveId:enclaveId]) {
        OWSFailDebug(@"couldn't verify quote.");
        return nil;
    }

    if (![self verifyIasSignatureWithCertificates:certificates
                                    signatureBody:signatureBody
                                        signature:signature
                                        quoteData:quoteData]) {
        OWSFailDebug(@"couldn't verify ias signature.");
        return nil;
    }

    RemoteAttestation *result = [RemoteAttestation new];
    result.cookies = cookies;
    result.keys = keys;
    result.requestId = requestId;
    result.enclaveId = enclaveId;
    result.auth = auth;

    OWSLogVerbose(@"remote attestation complete.");

    return result;
}

- (BOOL)verifyIasSignatureWithCertificates:(NSString *)certificates
                             signatureBody:(NSString *)signatureBody
                                 signature:(NSData *)signature
                                 quoteData:(NSData *)quoteData
{
    OWSAssertDebug(certificates.length > 0);
    OWSAssertDebug(signatureBody.length > 0);
    OWSAssertDebug(signature.length > 0);
    OWSAssertDebug(quoteData);

    CDSSigningCertificate *_Nullable certificate = [CDSSigningCertificate parseCertificateFromPem:certificates];
    if (!certificate) {
        OWSFailDebug(@"could not parse signing certificate.");
        return NO;
    }
    if (![certificate verifySignatureOfBody:signatureBody signature:signature]) {
        OWSFailDebug(@"could not verify signature.");
        return NO;
    }

    SignatureBodyEntity *_Nullable signatureBodyEntity = [self parseSignatureBodyEntity:signatureBody];
    if (!signatureBodyEntity) {
        OWSFailDebug(@"could not parse signature body.");
        return NO;
    }

    // Compare the first N bytes of the quote data with the signed quote body.
    const NSUInteger kQuoteBodyComparisonLength = 432;
    if (signatureBodyEntity.isvEnclaveQuoteBody.length < kQuoteBodyComparisonLength) {
        OWSFailDebug(@"isvEnclaveQuoteBody has unexpected length.");
        return NO;
    }
    // NOTE: This version is separate from and does _NOT_ match the CDS quote version.
    const NSUInteger kSignatureBodyVersion = 3;
    if (![signatureBodyEntity.version isEqual:@(kSignatureBodyVersion)]) {
        OWSFailDebug(@"signatureBodyEntity has unexpected version.");
        return NO;
    }
    if (quoteData.length < kQuoteBodyComparisonLength) {
        OWSFailDebug(@"quoteData has unexpected length.");
        return NO;
    }
    NSData *isvEnclaveQuoteBodyForComparison =
        [signatureBodyEntity.isvEnclaveQuoteBody subdataWithRange:NSMakeRange(0, kQuoteBodyComparisonLength)];
    NSData *quoteDataForComparison = [quoteData subdataWithRange:NSMakeRange(0, kQuoteBodyComparisonLength)];
    if (![isvEnclaveQuoteBodyForComparison ows_constantTimeIsEqualToData:quoteDataForComparison]) {
        OWSFailDebug(@"isvEnclaveQuoteBody and quoteData do not match.");
        return NO;
    }

    if (![@"OK" isEqualToString:signatureBodyEntity.isvEnclaveQuoteStatus]) {
        OWSFailDebug(@"invalid isvEnclaveQuoteStatus: %@.", signatureBodyEntity.isvEnclaveQuoteStatus);
        return NO;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setDateFormat:@"yyy-MM-dd'T'HH:mm:ss.SSSSSS"];
    NSDate *timestampDate = [dateFormatter dateFromString:signatureBodyEntity.timestamp];
    if (!timestampDate) {
        OWSFailDebug(@"could not parse signature body timestamp.");
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
        OWSFailDebug(@"Signature is expired.");
        return NO;
    }

    return YES;
}

- (nullable SignatureBodyEntity *)parseSignatureBodyEntity:(NSString *)signatureBody
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

- (BOOL)verifyServerQuote:(CDSQuote *)quote keys:(RemoteAttestationKeys *)keys enclaveId:(NSString *)enclaveId
{
    OWSAssertDebug(quote);
    OWSAssertDebug(keys);
    OWSAssertDebug(enclaveId.length > 0);

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
    NSData *_Nullable ourEnclaveIdHexData = [enclaveId dataUsingEncoding:NSUTF8StringEncoding];
    NSData *_Nullable theirEnclaveIdHexData =
        [quote.mrenclave.hexadecimalString dataUsingEncoding:NSUTF8StringEncoding];
    if (!ourEnclaveIdHexData || !theirEnclaveIdHexData
        || ![ourEnclaveIdHexData ows_constantTimeIsEqualToData:theirEnclaveIdHexData]) {
        OWSFailDebug(@"enclave ids do not match.");
        return NO;
    }
    if (quote.isDebugQuote) {
        OWSFailDebug(@"quote has invalid isDebugQuote value.");
        return NO;
    }
    return YES;
}

- (nullable NSData *)decryptRequestId:(NSData *)encryptedRequestId
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
