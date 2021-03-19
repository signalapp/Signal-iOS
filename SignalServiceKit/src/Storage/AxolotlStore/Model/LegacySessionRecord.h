//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LegacySessionState;

@interface LegacySessionRecord : NSObject <NSSecureCoding>

+ (void)setUpKeyedArchiverSubstitutions;

- (instancetype)init;

- (LegacySessionState*)sessionState;
- (NSArray<LegacySessionState *> *)previousSessionStates;

- (BOOL)isFresh;
- (void)markAsUnFresh;
- (void)archiveCurrentState;
- (void)setState:(LegacySessionState*)sessionState;

@end
