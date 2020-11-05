//
//  BobAxolotlParameters.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 26/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AxolotlParameters.h"

@interface BobAxolotlParameters : NSObject<AxolotlParameters>

@property (nonatomic, readonly)ECKeyPair *ourSignedPrekey;
@property (nonatomic, readonly)ECKeyPair *ourRatchetKey;
@property (nonatomic, readonly)ECKeyPair *ourOneTimePrekey;

@property (nonatomic, readonly)NSData    *theirBaseKey;

- (instancetype)initWithMyIdentityKeyPair:(ECKeyPair*)ourIdentityKeyPair theirIdentityKey:(NSData*)theirIdentityKey ourSignedPrekey:(ECKeyPair*)ourSignedPrekey ourRatchetKey:(ECKeyPair*)ourRatchetKey ourOneTimePrekey:(ECKeyPair*)ourOneTimeKeyPair theirBaseKey:(NSData*)theirBaseKey;

@end
