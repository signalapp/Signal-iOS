#import "YapDatabaseHooksConnection.h"
#import "YapDatabaseHooksPrivate.h"
#import "YapDatabaseLogging.h"

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
 **/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_OFF;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_OFF;
#endif
#pragma unused(ydbLogLevel)


@implementation YapDatabaseHooksConnection

@synthesize parent = parent;

- (id)initWithParent:(YapDatabaseHooks *)inParent databaseConnection:(YapDatabaseConnection *)inDbC
{
	if ((self = [super init]))
	{
		parent = inParent;
		databaseConnection = inDbC;
	}
	return self;
}

/**
 * Subclasses MUST implement this method.
 * Returns a reference to the parent (base class).
 *
 * This method is used by various general utility classes in order to
 * walk-the-chain: extension <-> extConnection <-> extTransaction.
 *
 * For example:
 * Given an extTransaction, the utility method can walk up to the base extension class, and fetch the registeredName.
**/
- (YapDatabaseExtension *)extension
{
	return parent;
}

/**
 * YapDatabaseExtensionConnection subclasses MUST implement this method.
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags
{
	// Nothing to do here
}

/**
 * YapDatabaseExtensionConnection subclasses MUST implement this method.
**/
- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr
           externalChangeset:(NSMutableDictionary **)externalPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	// Nothing to do here
	
	*internalPtr = nil;
	*externalPtr = nil;
	*hasDiskChangesPtr = NO;
}

/**
 * YapDatabaseExtensionConnection subclasses MUST implement this method.
**/
- (void)processChangeset:(NSDictionary *)changeset
{
	// Nothing to do here
}

/**
 * Subclasses MUST implement this method.
 * It should create and return a proper instance of the YapDatabaseExtensionTransaction subclass.
 *
 * You may optionally use different subclasses for read-only vs read-write transactions.
 * Alternatively you can just store an ivar to determine the type of the transaction in order to protect as needed.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseHooksTransaction *transaction =
	  [[YapDatabaseHooksTransaction alloc] initWithParentConnection:self
	                                            databaseTransaction:databaseTransaction];
	
	return transaction;
}

/**
 * Subclasses MUST implement this method.
 * It should create and return a proper instance of the YapDatabaseExtensionTransaction subclass.
 *
 * You may optionally use different subclasses for read-only vs read-write transactions.
 * Alternatively you can just store an ivar to determine the type of the transaction in order to protect as needed.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction
{
	YDBLogAutoTrace();
	
	YapDatabaseHooksTransaction *transaction =
	  [[YapDatabaseHooksTransaction alloc] initWithParentConnection:self
	                                            databaseTransaction:databaseTransaction];
	
	return transaction;
}

@end
