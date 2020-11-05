//
//  AxolotlKeyFetch.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 21/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PreKeyBundle : NSObject <NSSecureCoding>

@property (nonatomic, readonly) NSData   *identityKey;
@property (nonatomic, readonly) int      registrationId;
@property (nonatomic, readonly) int      deviceId;
@property (nonatomic, readonly) NSData   *signedPreKeyPublic;
@property (nonatomic, readonly) NSData   *preKeyPublic;
@property (nonatomic, readonly) int      preKeyId;
@property (nonatomic, readonly) int      signedPreKeyId;
@property (nonatomic, readonly) NSData   *signedPreKeySignature;

- (nullable instancetype)initWithRegistrationId:(int)registrationId
                                       deviceId:(int)deviceId
                                       preKeyId:(int)preKeyId
                                   preKeyPublic:(NSData *)preKeyPublic
                             signedPreKeyPublic:(NSData *)signedPreKeyPublic
                                 signedPreKeyId:(int)signedPreKeyId
                          signedPreKeySignature:(NSData *)signedPreKeySignature
                                    identityKey:(NSData *)identityKey;

@end
