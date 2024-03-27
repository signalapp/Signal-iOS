//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "LegacySessionRecord.h"
#import "LegacyChainKey.h"
#import "LegacyReceivingChain.h"
#import "LegacySendingChain.h"
#import "LegacySessionState.h"

#define ARCHIVED_STATES_MAX_LENGTH 40

@interface LegacySessionRecord()

@property (nonatomic, retain) LegacySessionState* sessionState;
@property (nonatomic, retain) NSMutableArray* previousStates;
@property (nonatomic) BOOL fresh;

@end

#define currentSessionStateKey   @"currentSessionStateKey"
#define previousSessionsStateKey @"previousSessionStateKeys"

@implementation LegacySessionRecord

- (instancetype)init{
    self = [super init];
    
    if (self) {
        _fresh = YES;
        _sessionState = [LegacySessionState new];
        _previousStates = [NSMutableArray new];
    }
    
    return self;
}

+ (void)initialize {
#define REGISTER(X) {\
    Class cls = [Legacy##X class];\
    [NSKeyedArchiver setClassName:@#X forClass:cls];\
    [NSKeyedUnarchiver setClass:cls forClassName:@#X];\
}
    REGISTER(ChainKey)
    REGISTER(MessageKeys)
    REGISTER(PendingPreKey)
    REGISTER(ReceivingChain)
    REGISTER(RootKey)
    REGISTER(SendingChain)
    REGISTER(SessionRecord)
    REGISTER(SessionState)
#undef REGISTER
}

#pragma mark Serialization

+ (void)setUpKeyedArchiverSubstitutions {
    // +initialize will have been called by this point, so we don't actually need any extra work.
}

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.previousStates forKey:previousSessionsStateKey];
    [aCoder encodeObject:self.sessionState   forKey:currentSessionStateKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [self init];
    
    self.fresh = false;
    
    self.previousStates = [aDecoder decodeObjectOfClass:[NSMutableArray class] forKey:previousSessionsStateKey];
    self.sessionState   = [aDecoder decodeObjectOfClass:[LegacySessionState class]   forKey:currentSessionStateKey];
    
    return self;
}

- (LegacySessionState*)sessionState{
    return _sessionState;
}

- (NSArray<LegacySessionState *> *)previousSessionStates
{
    return _previousStates;
}

- (BOOL)isFresh{
    return _fresh;
}

- (void)markAsUnFresh
{
    self.fresh = false;
}

- (void)archiveCurrentState{
    if (self.sessionState.isFresh) {
        OWSLogInfo(@"Skipping archive, current session state is fresh.");
        return;
    }
    [self promoteState:[LegacySessionState new]];
}

- (void)promoteState:(LegacySessionState *)promotedState{
    [self.previousStates insertObject:self.sessionState atIndex:0];
    self.sessionState = promotedState;
    
    if (self.previousStates.count > ARCHIVED_STATES_MAX_LENGTH) {
        NSUInteger deleteCount;
        ows_sub_overflow(self.previousStates.count, ARCHIVED_STATES_MAX_LENGTH, &deleteCount);
        NSIndexSet *indexesToDelete =
            [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(ARCHIVED_STATES_MAX_LENGTH, deleteCount)];
        [self.previousStates removeObjectsAtIndexes:indexesToDelete];
    }
}

- (void)setState:(LegacySessionState *)sessionState{
    self.sessionState = sessionState;
}

@end
