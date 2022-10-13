//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
