//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import <AxolotlKit/SessionStore.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSStorageManager (SessionStore) <SessionStore>

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier;

#pragma mark - debug

- (void)resetSessionStore;
#if DEBUG
- (void)snapshotSessionStore;
- (void)restoreSessionStore;
#endif
- (void)printAllSessions;

@end

NS_ASSUME_NONNULL_END
