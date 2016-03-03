#import "YapDatabaseCrossProcessNotificationConnection.h"
#import "YapDatabaseCrossProcessNotificationTransaction.h"
#import "YapDatabaseCrossProcessNotificationPrivate.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
 **/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

@interface YapDatabaseCrossProcessNotificationConnection ()

@property (nonatomic, strong) YapDatabaseCrossProcessNotification *parent;

@end


@implementation YapDatabaseCrossProcessNotificationConnection

- (id)initWithParent:(YapDatabaseCrossProcessNotification *)inParent
{
	if ((self = [super init]))
	{
		self.parent = inParent;
	}
	return self;
}

/**
 * Required override method from YapDatabaseExtensionConnection
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
    // Nothing to do for this particular extension.
    //
    // YapDatabaseExtension throws a "not implemented" exception
    // to ensure extensions have implementations of all required methods.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (YapDatabaseExtension *)extension
{
	return self.parent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transactions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YapDatabaseCrossProcessNotificationTransaction *transaction =
	    [[YapDatabaseCrossProcessNotificationTransaction alloc] initWithParentConnection:self
	                                                       databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Required override method from YapDatabaseExtensionConnection.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YapDatabaseCrossProcessNotificationTransaction *transaction =
	    [[YapDatabaseCrossProcessNotificationTransaction alloc] initWithParentConnection:self
	                                                       databaseTransaction:databaseTransaction];
	
	return transaction;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtension
**/
- (void)getInternalChangeset:(NSMutableDictionary __unused **)internalChangesetPtr
           externalChangeset:(NSMutableDictionary __unused **)externalChangesetPtr
              hasDiskChanges:(BOOL __unused *)hasDiskChangesPtr
{
	// Nothing to do for this particular extension.
	//
	// YapDatabaseExtension throws a "not implemented" exception
	// to ensure extensions have implementations of all required methods.
}

/**
 * Required override method from YapDatabaseExtension
**/
- (void)processChangeset:(NSDictionary __unused *)changeset
{
	// Nothing to do for this particular extension.
	//
	// YapDatabaseExtension throws a "not implemented" exception
	// to ensure extensions have implementations of all required methods.
}

@end
