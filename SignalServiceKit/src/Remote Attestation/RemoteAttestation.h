//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, RemoteAttestationService) {
    RemoteAttestationServiceContactDiscovery = 1,
    RemoteAttestationServiceKeyBackup,
};

extern NSErrorUserInfoKey const RemoteAttestationErrorKey_Reason;
extern NSErrorDomain const RemoteAttestationErrorDomain;
typedef NS_ERROR_ENUM(RemoteAttestationErrorDomain, RemoteAttestationError){
    RemoteAttestationFailed = 100,
    RemoteAttestationAssertionError = 101,
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
@property (nonatomic, readonly) NSString *enclaveName;
@property (nonatomic, readonly) RemoteAttestationAuth *auth;

+ (nullable RemoteAttestationAuth *)parseAuthParams:(id)response;

+ (void)performRemoteAttestationForService:(RemoteAttestationService)service
                                   success:(void (^)(RemoteAttestation *_Nonnull remoteAttestation))successHandler
                                   failure:(void (^)(NSError *_Nonnull error))failureHandler;


+ (void)performRemoteAttestationForService:(RemoteAttestationService)service
                                      auth:(nullable RemoteAttestationAuth *)auth
                                   success:(void (^)(RemoteAttestation *_Nonnull remoteAttestation))successHandler
                                   failure:(void (^)(NSError *_Nonnull error))failureHandler;

@end

NS_ASSUME_NONNULL_END
