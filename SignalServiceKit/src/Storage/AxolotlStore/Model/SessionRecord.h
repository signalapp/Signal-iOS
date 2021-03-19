//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SessionState;

@interface SessionRecord : NSObject <NSSecureCoding>

- (instancetype)init;

- (SessionState*)sessionState;
- (NSArray<SessionState *> *)previousSessionStates;

- (BOOL)isFresh;
- (void)markAsUnFresh;
- (void)archiveCurrentState;
- (void)setState:(SessionState*)sessionState;

@end
