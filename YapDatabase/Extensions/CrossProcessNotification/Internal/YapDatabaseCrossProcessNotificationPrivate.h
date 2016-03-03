#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseCrossProcessNotification.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCrossProcessNotification ()

- (void)notifyChanged;

@end

@interface YapDatabaseCrossProcessNotificationTransaction ()

- (id)initWithParentConnection:(YapDatabaseCrossProcessNotificationConnection *)inParentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction;

@end

@interface YapDatabaseCrossProcessNotificationConnection ()

- (id)initWithParent:(YapDatabaseCrossProcessNotification *)inParent;

@end
