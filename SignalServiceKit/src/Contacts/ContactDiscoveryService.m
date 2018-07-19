//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactDiscoveryService.h"
#import "CDSQuote.h"
#import "CDSSigningCertificate.h"
#import "Cryptography.h"
#import "NSData+OWS.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import <Curve25519Kit/Curve25519.h>
#import <HKDFKit/HKDFKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RemoteAttestationKeys : NSObject

@property (nonatomic) ECKeyPair *keyPair;
@property (nonatomic) NSData *serverEphemeralPublic;
@property (nonatomic) NSData *serverStaticPublic;

@property (nonatomic) NSData *clientKey;
@property (nonatomic) NSData *serverKey;

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
        derivedMaterial = [HKDFKit deriveKey:masterSecret info:nil salt:publicKeys outputSize:ECCKeyLength * 2];
    } @catch (NSException *exception) {
        DDLogError(@"%@ could not derive service key: %@", self.logTag, exception);
        return NO;
    }

    if (!derivedMaterial) {
        OWSProdLogAndFail(@"%@ missing derived service key.", self.logTag);
        return NO;
    }
    if (derivedMaterial.length != ECCKeyLength * 2) {
        OWSProdLogAndFail(@"%@ derived service key has unexpected length.", self.logTag);
        return NO;
    }
    NSData *_Nullable clientKey = [derivedMaterial subdataWithRange:NSMakeRange(ECCKeyLength * 0, ECCKeyLength)];
    NSData *_Nullable serverKey = [derivedMaterial subdataWithRange:NSMakeRange(ECCKeyLength * 1, ECCKeyLength)];
    if (clientKey.length != ECCKeyLength) {
        OWSProdLogAndFail(@"%@ clientKey has unexpected length.", self.logTag);
        return NO;
    }
    if (serverKey.length != ECCKeyLength) {
        OWSProdLogAndFail(@"%@ serverKey has unexpected length.", self.logTag);
        return NO;
    }

    self.clientKey = clientKey;
    self.serverKey = serverKey;

    return YES;
}

@end

#pragma mark -

@interface RemoteAttestation : NSObject

@property (nonatomic) RemoteAttestationKeys *keys;
// TODO: Do we need to support multiple cookies?
@property (nonatomic) NSString *cookie;
@property (nonatomic) NSData *requestId;

@end

#pragma mark -

@implementation RemoteAttestation

@end

#pragma mark -

@interface NSDictionary (CDS)

@end

#pragma mark -

@implementation NSDictionary (CDS)

- (nullable NSData *)base64DataForKey:(NSString *)key
{
    NSString *_Nullable valueString = self[key];
    if (![valueString isKindOfClass:[NSString class]]) {
        OWSProdLogAndFail(@"%@ couldn't parse base 64 value for key: %@", self.logTag, key);
        return nil;
    }
    NSData *_Nullable valueData = [[NSData alloc] initWithBase64EncodedString:valueString options:0];
    if (!valueData) {
        OWSProdLogAndFail(@"%@ couldn't decode base 64 value for key: %@", self.logTag, key);
        return nil;
    }
    return valueData;
}

- (nullable NSData *)base64DataForKey:(NSString *)key expectedLength:(NSUInteger)expectedLength
{
    NSData *_Nullable valueData = [self base64DataForKey:key];
    if (valueData && valueData.length != expectedLength) {
        OWSProdLogAndFail(@"%@ decoded base 64 value for key: %@, has unexpected length: %zd != %zd",
            self.logTag,
            key,
            valueData.length,
            expectedLength);
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
        [self performRemoteAttestation];
    });
}

- (void)performRemoteAttestation
{
    [self performRemoteAttestationAuth];
}

// TODO: Add success and failure?
- (void)performRemoteAttestationAuth
{
    TSRequest *request = [OWSRequestFactory remoteAttestationAuthRequest];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseDict) {
            DDLogVerbose(@"%@ remote attestation auth success: %@", self.logTag, responseDict);

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *_Nullable authToken = [self parseAuthToken:responseDict];
                if (!authToken) {
                    DDLogError(@"%@ remote attestation auth missing token: %@", self.logTag, responseDict);
                    return;
                }
                [self performRemoteAttestationWithToken:authToken];
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            DDLogVerbose(@"%@ remote attestation auth failure: %zd", self.logTag, response.statusCode);
        }];
}

