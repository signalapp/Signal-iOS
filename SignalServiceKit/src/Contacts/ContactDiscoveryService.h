//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

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

+ (instancetype)shared;

- (void)testService;
- (void)performRemoteAttestationWithSuccess:(void (^)(RemoteAttestation *_Nonnull remoteAttestation))successHandler
                                    failure:(void (^)(NSError *_Nonnull error))failureHandler;
@end

NS_ASSUME_NONNULL_END
