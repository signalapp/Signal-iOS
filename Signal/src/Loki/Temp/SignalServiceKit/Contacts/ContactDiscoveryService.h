//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSErrorUserInfoKey const ContactDiscoveryServiceErrorKey_Reason;
extern NSErrorDomain const ContactDiscoveryServiceErrorDomain;
typedef NS_ERROR_ENUM(ContactDiscoveryServiceErrorDomain, ContactDiscoveryServiceError){
    ContactDiscoveryServiceErrorAttestationFailed = 100, ContactDiscoveryServiceErrorAssertionError = 101
};

@class ECKeyPair;
@class OWSAES256Key;

@interface RemoteAttestationAuth : NSObject

@property (nonatomic, readonly) NSString *username;
@property (nonatomic, readonly) NSString *password;

@end

#pragma mark -

@interface RemoteAttestationKeys : NSObject

@property (nonatomic, readonly) ECKeyPair *keyPair;
@property (nonatomic, readonly) NSData *serverEphemeralPublic;
@property (nonatomic, readonly) NSData *serverStaticPublic;

@property (nonatomic, readonly) OWSAES256Key *clientKey;
@property (nonatomic, readonly) OWSAES256Key *serverKey;

@end

#pragma mark -

@interface RemoteAttestation : NSObject

@property (nonatomic, readonly) RemoteAttestationKeys *keys;
@property (nonatomic, readonly) NSArray<NSHTTPCookie *> *cookies;
@property (nonatomic, readonly) NSData *requestId;
@property (nonatomic, readonly) NSString *enclaveId;
@property (nonatomic, readonly) RemoteAttestationAuth *auth;

@end

#pragma mark -

@interface ContactDiscoveryService : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

+ (instancetype)shared;

- (void)testService;
- (void)performRemoteAttestationWithSuccess:(void (^)(RemoteAttestation *_Nonnull remoteAttestation))successHandler
                                    failure:(void (^)(NSError *_Nonnull error))failureHandler;
@end

NS_ASSUME_NONNULL_END
