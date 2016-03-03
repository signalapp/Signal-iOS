#import "YapDatabaseHooks.h"
#import "YapDatabaseHooksPrivate.h"


@implementation YapDatabaseHooks

/**
 * Subclasses MUST implement this method.
 *
 * This method is used when unregistering an extension in order to drop the related tables.
 *
 * @param registeredName
 *   The name the extension was registered using.
 *   The extension should be able to generated the proper table name(s) using the given registered name.
 *
 * @param transaction
 *   A readWrite transaction for proper database access.
 *
 * @param wasPersistent
 *   If YES, then the extension should drop tables from sqlite.
 *   If NO, then the extension should unregister the proper YapMemoryTable(s).
**/
+ (void)dropTablesForRegisteredName:(NSString *)registeredName
					withTransaction:(YapDatabaseReadWriteTransaction *)transaction
					  wasPersistent:(BOOL)wasPersistent
{
	// Nothing to do here...
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		// Nothing to do here...
	}
	return self;
}

/**
 * Subclasses MUST implement this method IF they are non-persistent (in-memory only).
 * By doing so, they allow various optimizations, such as not persisting extension info in the yap2 table.
**/
- (BOOL)isPersistent
{
	return NO;
}

/**
 * Subclasses MUST implement this method.
 * Returns a proper instance of the YapDatabaseExtensionConnection subclass.
**/
- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseHooksConnection alloc] initWithParent:self databaseConnection:databaseConnection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize allowedCollections = allowedCollections;

@synthesize willModifyRow = willModifyRow;
@synthesize didModifyRow = didModifyRow;

@synthesize willRemoveRow = willRemoveRow;
@synthesize didRemoveRow = didRemoveRow;

@synthesize willRemoveAllRows = willRemoveAllRows;
@synthesize didRemoveAllRows = didRemoveAllRows;

@end