- (nullable NSString *)parseAuthToken:(id)response
{
    if (![response isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *responseDict = response;
    NSString *_Nullable token = responseDict[@"token"];
    if (![token isKindOfClass:[NSString class]]) {
        return nil;
    }
    if (token.length < 1) {
        return nil;
    }

    NSString *_Nullable username = responseDict[@"username"];
    if (![username isKindOfClass:[NSString class]]) {
        return nil;
    }
    if (username.length < 1) {
        return nil;
    }

    // To work around an idiosyncracy of the service implementation,
    // we need to repeat the username twice in the token.
    NSString *modifiedToken = [username stringByAppendingFormat:@":%@", token];
    DDLogVerbose(@"%@ attestation modified token: %@", self.logTag, modifiedToken);
    return modifiedToken;
}

- (void)performRemoteAttestationWithToken:(NSString *)authToken
{
    ECKeyPair *keyPair = [Curve25519 generateKeyPair];

    // TODO:
    NSString *enclaveId = @"cd6cfc342937b23b1bdd3bbf9721aa5615ac9ff50a75c5527d441cd3276826c9";

    TSRequest *request = [OWSRequestFactory remoteAttestationRequest:keyPair enclaveId:enclaveId authToken:authToken];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseJson) {
            DDLogVerbose(@"%@ remote attestation success: %@", self.logTag, responseJson);

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // TODO: Handle result.
                [self parseAttestationResponseJson:responseJson
                                          response:task.response
                                           keyPair:keyPair
                                         enclaveId:enclaveId];
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            DDLogVerbose(@"%@ remote attestation failure: %zd", self.logTag, response.statusCode);
        }];
}

