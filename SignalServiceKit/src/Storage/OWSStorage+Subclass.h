//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (Subclass)

- (void)loadDatabase;

- (void)runSyncRegistrations;
- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion;

- (BOOL)areAsyncRegistrationsComplete;
- (BOOL)areSyncRegistrationsComplete;

- (NSString *)databaseFilePath;
- (NSString *)databaseFilePath_SHM;
- (NSString *)databaseFilePath_WAL;

- (void)resetStorage;

@end

NS_ASSUME_NONNULL_END
