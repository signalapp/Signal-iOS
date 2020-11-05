//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SessionState.h"

@interface SessionRecord : NSObject <NSSecureCoding>

- (instancetype)init;

- (BOOL)hasSessionState:(int)version baseKey:(NSData*)aliceBaseKey;
- (SessionState*)sessionState;
- (NSMutableArray<SessionState *> *)previousSessionStates;

- (void)removePreviousSessionStates;
- (BOOL)isFresh;
- (void)markAsUnFresh;
- (void)archiveCurrentState;
- (void)promoteState:(SessionState*)promotedState;
- (void)setState:(SessionState*)sessionState;

@end
