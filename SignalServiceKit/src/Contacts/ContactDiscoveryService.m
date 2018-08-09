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

@interface RemoteAttestationAuth : NSObject

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
    NSData *ephemeralToEphemeral =
        [Curve25519 generateSharedSecretFromPublicKey:self.serverEphemeralPublic andKeyPair:self.keyPair];
    NSData *ephemeralToStatic =
        [Curve25519 generateSharedSecretFromPublicKey:self.serverStaticPublic andKeyPair:self.keyPair];

    NSData *masterSecret = [ephemeralToEphemeral dataByAppendingData:ephemeralToStatic];
    NSData *publicKeys = [[self.keyPair.publicKey dataByAppendingData:self.serverEphemeralPublic]
        dataByAppendingData:self.serverStaticPublic];

    NSData *_Nullable derivedMaterial;
    @try {
        derivedMaterial =
            [HKDFKit deriveKey:masterSecret info:nil salt:publicKeys outputSize:(int)kAES256_KeyByteLength * 2];
    } @catch (NSException *exception) {
        DDLogError(@"%@ could not derive service key: %@", self.logTag, exception);
        return NO;
    }

    if (!derivedMaterial) {
        OWSFail(@"%@ missing derived service key.", self.logTag);
        return NO;
    }
    if (derivedMaterial.length != kAES256_KeyByteLength * 2) {
        OWSFail(@"%@ derived service key has unexpected length.", self.logTag);
        return NO;
    }

    NSData *_Nullable clientKeyData =
        [derivedMaterial subdataWithRange:NSMakeRange(kAES256_KeyByteLength * 0, kAES256_KeyByteLength)];
    OWSAES256Key *_Nullable clientKey = [OWSAES256Key keyWithData:clientKeyData];
    if (!clientKey) {
        OWSFail(@"%@ clientKey has unexpected length.", self.logTag);
        return NO;
    }

    NSData *_Nullable serverKeyData =
        [derivedMaterial subdataWithRange:NSMakeRange(kAES256_KeyByteLength * 1, kAES256_KeyByteLength)];
    OWSAES256Key *_Nullable serverKey = [OWSAES256Key keyWithData:serverKeyData];
    if (!serverKey) {
        OWSFail(@"%@ serverKey has unexpected length.", self.logTag);
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

- (NSString *)authUsername
{
    return self.auth.username;
}

- (NSString *)password
{
    return self.auth.password;
}

@end

#pragma mark -

@interface SignatureBodyEntity : NSObject

@property (nonatomic) NSData *isvEnclaveQuoteBody;
@property (nonatomic) NSString *isvEnclaveQuoteStatus;
@property (nonatomic) NSString *timestamp;

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
        OWSFail(@"%@ couldn't parse string for key: %@", self.logTag, key);
        return nil;
    }
    return valueString;
}

- (nullable NSData *)base64DataForKey:(NSString *)key
{
    NSString *_Nullable valueString = self[key];
    if (![valueString isKindOfClass:[NSString class]]) {
        OWSFail(@"%@ couldn't parse base 64 value for key: %@", self.logTag, key);
        return nil;
    }
    NSData *_Nullable valueData = [[NSData alloc] initWithBase64EncodedString:valueString options:0];
    if (!valueData) {
        OWSFail(@"%@ couldn't decode base 64 value for key: %@", self.logTag, key);
        return nil;
    }
    return valueData;
}

- (nullable NSData *)base64DataForKey:(NSString *)key expectedLength:(NSUInteger)expectedLength
{
    NSData *_Nullable valueData = [self base64DataForKey:key];
    if (valueData && valueData.length != expectedLength) {
        DDLogDebug(@"%@ decoded base 64 value for key: %@, has unexpected length: %zd != %zd",
            self.logTag,
            key,
            valueData.length,
            expectedLength);
        OWSFail(@"%@ decoded base 64 value for key has unexpected length: %lu != %lu",
            self.logTag,
            (unsigned long)valueData.length,
            (unsigned long)expectedLength);
        return nil;
    }
    return valueData;
}

