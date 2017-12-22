//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConnection.h"
#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (Subclass) <OWSDatabaseConnectionDelegate>

- (void)runSyncRegistrations;
- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion;

- (BOOL)areAsyncRegistrationsComplete;
- (BOOL)areSyncRegistrationsComplete;

- (NSString *)databaseFilePath;
- (NSString *)databaseFilePath_SHM;
- (NSString *)databaseFilePath_WAL;

- (void)openDatabase;
- (void)closeDatabase;

- (void)observeNotifications;

- (void)resetStorage;

@end

NS_ASSUME_NONNULL_END
