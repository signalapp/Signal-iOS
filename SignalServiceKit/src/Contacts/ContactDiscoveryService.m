//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactDiscoveryService.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import <Curve25519Kit/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

@interface RemoteAttestationKeys : NSObject

@property (nonatomic) ECKeyPair *keyPair;
@property (nonatomic) NSData *serverEphemeralPublic;
@property (nonatomic) NSData *serverStaticPublic;

@end

#pragma mark -

@implementation RemoteAttestationKeys

@end

#pragma mark -

@interface NSDictionary (OWS)

@end

#pragma mark -

@implementation NSDictionary (OWS)

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

            NSString *_Nullable authToken = [self parseAuthToken:responseDict];
            if (!authToken) {
                DDLogError(@"%@ remote attestation auth missing token: %@", self.logTag, responseDict);
                return;
            }
            [self performRemoteAttestationWithToken:authToken];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            DDLogVerbose(@"%@ remote attestation auth failure: %zd", self.logTag, response.statusCode);
        }];


    //    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //        [self performRemoteAttestation];
    //    });
}

- (nullable NSString *)parseAuthToken:(id)response
{
    if (![response isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *responseDict = response;
    NSString *_Nullable tokenString = responseDict[@"token"];
    if (![tokenString isKindOfClass:[NSString class]]) {
        return nil;
    }
    if (tokenString.length < 1) {
        return nil;
    }
    NSRange range = [tokenString rangeOfString:@":"];
    if (range.location == NSNotFound) {
        return nil;
    }
    DDLogVerbose(@"%@ attestation raw token: %@", self.logTag, tokenString);
    NSString *username = [tokenString substringToIndex:range.location];
    NSString *password = [tokenString substringFromIndex:range.location + range.length];
    if (username.length < 1 || password.length < 1) {
        return nil;
    }
    // To work around an idiosyncracy of the service implementation,
    // we need to repeat the username twice in the token.
    NSString *token = [username stringByAppendingFormat:@":%@", tokenString];
    DDLogVerbose(@"%@ attestation modified token: %@", self.logTag, token);
    return token;
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
            [self parseAttestationResponseJson:responseJson response:task.response keyPair:keyPair];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            DDLogVerbose(@"%@ remote attestation failure: %zd", self.logTag, response.statusCode);
        }];
}

- (nullable NSString *)parseAttestationResponseJson:(id)responseJson
                                           response:(NSURLResponse *)response
                                            keyPair:(ECKeyPair *)keyPair
{
    OWSAssert(responseJson);
    OWSAssert(response);
    OWSAssert(keyPair);

    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        OWSProdLogAndFail(@"%@ unexpected response type.", self.logTag);
        return nil;
    }
    NSDictionary *responseHeaders = ((NSHTTPURLResponse *)response).allHeaderFields;
    //    DDLogVerbose(@"%@ responseHeaders: %@", self.logTag, responseHeaders);
    //    for (NSString *key in responseHeaders) {
    //        id value = responseHeaders[key];
    //        DDLogVerbose(@"%@ \t %@: %@, %@", self.logTag, key, [value class], value);
    //    }

    NSString *_Nullable cookie = responseHeaders[@"Set-Cookie"];
    if (![cookie isKindOfClass:[NSString class]]) {
        OWSProdLogAndFail(@"%@ couldn't parse cookie.", self.logTag);
        return nil;
    }
    DDLogVerbose(@"%@ cookie: %@", self.logTag, cookie);
    NSRange cookieRange = [cookie rangeOfString:@";"];
    if (cookieRange.length != NSNotFound) {
        cookie = [cookie substringToIndex:cookieRange.location];
        DDLogVerbose(@"%@ trimmed cookie: %@", self.logTag, cookie);
    }
    //    Set-Cookie: __NSCFString, c2131364675-413235ic=c1656171-249545-958227; Path=/; Secure

    if (![responseJson isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *responseDict = responseJson;
    DDLogVerbose(@"%@ parseAttestationResponse: %@", self.logTag, responseDict);
    for (NSString *key in responseDict) {
        id value = responseDict[key];
        DDLogVerbose(@"%@ \t %@: %@, %@", self.logTag, key, [value class], value);
    }
    //    NSString *_Nullable serverEphemeralPublic = responseDict[@"serverEphemeralPublic"];
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
    NSData *_Nullable quote = [responseDict base64DataForKey:@"quote"];
    if (!quote) {
        OWSProdLogAndFail(@"%@ couldn't parse quote.", self.logTag);
        return nil;
    }
    id _Nullable signatureBody = responseDict[@"signatureBody"];
    if (!signatureBody) {
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

    RemoteAttestationKeys *keys = [RemoteAttestationKeys new];
    keys.keyPair = keyPair;
    keys.serverEphemeralPublic = serverEphemeralPublic;
    keys.serverStaticPublic = serverStaticPublic;

    //    RemoteAttestationKeys keys      = new RemoteAttestationKeys(keyPair, response.getServerEphemeralPublic(),
    //    response.getServerStaticPublic()); Quote                 quote     = new Quote(response.getQuote()); byte[]
    //    requestId = getPlaintext(keys.getServerKey(), response.getIv(), response.getCiphertext(), response.getTag());
    //
    //    verifyServerQuote(quote, response.getServerStaticPublic(), mrenclave);
    //    verifyIasSignature(keyStore, response.getCertificates(), response.getSignatureBody(), response.getSignature(),
    //    quote);
    //
    //    return new RemoteAttestation(requestId, keys, cookies);
    //} catch (BadPaddingException e) {
    //    throw new UnauthenticatedResponseException(e);
    //}
    return nil;
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
