//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "SessionRecord.h"
#import "SessionState.h"

#define ARCHIVED_STATES_MAX_LENGTH 40

@interface SessionRecord()

@property (nonatomic, retain) SessionState* sessionState;
@property (nonatomic, retain) NSMutableArray* previousStates;
@property (nonatomic) BOOL fresh;

@end

#define currentSessionStateKey   @"currentSessionStateKey"
#define previousSessionsStateKey @"previousSessionStateKeys"

@implementation SessionRecord

- (instancetype)init{
    self = [super init];
    
    if (self) {
        _fresh = YES;
        _sessionState = [SessionState new];
        _previousStates = [NSMutableArray new];
    }
    
    return self;
}

#pragma mark Serialization

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
    self.sessionState   = [aDecoder decodeObjectOfClass:[SessionState class]   forKey:currentSessionStateKey];
    
    return self;
}

- (BOOL)hasSessionState:(int)version baseKey:(NSData *)aliceBaseKey{
    if (self.sessionState.version == version && [aliceBaseKey isEqualToData:self.sessionState.aliceBaseKey]) {
        return YES;
    }
    
    for (SessionState *state in self.previousStates) {
        if (state.version == version && [aliceBaseKey isEqualToData:self.sessionState.aliceBaseKey]) {
            return YES;
        }
    }
    
    return NO;
}

- (SessionState*)sessionState{
    return _sessionState;
}

- (NSArray<SessionState *> *)previousSessionStates
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
    [self promoteState:[SessionState new]];
}

- (void)promoteState:(SessionState *)promotedState{
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

- (void)setState:(SessionState *)sessionState{
    self.sessionState = sessionState;
}

@end