@end

#pragma mark -

@implementation ContactDiscoveryService

+ (instancetype)sharedService {
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
            performRemoteAttestationWithSuccess:^(RemoteAttestation *_Nonnull remoteAttestation) {
                DDLogDebug(@"%@ in %s succeeded", self.logTag, __PRETTY_FUNCTION__);
            }
            failure:^(NSError *_Nonnull error) {
                DDLogDebug(@"%@ in %s failed with error: %@", self.logTag, __PRETTY_FUNCTION__, error);
            }];
    });
}

- (void)performRemoteAttestationWithSuccess:(void (^)(RemoteAttestation *_Nonnull remoteAttestation))successHandler
                                    failure:(void (^)(NSError *_Nonnull error))failureHandler
{
    [self
        getRemoteAttestationAuthWithSuccess:^(RemoteAttestationAuth *_Nonnull auth) {
            [self performRemoteAttestationWithAuth:auth success:successHandler failure:failureHandler];
        }
                                    failure:failureHandler];
}

- (void)getRemoteAttestationAuthWithSuccess:(void (^)(RemoteAttestationAuth *))successHandler
                                    failure:(void (^)(NSError *_Nonnull error))failureHandler
{
    TSRequest *request = [OWSRequestFactory remoteAttestationAuthRequest];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseDict) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                RemoteAttestationAuth *_Nullable auth = [self parseAuthParams:responseDict];
                if (!auth) {
                    DDLogError(@"%@ remote attestation auth could not be parsed: %@", self.logTag, responseDict);
                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                    failureHandler(error);
                    return;
                }

                successHandler(auth);
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            DDLogVerbose(@"%@ remote attestation auth failure: %zd", self.logTag, response.statusCode);
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
        OWSFail(@"%@ missing or empty password.", self.logTag);
        return nil;
    }

    NSString *_Nullable username = [responseDict stringForKey:@"username"];
    if (username.length < 1) {
        OWSFail(@"%@ missing or empty username.", self.logTag);
        return nil;
    }

    RemoteAttestationAuth *result = [RemoteAttestationAuth new];
    result.username = username;
    result.password = password;
    return result;
}

- (void)performRemoteAttestationWithAuth:(RemoteAttestationAuth *)auth
                                 success:(void (^)(RemoteAttestation *_Nonnull remoteAttestation))successHandler
                                 failure:(void (^)(NSError *_Nonnull error))failureHandler
{
    ECKeyPair *keyPair = [Curve25519 generateKeyPair];

    // TODO:
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
            DDLogVerbose(@"%@ remote attestation failure: %zd", self.logTag, response.statusCode);
            failureHandler(error);
        }];
}

