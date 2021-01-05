//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, RemoteAttestationService) {
    RemoteAttestationServiceContactDiscovery = 1,
    RemoteAttestationServiceKeyBackup,
};

NSString *NSStringForRemoteAttestationService(RemoteAttestationService value);

extern NSErrorUserInfoKey const RemoteAttestationErrorKey_Reason;
extern NSErrorDomain const RemoteAttestationErrorDomain;
typedef NS_ERROR_ENUM(RemoteAttestationErrorDomain, RemoteAttestationError){
    RemoteAttestationFailed = 100,
    RemoteAttestationAssertionError = 101,
};

@class ECKeyPair;
@class OWSAES256Key;
@class RemoteAttestationQuote;

@interface RemoteAttestationAuth : NSObject

@property (nonatomic, readonly) NSString *username;
@property (nonatomic, readonly) NSString *password;

@end

#pragma mark -

@interface RemoteAttestationKeys : NSObject

@property (nonatomic, readonly) ECKeyPair *clientEphemeralKeyPair;
@property (nonatomic, readonly) NSData *serverEphemeralPublic;
@property (nonatomic, readonly) NSData *serverStaticPublic;

@property (nonatomic, readonly) OWSAES256Key *clientKey;
@property (nonatomic, readonly) OWSAES256Key *serverKey;

- (nullable RemoteAttestationKeys *)initWithClientEphemeralKeyPair:(ECKeyPair *)clientEphemeralKeyPair
                                             serverEphemeralPublic:(NSData *)serverEphemeralPublic
                                                serverStaticPublic:(NSData *)serverStaticPublic
                                                             error:(NSError **)error;
@end

#pragma mark -

@interface RemoteAttestation : NSObject

@property (nonatomic, readonly) RemoteAttestationKeys *keys;
@property (nonatomic, readonly) NSArray<NSHTTPCookie *> *cookies;
@property (nonatomic, readonly) NSData *requestId;
@property (nonatomic, readonly) NSString *enclaveName;
@property (nonatomic, readonly) RemoteAttestationAuth *auth;

- (instancetype)initWithCookies:(NSArray<NSHTTPCookie *> *)cookies
                           keys:(RemoteAttestationKeys *)keys
                      requestId:(NSData *)requestId
                    enclaveName:(NSString *)enclaveName
                           auth:(RemoteAttestationAuth *)auth;

+ (nullable RemoteAttestationAuth *)parseAuthParams:(id)response;

+ (void)getRemoteAttestationAuthForService:(RemoteAttestationService)service
                                   success:(void (^)(RemoteAttestationAuth *))successHandler
                                   failure:(void (^)(NSError *error))failureHandler;

+ (BOOL)verifyServerQuote:(RemoteAttestationQuote *)quote
                     keys:(RemoteAttestationKeys *)keys
                mrenclave:(NSString *)mrenclave;

+ (BOOL)verifyIasSignatureWithCertificates:(NSString *)certificates
                             signatureBody:(NSString *)signatureBody
                                 signature:(NSData *)signature
                                 quoteData:(NSData *)quoteData
                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
