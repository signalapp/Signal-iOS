//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "LegacySessionState.h"
#import "LegacyReceivingChain.h"
#import "LegacySendingChain.h"
#import <Curve25519Kit/Curve25519.h>

@implementation LegacyPendingPreKey

static NSString* const kCoderPreKeyId       = @"kCoderPreKeyId";
static NSString* const kCoderSignedPreKeyId = @"kCoderSignedPreKeyId";
static NSString* const kCoderBaseKey        = @"kCoderBaseKey";


+ (BOOL)supportsSecureCoding{
    return YES;
}

-(instancetype)initWithBaseKey:(NSData*)baseKey preKeyId:(int)preKeyId signedPreKeyId:(int)signedPrekeyId{
    OWSAssert(baseKey);

    self = [super init];
    if (self) {
        _preKeyId       = preKeyId;
        _signedPreKeyId = signedPrekeyId;
        _baseKey        = baseKey;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [self initWithBaseKey:[aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderBaseKey]
                        preKeyId:[aDecoder decodeIntForKey:kCoderPreKeyId]
                  signedPreKeyId:[aDecoder decodeIntForKey:kCoderSignedPreKeyId]];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:_baseKey forKey:kCoderBaseKey];
    [aCoder encodeInt:_preKeyId forKey:kCoderPreKeyId];
    [aCoder encodeInt:_signedPreKeyId forKey:kCoderSignedPreKeyId];
}

@end

@interface LegacySessionState ()

@property LegacySendingChain       *sendingChain;               // The outgoing sending chain
@property LegacyPendingPreKey      *pendingPreKey;

@end

#pragma mark Keys for coder

static NSString* const kCoderVersion          = @"kCoderVersion";
static NSString* const kCoderAliceBaseKey     = @"kCoderAliceBaseKey";
static NSString* const kCoderRemoteIDKey      = @"kCoderRemoteIDKey";
static NSString* const kCoderLocalIDKey       = @"kCoderLocalIDKey";
static NSString* const kCoderPreviousCounter  = @"kCoderPreviousCounter";
static NSString* const kCoderRootKey          = @"kCoderRoot";
static NSString* const kCoderLocalRegID       = @"kCoderLocalRegID";
static NSString* const kCoderRemoteRegID      = @"kCoderRemoteRegID";
static NSString* const kCoderReceiverChains   = @"kCoderReceiverChains";
static NSString* const kCoderSendingChain     = @"kCoderSendingChain";
static NSString* const kCoderPendingPrekey    = @"kCoderPendingPrekey";

@implementation LegacySessionState

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (instancetype)init{
    self = [super init];
    
    if (self) {
        self.receivingChains = [NSArray array];
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [self init];
    
    if (self) {
        self.version              = [aDecoder decodeIntForKey:kCoderVersion];
        self.aliceBaseKey         = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderAliceBaseKey];
        self.remoteIdentityKey    = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderRemoteIDKey];
        self.localIdentityKey     = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderLocalIDKey];
        self.previousCounter      = [aDecoder decodeIntForKey:kCoderPreviousCounter];
        self.rootKey              = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderRootKey];
        self.remoteRegistrationId = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:kCoderRemoteRegID] intValue];
        self.localRegistrationId  = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:kCoderLocalRegID] intValue];
        self.sendingChain         = [aDecoder decodeObjectOfClass:[LegacySendingChain class] forKey:kCoderSendingChain];
        self.receivingChains      = [aDecoder decodeObjectOfClass:[NSArray class] forKey:kCoderReceiverChains];
        self.pendingPreKey        = [aDecoder decodeObjectOfClass:[LegacyPendingPreKey class] forKey:kCoderPendingPrekey];
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeInt:self.version forKey:kCoderVersion];
    [aCoder encodeObject:self.aliceBaseKey forKey:kCoderAliceBaseKey];
    [aCoder encodeObject:self.remoteIdentityKey forKey:kCoderRemoteIDKey];
    [aCoder encodeObject:self.localIdentityKey forKey:kCoderLocalIDKey];
    [aCoder encodeInt:self.previousCounter forKey:kCoderPreviousCounter];
    [aCoder encodeObject:self.rootKey forKey:kCoderRootKey];
    [aCoder encodeObject:[NSNumber numberWithInt:self.remoteRegistrationId] forKey:kCoderRemoteRegID];
    [aCoder encodeObject:[NSNumber numberWithInt:self.localRegistrationId] forKey:kCoderLocalRegID];
    [aCoder encodeObject:self.sendingChain forKey:kCoderSendingChain];
    [aCoder encodeObject:self.receivingChains forKey:kCoderReceiverChains];
    [aCoder encodeObject:self.pendingPreKey forKey:kCoderPendingPrekey];
}

- (BOOL)isFresh
{
    return self.remoteIdentityKey == nil && self.localIdentityKey == nil && self.sendingChain == nil && self.receivingChains.count == 0 && self.pendingPreKey == nil;
}

- (NSData*)senderRatchetKey{
    return [[self senderRatchetKeyPair] publicKey];
}

- (ECKeyPair*)senderRatchetKeyPair{
    return [[self sendingChain] senderRatchetKeyPair];
}

- (void)setSenderChain:(ECKeyPair*)senderRatchetKeyPair chainKey:(LegacyChainKey*)chainKey{
    OWSAssert(senderRatchetKeyPair);
    OWSAssert(chainKey);

    self.sendingChain = [[LegacySendingChain alloc]initWithChainKey:chainKey senderRatchetKeyPair:senderRatchetKeyPair];
}

- (LegacyChainKey*)senderChainKey{
    return self.sendingChain.chainKey;
}

- (void)setUnacknowledgedPreKeyMessage:(int)preKeyId signedPreKey:(int)signedPreKeyId baseKey:(NSData*)baseKey{
    OWSAssert(baseKey);

    LegacyPendingPreKey *pendingPreKey = [[LegacyPendingPreKey alloc] initWithBaseKey:baseKey preKeyId:preKeyId signedPreKeyId:signedPreKeyId];
    
    self.pendingPreKey = pendingPreKey;
}

- (BOOL)hasUnacknowledgedPreKeyMessage{
    return self.pendingPreKey?YES:NO;
}

- (LegacyPendingPreKey*)unacknowledgedPreKeyMessageItems{
    return self.pendingPreKey;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