- (nullable RemoteAttestation *)parseAttestationResponseJson:(id)responseJson
                                                    response:(NSURLResponse *)response
                                                     keyPair:(ECKeyPair *)keyPair
                                                   enclaveId:(NSString *)enclaveId
                                                        auth:(RemoteAttestationAuth *)auth
{
    OWSAssert(responseJson);
    OWSAssert(response);
    OWSAssert(keyPair);
    OWSAssert(enclaveId.length > 0);

    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        OWSFail(@"%@ unexpected response type.", self.logTag);
        return nil;
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSArray<NSHTTPCookie *> *cookies =
        [NSHTTPCookie cookiesWithResponseHeaderFields:httpResponse.allHeaderFields forURL:[NSURL new]];
    if (cookies.count < 1) {
        OWSFail(@"%@ couldn't parse cookie.", self.logTag);
        return nil;
    }

    if (![responseJson isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *responseDict = responseJson;
    NSData *_Nullable serverEphemeralPublic =
        [responseDict base64DataForKey:@"serverEphemeralPublic" expectedLength:32];
    if (!serverEphemeralPublic) {
        OWSFail(@"%@ couldn't parse serverEphemeralPublic.", self.logTag);
        return nil;
    }
    NSData *_Nullable serverStaticPublic = [responseDict base64DataForKey:@"serverStaticPublic" expectedLength:32];
    if (!serverStaticPublic) {
        OWSFail(@"%@ couldn't parse serverStaticPublic.", self.logTag);
        return nil;
    }
    NSData *_Nullable encryptedRequestId = [responseDict base64DataForKey:@"ciphertext"];
    if (!encryptedRequestId) {
        OWSFail(@"%@ couldn't parse encryptedRequestId.", self.logTag);
        return nil;
    }
    NSData *_Nullable encryptedRequestIv = [responseDict base64DataForKey:@"iv" expectedLength:12];
    if (!encryptedRequestIv) {
        OWSFail(@"%@ couldn't parse encryptedRequestIv.", self.logTag);
        return nil;
    }
    NSData *_Nullable encryptedRequestTag = [responseDict base64DataForKey:@"tag" expectedLength:16];
    if (!encryptedRequestTag) {
        OWSFail(@"%@ couldn't parse encryptedRequestTag.", self.logTag);
        return nil;
    }
    NSData *_Nullable quoteData = [responseDict base64DataForKey:@"quote"];
    if (!quoteData) {
        OWSFail(@"%@ couldn't parse quote data.", self.logTag);
        return nil;
    }
    NSString *_Nullable signatureBody = [responseDict stringForKey:@"signatureBody"];
    if (![signatureBody isKindOfClass:[NSString class]]) {
        OWSFail(@"%@ couldn't parse signatureBody.", self.logTag);
        return nil;
    }
    NSData *_Nullable signature = [responseDict base64DataForKey:@"signature"];
    if (!signature) {
        OWSFail(@"%@ couldn't parse signature.", self.logTag);
        return nil;
    }
    NSString *_Nullable encodedCertificates = [responseDict stringForKey:@"certificates"];
    if (![encodedCertificates isKindOfClass:[NSString class]]) {
        OWSFail(@"%@ couldn't parse encodedCertificates.", self.logTag);
        return nil;
    }
    NSString *_Nullable certificates = [encodedCertificates stringByRemovingPercentEncoding];
    if (!certificates) {
        OWSFail(@"%@ couldn't parse certificates.", self.logTag);
        return nil;
    }

    RemoteAttestationKeys *_Nullable keys = [RemoteAttestationKeys keysForKeyPair:keyPair
                                                            serverEphemeralPublic:serverEphemeralPublic
                                                               serverStaticPublic:serverStaticPublic];
    if (!keys) {
        OWSFail(@"%@ couldn't derive keys.", self.logTag);
        return nil;
    }

    CDSQuote *_Nullable quote = [CDSQuote parseQuoteFromData:quoteData];
    if (!quote) {
        OWSFail(@"%@ couldn't parse quote.", self.logTag);
        return nil;
    }
    NSData *_Nullable requestId = [self decryptRequestId:encryptedRequestId
                                      encryptedRequestIv:encryptedRequestIv
                                     encryptedRequestTag:encryptedRequestTag
                                                    keys:keys];
    if (!requestId) {
        OWSFail(@"%@ couldn't decrypt request id.", self.logTag);
        return nil;
    }

    if (![self verifyServerQuote:quote keys:keys enclaveId:enclaveId]) {
        OWSFail(@"%@ couldn't verify quote.", self.logTag);
        return nil;
    }

    if (![self verifyIasSignatureWithCertificates:certificates
                                    signatureBody:signatureBody
                                        signature:signature
                                        quoteData:quoteData]) {
        OWSFail(@"%@ couldn't verify ias signature.", self.logTag);
        return nil;
    }

    RemoteAttestation *result = [RemoteAttestation new];
    result.cookies = cookies;
    result.keys = keys;
    result.requestId = requestId;
    result.enclaveId = enclaveId;
    result.auth = auth;

    DDLogVerbose(@"%@ remote attestation complete.", self.logTag);

    return result;
}

- (BOOL)verifyIasSignatureWithCertificates:(NSString *)certificates
                             signatureBody:(NSString *)signatureBody
                                 signature:(NSData *)signature
                                 quoteData:(NSData *)quoteData
{
    OWSAssert(certificates.length > 0);
    OWSAssert(signatureBody.length > 0);
    OWSAssert(signature.length > 0);
    OWSAssert(quoteData);

    CDSSigningCertificate *_Nullable certificate = [CDSSigningCertificate parseCertificateFromPem:certificates];
    if (!certificate) {
        OWSFail(@"%@ could not parse signing certificate.", self.logTag);
        return NO;
    }
    if (![certificate verifySignatureOfBody:signatureBody signature:signature]) {
        OWSFail(@"%@ could not verify signature.", self.logTag);
        return NO;
    }

    SignatureBodyEntity *_Nullable signatureBodyEntity = [self parseSignatureBodyEntity:signatureBody];
    if (!signatureBodyEntity) {
        OWSFail(@"%@ could not parse signature body.", self.logTag);
        return NO;
    }

    // Compare the first N bytes of the quote data with the signed quote body.
    const NSUInteger kQuoteBodyComparisonLength = 432;
    if (signatureBodyEntity.isvEnclaveQuoteBody.length < kQuoteBodyComparisonLength) {
        OWSFail(@"%@ isvEnclaveQuoteBody has unexpected length.", self.logTag);
        return NO;
    }
    if (quoteData.length < kQuoteBodyComparisonLength) {
        OWSFail(@"%@ quoteData has unexpected length.", self.logTag);
        return NO;
    }
    NSData *isvEnclaveQuoteBodyForComparison =
        [signatureBodyEntity.isvEnclaveQuoteBody subdataWithRange:NSMakeRange(0, kQuoteBodyComparisonLength)];
    NSData *quoteDataForComparison = [quoteData subdataWithRange:NSMakeRange(0, kQuoteBodyComparisonLength)];
    if (![isvEnclaveQuoteBodyForComparison ows_constantTimeIsEqualToData:quoteDataForComparison]) {
        OWSFail(@"%@ isvEnclaveQuoteBody and quoteData do not match.", self.logTag);
        return NO;
    }

    // TODO: Before going to production, remove GROUP_OUT_OF_DATE.
    if (![@"OK" isEqualToString:signatureBodyEntity.isvEnclaveQuoteStatus]
        && ![@"GROUP_OUT_OF_DATE" isEqualToString:signatureBodyEntity.isvEnclaveQuoteStatus]) {
        OWSFail(@"%@ invalid isvEnclaveQuoteStatus: %@.", self.logTag, signatureBodyEntity.isvEnclaveQuoteStatus);
        return NO;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setDateFormat:@"yyy-MM-dd'T'HH:mm:ss.SSSSSS"];
    NSDate *timestampDate = [dateFormatter dateFromString:signatureBodyEntity.timestamp];
    if (!timestampDate) {
        OWSFail(@"%@ could not parse signature body timestamp.", self.logTag);
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
        OWSFail(@"%@ Signature is expired.", self.logTag);
        return NO;
    }

    return YES;
}

- (nullable SignatureBodyEntity *)parseSignatureBodyEntity:(NSString *)signatureBody
{
    OWSAssert(signatureBody.length > 0);

    NSError *error = nil;
    NSDictionary *_Nullable jsonDict =
        [NSJSONSerialization JSONObjectWithData:[signatureBody dataUsingEncoding:NSUTF8StringEncoding]
                                        options:0
                                          error:&error];
    if (error || ![jsonDict isKindOfClass:[NSDictionary class]]) {
        OWSFail(@"%@ could not parse signature body JSON: %@.", self.logTag, error);
        return nil;
    }
    NSString *_Nullable timestamp = [jsonDict stringForKey:@"timestamp"];
    if (timestamp.length < 1) {
        OWSFail(@"%@ could not parse signature timestamp.", self.logTag);
        return nil;
    }
    NSData *_Nullable isvEnclaveQuoteBody = [jsonDict base64DataForKey:@"isvEnclaveQuoteBody"];
    if (isvEnclaveQuoteBody.length < 1) {
        OWSFail(@"%@ could not parse signature isvEnclaveQuoteBody.", self.logTag);
        return nil;
    }
    NSString *_Nullable isvEnclaveQuoteStatus = [jsonDict stringForKey:@"isvEnclaveQuoteStatus"];
    if (isvEnclaveQuoteStatus.length < 1) {
        OWSFail(@"%@ could not parse signature isvEnclaveQuoteStatus.", self.logTag);
        return nil;
    }

    SignatureBodyEntity *result = [SignatureBodyEntity new];
    result.isvEnclaveQuoteBody = isvEnclaveQuoteBody;
    result.isvEnclaveQuoteStatus = isvEnclaveQuoteStatus;
    result.timestamp = timestamp;
    return result;
}

- (BOOL)verifyServerQuote:(CDSQuote *)quote keys:(RemoteAttestationKeys *)keys enclaveId:(NSString *)enclaveId
{
    OWSAssert(quote);
    OWSAssert(keys);
    OWSAssert(enclaveId.length > 0);

    if (quote.reportData.length < keys.serverStaticPublic.length) {
        OWSFail(@"%@ reportData has unexpected length: %zd != %zd.",
            self.logTag,
            quote.reportData.length,
            keys.serverStaticPublic.length);
        return NO;
    }

    NSData *_Nullable theirServerPublicStatic =
        [quote.reportData subdataWithRange:NSMakeRange(0, keys.serverStaticPublic.length)];
    if (theirServerPublicStatic.length != keys.serverStaticPublic.length) {
        OWSFail(@"%@ could not extract server public static.", self.logTag);
        return NO;
    }
    if (![keys.serverStaticPublic ows_constantTimeIsEqualToData:theirServerPublicStatic]) {
        OWSFail(@"%@ server public statics do not match.", self.logTag);
        return NO;
    }
    // It's easier to compare as hex data than parsing hexadecimal.
    NSData *_Nullable ourEnclaveIdHexData = [enclaveId dataUsingEncoding:NSUTF8StringEncoding];
    NSData *_Nullable theirEnclaveIdHexData =
        [quote.mrenclave.hexadecimalString dataUsingEncoding:NSUTF8StringEncoding];
    if (!ourEnclaveIdHexData || !theirEnclaveIdHexData
        || ![ourEnclaveIdHexData ows_constantTimeIsEqualToData:theirEnclaveIdHexData]) {
        OWSFail(@"%@ enclave ids do not match.", self.logTag);
        return NO;
    }
    // TODO: Reverse this condition in production.
    if (!quote.isDebugQuote) {
        OWSFail(@"%@ quote has invalid isDebugQuote value.", self.logTag);
        return NO;
    }
    return YES;
}

- (nullable NSData *)decryptRequestId:(NSData *)encryptedRequestId
                   encryptedRequestIv:(NSData *)encryptedRequestIv
                  encryptedRequestTag:(NSData *)encryptedRequestTag
                                 keys:(RemoteAttestationKeys *)keys
{
    OWSAssert(encryptedRequestId.length > 0);
    OWSAssert(encryptedRequestIv.length > 0);
    OWSAssert(encryptedRequestTag.length > 0);
    OWSAssert(keys);

    OWSAES256Key *_Nullable key = keys.serverKey;
    if (!key) {
        OWSFail(@"%@ invalid server key.", self.logTag);
        return nil;
    }
    NSData *_Nullable decryptedData = [Cryptography decryptAESGCMWithInitializationVector:encryptedRequestIv
                                                                               ciphertext:encryptedRequestId
                                                              additionalAuthenticatedData:nil
                                                                                  authTag:encryptedRequestTag
                                                                                      key:key];
    if (!decryptedData) {
        OWSFail(@"%@ couldn't decrypt request id.", self.logTag);
        return nil;
    }
    return decryptedData;
}

@end

NS_ASSUME_NONNULL_END
