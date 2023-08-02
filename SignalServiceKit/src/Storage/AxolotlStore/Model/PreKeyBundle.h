//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreKeyBundle : NSObject <NSSecureCoding>

@property (nonatomic, readonly) NSData   *identityKey;
@property (nonatomic, readonly) int      registrationId;
@property (nonatomic, readonly) int      deviceId;
@property (nonatomic, readonly) NSData   *signedPreKeyPublic;
@property (nonatomic, readonly) NSData   *preKeyPublic;
@property (nonatomic, readonly) int      preKeyId;
@property (nonatomic, readonly) int      signedPreKeyId;
@property (nonatomic, readonly) NSData   *signedPreKeySignature;
@property (nonatomic, readonly) int pqPreKeyId;
@property (nonatomic, readonly) NSData *pqPreKeyPublic;
@property (nonatomic, readonly) NSData *pqPreKeySignature;


- (nullable instancetype)initWithRegistrationId:(int)registrationId
                                       deviceId:(int)deviceId
                                       preKeyId:(int)preKeyId
                                   preKeyPublic:(NSData *)preKeyPublic
                             signedPreKeyPublic:(NSData *)signedPreKeyPublic
                                 signedPreKeyId:(int)signedPreKeyId
                          signedPreKeySignature:(NSData *)signedPreKeySignature
                                     pqPreKeyId:(int)pqPreKeyId
                                 pqPreKeyPublic:(NSData *)pqPreKeyPublic
                              pqPreKeySignature:(NSData *)pqPreKeySignature
                                    identityKey:(NSData *)identityKey;

@end

NS_ASSUME_NONNULL_END
