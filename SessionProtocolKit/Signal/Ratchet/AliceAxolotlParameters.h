//
//  AliceAxolotlParameters.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 26/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AxolotlParameters.h"

@interface AliceAxolotlParameters : NSObject<AxolotlParameters>

@property (nonatomic, readonly)ECKeyPair *ourBaseKey;
@property (nonatomic, readonly)NSData* theirSignedPreKey;
@property (nonatomic, readonly)NSData* theirRatchetKey;
@property (nonatomic, readonly)NSData* theirOneTimePrekey;

- (instancetype)initWithIdentityKey:(ECKeyPair*)myIdentityKey theirIdentityKey:(NSData*)theirIdentityKey ourBaseKey:(ECKeyPair*)ourBaseKey theirSignedPreKey:(NSData*)theirSignedPreKey theirOneTimePreKey:(NSData*)theirOneTimePreKey theirRatchetKey:(NSData*)theirRatchetKey;

@end
