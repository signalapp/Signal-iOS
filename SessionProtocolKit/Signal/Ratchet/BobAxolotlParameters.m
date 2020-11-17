//
//  BobAxolotlParameters.m
//  AxolotlKit
//
//  Created by Frederic Jacobs on 26/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import "BobAxolotlParameters.h"
#import <SignalCoreKit/OWSAsserts.h>

@implementation BobAxolotlParameters

@synthesize theirIdentityKey=_theirIdentityKey, ourIdentityKeyPair=_ourIdentityKeyPair;

- (instancetype)initWithMyIdentityKeyPair:(ECKeyPair*)ourIdentityKeyPair theirIdentityKey:(NSData*)theirIdentityKey ourSignedPrekey:(ECKeyPair*)ourSignedPrekey ourRatchetKey:(ECKeyPair*)ourRatchetKey ourOneTimePrekey:(ECKeyPair*)ourOneTimeKeyPair theirBaseKey:(NSData*)theirBaseKey{

    OWSAssert(ourIdentityKeyPair);
    OWSAssert(theirIdentityKey);
    OWSAssert(ourSignedPrekey);
    OWSAssert(ourRatchetKey);
    OWSAssert(theirBaseKey);

    self = [super init];
    
    if (self) {
        _ourIdentityKeyPair     = ourIdentityKeyPair;
        _theirIdentityKey       = theirIdentityKey;
        _ourSignedPrekey        = ourSignedPrekey;
        _ourRatchetKey          = ourRatchetKey;
        _ourOneTimePrekey       = ourOneTimeKeyPair;
        _theirBaseKey           = theirBaseKey;
    }
    return self;
}

@end