- (nullable RemoteAttestation *)parseAttestationResponseJson:(id)responseJson
                                                    response:(NSURLResponse *)response
                                                     keyPair:(ECKeyPair *)keyPair
                                                   enclaveId:(NSString *)enclaveId
{
    OWSAssert(responseJson);
    OWSAssert(response);
    OWSAssert(keyPair);
    OWSAssert(enclaveId.length > 0);

    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        OWSProdLogAndFail(@"%@ unexpected response type.", self.logTag);
        return nil;
    }
    NSDictionary *responseHeaders = ((NSHTTPURLResponse *)response).allHeaderFields;

    NSString *_Nullable cookie = responseHeaders[@"Set-Cookie"];
    if (![cookie isKindOfClass:[NSString class]]) {
        OWSProdLogAndFail(@"%@ couldn't parse cookie.", self.logTag);
        return nil;
    }
    DDLogVerbose(@"%@ cookie: %@", self.logTag, cookie);

    // The cookie header will have this form:
    // Set-Cookie: __NSCFString, c2131364675-413235ic=c1656171-249545-958227; Path=/; Secure
    // We want to strip everything after the semicolon (;).
    NSRange cookieRange = [cookie rangeOfString:@";"];
    if (cookieRange.length != NSNotFound) {
        cookie = [cookie substringToIndex:cookieRange.location];
        DDLogVerbose(@"%@ trimmed cookie: %@", self.logTag, cookie);
    }

    if (![responseJson isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *responseDict = responseJson;
    DDLogVerbose(@"%@ parseAttestationResponse: %@", self.logTag, responseDict);
    for (NSString *key in responseDict) {
        id value = responseDict[key];
        DDLogVerbose(@"%@ \t %@: %@, %@", self.logTag, key, [value class], value);
    }
    NSData *_Nullable serverEphemeralPublic =
        [responseDict base64DataForKey:@"serverEphemeralPublic" expectedLength:32];
    if (!serverEphemeralPublic) {
        OWSProdLogAndFail(@"%@ couldn't parse serverEphemeralPublic.", self.logTag);
        return nil;
    }
    NSData *_Nullable serverStaticPublic = [responseDict base64DataForKey:@"serverStaticPublic" expectedLength:32];
    if (!serverStaticPublic) {
        OWSProdLogAndFail(@"%@ couldn't parse serverStaticPublic.", self.logTag);
        return nil;
    }
    NSData *_Nullable encryptedRequestId = [responseDict base64DataForKey:@"ciphertext"];
    if (!encryptedRequestId) {
        OWSProdLogAndFail(@"%@ couldn't parse encryptedRequestId.", self.logTag);
        return nil;
    }
    NSData *_Nullable encryptedRequestIv = [responseDict base64DataForKey:@"iv" expectedLength:12];
    if (!encryptedRequestIv) {
        OWSProdLogAndFail(@"%@ couldn't parse encryptedRequestIv.", self.logTag);
        return nil;
    }
    NSData *_Nullable encryptedRequestTag = [responseDict base64DataForKey:@"tag" expectedLength:16];
    if (!encryptedRequestTag) {
        OWSProdLogAndFail(@"%@ couldn't parse encryptedRequestTag.", self.logTag);
        return nil;
    }
    NSData *_Nullable quoteData = [responseDict base64DataForKey:@"quote"];
    if (!quoteData) {
        OWSProdLogAndFail(@"%@ couldn't parse quote data.", self.logTag);
        return nil;
    }
    NSString *_Nullable signatureBody = responseDict[@"signatureBody"];
    if (![signatureBody isKindOfClass:[NSString class]]) {
        OWSProdLogAndFail(@"%@ couldn't parse signatureBody.", self.logTag);
        return nil;
    }
    NSData *_Nullable signature = [responseDict base64DataForKey:@"signature"];
    if (!signature) {
        OWSProdLogAndFail(@"%@ couldn't parse signature.", self.logTag);
        return nil;
    }
    NSString *_Nullable encodedCertificates = responseDict[@"certificates"];
    if (![encodedCertificates isKindOfClass:[NSString class]]) {
        OWSProdLogAndFail(@"%@ couldn't parse encodedCertificates.", self.logTag);
        return nil;
    }
    NSString *_Nullable certificates = [encodedCertificates stringByRemovingPercentEncoding];
    if (!certificates) {
        OWSProdLogAndFail(@"%@ couldn't parse certificates.", self.logTag);
        return nil;
    }

    RemoteAttestationKeys *_Nullable keys = [RemoteAttestationKeys keysForKeyPair:keyPair
                                                            serverEphemeralPublic:serverEphemeralPublic
                                                               serverStaticPublic:serverStaticPublic];
    if (!keys) {
        OWSProdLogAndFail(@"%@ couldn't derive keys.", self.logTag);
        return nil;
    }

    CDSQuote *_Nullable quote = [CDSQuote parseQuoteFromData:quoteData];
    if (!quote) {
        OWSProdLogAndFail(@"%@ couldn't parse quote.", self.logTag);
        return nil;
    }
    NSData *_Nullable requestId = [self decryptRequestId:encryptedRequestId
                                      encryptedRequestIv:encryptedRequestIv
                                     encryptedRequestTag:encryptedRequestTag
                                                    keys:keys];
    if (!requestId) {
        OWSProdLogAndFail(@"%@ couldn't decrypt request id.", self.logTag);
        return nil;
    }

    if (![self verifyServerQuote:quote keys:keys enclaveId:enclaveId]) {
        OWSProdLogAndFail(@"%@ couldn't verify quote.", self.logTag);
        return nil;
    }

    if (![self verifyIasSignatureWithCertificates:certificates
                                    signatureBody:signatureBody
                                        signature:signature
                                            quote:quote]) {
        OWSProdLogAndFail(@"%@ couldn't verify ias signature.", self.logTag);
        return nil;
    }

    //+      RemoteAttestation remoteAttestation = new RemoteAttestation(requestId, keys);
    //+      List<String>      addressBook       = new LinkedList<>();
    //+
    //+      for (String e164number : e164numbers) {
    //+        addressBook.add(e164number.substring(1));
    //+      }
    //+
    //+      DiscoveryRequest  request  = cipher.createDiscoveryRequest(addressBook, remoteAttestation);
    //+      DiscoveryResponse response = this.pushServiceSocket.getContactDiscoveryRegisteredUsers(authorization,
    //request, attestationResponse.second(), mrenclave);
    //+      byte[]            data     = cipher.getDiscoveryResponseData(response, remoteAttestation);
    //+
    //+      Iterator<String> addressBookIterator = addressBook.iterator();
    //+      List<String>     results             = new LinkedList<>();
    //+
    //+      for (byte aData : data) {
    //+        String candidate = addressBookIterator.next();
    //+
    //+        if (aData != 0) results.add('+' + candidate);
    //+      }
    //+
    //+      return results;

    RemoteAttestation *result = [RemoteAttestation new];
    result.cookie = cookie;
    result.keys = keys;
    result.requestId = requestId;

    return result;
}

- (BOOL)verifyIasSignatureWithCertificates:(NSString *)certificates
                             signatureBody:(NSString *)signatureBody
                                 signature:(NSData *)signature
                                     quote:(CDSQuote *)quote
{
    OWSAssert(certificates.length > 0);
    OWSAssert(signatureBody.length > 0);
    OWSAssert(signature.length > 0);
    OWSAssert(quote);

    CDSSigningCertificate *_Nullable certificate = [CDSSigningCertificate parseCertificateFromPem:certificates];
    if (!certificate) {
        OWSProdLogAndFail(@"%@ could not parse signing certificate.", self.logTag);
        return NO;
    }
    if (![certificate verifySignatureOfBody:signatureBody signature:signature]) {
        OWSProdLogAndFail(@"%@ could not verify signature.", self.logTag);
        return NO;
    }
    ////public void verifyIasSignature(KeyStore trustStore, String certificates, String signatureBody, String signature,
    ///Quote quote) /throws SignatureException
    ////{
    ////    try {
    //        SigningCertificate signingCertificate = new SigningCertificate(certificates, trustStore);
    //        signingCertificate.verifySignature(signatureBody, signature);
    //
    //        SignatureBodyEntity signatureBodyEntity = JsonUtil.fromJson(signatureBody, SignatureBodyEntity.class);
    //
    //        if (!MessageDigest.isEqual(ByteUtil.trim(signatureBodyEntity.getIsvEnclaveQuoteBody(), 432),
    //        ByteUtil.trim(quote.getQuoteBytes(), 432))) {
    //            throw new SignatureException("Signed quote is not the same as RA quote: " +
    //            Hex.toStringCondensed(signatureBodyEntity.getIsvEnclaveQuoteBody()) + " vs " +
    //            Hex.toStringCondensed(quote.getQuoteBytes()));
    //        }
    //
    //        if (!"OK".equals(signatureBodyEntity.getIsvEnclaveQuoteStatus()) &&
    //        !"GROUP_OUT_OF_DATE".equals(signatureBodyEntity.getIsvEnclaveQuoteStatus())) {
    //            //      if (!"OK".equals(signatureBodyEntity.getIsvEnclaveQuoteStatus())) {
    //            throw new SignatureException("Quote status is: " + signatureBodyEntity.getIsvEnclaveQuoteStatus());
    //        }
    //
    //        if
    //        (Instant.from(ZonedDateTime.of(LocalDateTime.from(DateTimeFormatter.ofPattern("yyy-MM-dd'T'HH:mm:ss.SSSSSS").parse(signatureBodyEntity.getTimestamp())),
    //        ZoneId.of("UTC")))
    //            .plus(Period.ofDays(1))
    //            .isBefore(Instant.now()))
    //        {
    //            throw new SignatureException("Signature is expired");
    //        }
    //
    //    } catch (CertificateException | CertPathValidatorException | IOException e) {
    //        throw new SignatureException(e);
    //    }

    return YES;
}

- (BOOL)verifyServerQuote:(CDSQuote *)quote keys:(RemoteAttestationKeys *)keys enclaveId:(NSString *)enclaveId
{
    OWSAssert(quote);
    OWSAssert(keys);
    OWSAssert(enclaveId.length > 0);

    if (quote.reportData.length < keys.serverStaticPublic.length) {
        OWSProdLogAndFail(@"%@ reportData has unexpected length: %zd != %zd.",
            self.logTag,
            quote.reportData.length,
            keys.serverStaticPublic.length);
        return NO;
    }

    NSData *_Nullable theirServerPublicStatic =
        [quote.reportData subdataWithRange:NSMakeRange(0, keys.serverStaticPublic.length)];
    if (theirServerPublicStatic.length != keys.serverStaticPublic.length) {
        OWSProdLogAndFail(@"%@ could not extract server public static.", self.logTag);
        return NO;
    }
    if (![keys.serverStaticPublic ows_constantTimeIsEqualToData:theirServerPublicStatic]) {
        OWSProdLogAndFail(@"%@ server public statics do not match.", self.logTag);
        return NO;
    }
    // It's easier to compare as hex data than parsing hexadecimal.
    NSData *_Nullable ourEnclaveIdHexData = [enclaveId dataUsingEncoding:NSUTF8StringEncoding];
    NSData *_Nullable theirEnclaveIdHexData =
        [quote.mrenclave.hexadecimalString dataUsingEncoding:NSUTF8StringEncoding];
    if (!ourEnclaveIdHexData || !theirEnclaveIdHexData
        || ![ourEnclaveIdHexData ows_constantTimeIsEqualToData:theirEnclaveIdHexData]) {
        OWSProdLogAndFail(@"%@ enclave ids do not match.", self.logTag);
        return NO;
    }
    // TODO: Reverse this condition in production.
    if (!quote.isDebugQuote) {
        OWSProdLogAndFail(@"%@ quote has invalid isDebugQuote value.", self.logTag);
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

    OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:keys.serverKey];
    if (!key) {
        OWSProdLogAndFail(@"%@ invalid server key.", self.logTag);
        return nil;
    }
    NSData *_Nullable decryptedData = [Cryptography decryptAESGCMWithInitializationVector:encryptedRequestIv
                                                                               ciphertext:encryptedRequestId
                                                                                  authTag:encryptedRequestTag
                                                                                      key:key];
    if (!decryptedData) {
        OWSProdLogAndFail(@"%@ couldn't decrypt request id.", self.logTag);
        return nil;
    }
    return decryptedData;
}

// A successful (HTTP 200) response json object consists of:
// serverEphemeralPublic:    (32 bytes, base64) an ephemeral curve25519 public key generated by the server
// serverStaticPublic:    (32 bytes, base64) a static curve25519 public key generated by the server
// ciphertext:         (variable length, base64) a "request id" to be decrypted by the client (see below for derivation
// of server_key) (ciphertext, tag) = AES-256-GCM(key=server_key, plaintext=requestId, AAD=(), iv) iv:                (12
// bytes, base64) an IV for encrypted ciphertext tag:                (16 bytes, base64) a MAC for encrypted ciphertext
// quote:             (variable length, base64) a binary structure from an Intel CPU containing runtime information
// about a running enclave signatureBody:        (json object) a response from Intel Attestation Services attesting to
// the genuineness of the Quote signature:            (base64) a signature over signatureBody, with public key in
// corresponding signing certificate certificates:        (url-encoded PEM) signing certificate chain The response also
// contains HTTP session cookies which must be preserved for exactly one corresponding Contact Discovery request.
//
// After this PUT response is received, the client must:
// parse and verify fields in quote (see sample client code for parsing details):
// report_data:        (64 bytes) must equal (serverStaticPublic || 0 ...)
// mrenclave:            (32 bytes) must equal the request's enclaveId
// flags:            (8 bytes) debug flag must be unset, as well as being validated against expected values during
// parsing all other fields must be validated against a range of expected values during parsing (as shown in example
// parsing code), but are otherwise ignored See client/src/main/java/org/whispersystems/contactdiscovery/Quote.java parse
// and verify fields in signatureBody json object: isvEnclaveQuoteBody:    (base64) must equal quote
// isvEnclaveQuoteStatus:    (ascii) must equal "OK"
//"GROUP_OUT_OF_DATE" may be allowed for testing only
// timestamp:            (ascii) UTC timestamp formatted as "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" which must fall within the
// last 24h verify validity of signature over signatureBody using the public key contained in the leaf signing
// certificate in certificates verify signing certificates chain, with fixed trust anchors to be hard-coded in clients
// client/src/main/java/org/whispersystems/contactdiscovery/SigningCertificate.java contains X.509 PKI certificate chain
// validation code to follow
//
// After Curve25519-DH/HKDF key derivation upon the three public keys (client ephemeral private key, server ephemeral
// public key, and server static public key, described below), the client can now decrypt the ciphertext in the Remote
// Attestation Response containing a requestId to be sent along with a Contact Discovery request, and encrypt the body of
// a Contact Discovery request using client_key, bound for the enclave it performed attestation with.

@end

NS_ASSUME_NONNULL_END
