//
//  AliceAxolotlParameters.m
//  AxolotlKit
//
//  Created by Frederic Jacobs on 26/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import "AliceAxolotlParameters.h"
#import <SignalCoreKit/OWSAsserts.h>

@implementation AliceAxolotlParameters

@synthesize ourIdentityKeyPair=_ourIdentityKeyPair, theirIdentityKey=_theirIdentityKey;

- (instancetype)initWithIdentityKey:(ECKeyPair*)myIdentityKey theirIdentityKey:(NSData*)theirIdentityKey ourBaseKey:(ECKeyPair*)ourBaseKey theirSignedPreKey:(NSData*)theirSignedPreKey theirOneTimePreKey:(NSData*)theirOneTimePreKey theirRatchetKey:(NSData*)theirRatchetKey{

    OWSAssert(myIdentityKey);
    OWSAssert(theirIdentityKey);
    OWSAssert(ourBaseKey);
    OWSAssert(theirSignedPreKey);
    OWSAssert(theirRatchetKey);

    self = [super init];
    
    if (self) {
        _ourIdentityKeyPair     = myIdentityKey;
        _theirIdentityKey       = theirIdentityKey;
        _ourBaseKey             = ourBaseKey;
        _theirSignedPreKey      = theirSignedPreKey;
        _theirOneTimePrekey     = theirOneTimePreKey;
        _theirRatchetKey        = theirRatchetKey;
    }
    
    return self;
}


@end
