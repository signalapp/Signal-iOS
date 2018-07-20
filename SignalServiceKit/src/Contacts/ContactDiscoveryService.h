//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class RemoteAttestation;

@interface ContactDiscoveryService : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedService;

- (void)testService;
- (void)performRemoteAttestationWithSuccess:(void (^)(RemoteAttestation *_Nonnull remoteAttestation))successHandler
                                    failure:(void (^)(NSError *_Nonnull error))failureHandler;
@end

NS_ASSUME_NONNULL_END
