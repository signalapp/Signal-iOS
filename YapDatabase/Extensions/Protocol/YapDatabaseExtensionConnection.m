#import "YapDatabaseExtensionConnection.h"
#import "YapDatabaseExtensionPrivate.h"


@implementation YapDatabaseExtensionConnection {

// You MUST store a strong reference to the parent.
// You MUST store an unretained reference to the corresponding database connection.
//
// The architecture of the database, throughout the database classes and extensions,
// is such that connections retain their parents, which are the base classes.
// This is needed so the base classes cannot disappear until their connections have all finished.
// Otherwise a connection might get orphaned, and a crash would ensue.
//
// Your custom extension implementation should be similar to the example below, but typed according to your needs.

/* Example from YapDatabaseViewConnection
 
@public
	__strong YapDatabaseView *view;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	 
*/
}

/**
 * Subclasses MUST implement this method.
 * It should create and return a proper instance of the YapDatabaseExtensionTransaction subclass.
 *
 * You may optionally use different subclasses for read-only vs read-write transactions.
 * Alternatively you can just store an ivar to determine the type of the transaction in order to protect as needed.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction __unused *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

/**
 * Subclasses MUST implement this method.
 * It should create and return a proper instance of the YapDatabaseExtensionTransaction subclass.
 *
 * You may optionally use different subclasses for read-only vs read-write transactions.
 * Alternatively you can just store an ivar to determine the type of the transaction in order to protect as needed.
**/
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction __unused *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

/**
 * Subclasses MUST implement this method.
 *
 * This method will be invoked in order to flush memory.
 * Subclasses are encouraged to do something similar to the following:
 *
 * if (flags & YapDatabaseConnectionFlushMemoryFlags_Caches)
 * {
 *     // Dump all caches
 * }
 *
 * if (flags & YapDatabaseConnectionFlushMemoryFlags_Statements)
 * {
 *     // Dump all pre-compiled statements
 *
 *     sqlite_finalize_null(&myStatement);
 * }
**/
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags __unused)flags
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses MUST implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * This method is invoked in order to get the internal and external changesets.
 * The internal changeset will be passed to sibling connections via processChangeset:.
 * The external changeset will be embedded within YapDatabaseModifiedNotification.
 *
 * This is one of the primary methods within the architecture to keep multiple connections up-to-date
 * as they move from one snapshot to the next. It is the responsibility of this method to provide
 * all the information necessary for other connections to properly update their state,
 * as well as provide the ability to extract information from YapDatabaseModifiedNotification's.
 *
 * The internal changeset will be passed directly to other connections.
 * It should contain any information necessary to ensure that other connections can update their state
 * to reflect the changes that were made during this transaction.
 *
 * The external changeset will be embedded within the YapDatabaseModifiedNotification.
 * Thus, it can be used to provide support for things such as querying to see if something changed,
 * or generating information necessary for UI update animations.
 *
 * If needed, "return" a internal changeset to be passed to other connections.
 * If not needed, you can "return" a nil internal changeset.
 *
 * If needed, "return" an external changeset to be embedded within YapDatabaseModifiedNotification.
 *
 * If any changes to the database file were made made during this transaction,
 * the hasDiskChangesPtr should be set to YES.
 *
 * For the most part, extensions update themselves in relation to changes within the main database table.
 * However, sometimes extensions may update the database file independently. For example, the FullTextSearch extension
 * has a method that optimizes the search tables by merging a bunch of different internal b-trees.
 * If an extension makes changes to the database file outside the context of the normal changes to the main database
 * table (such as the optimize command), then it MUST be sure to set the hasDiskChangesPtr to YES.
 * This is because the internal architecture has optimizations if no disk changes occurred.
**/
- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr
           externalChangeset:(NSMutableDictionary **)externalPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	*internalPtr = nil;
	*externalPtr = nil;
	*hasDiskChangesPtr = NO;
}

/**
 * Subclasses MUST implement this method.
 *
 * This method processes an internal changeset from another connection.
 * The internal changeset was generated from getInternalChangeset:externalChangeset:: on a sibling connection.
 *
 * This is one of the primary methods within the architecture to keep multiple connections up-to-date
 * as they move from one snapshot to the next. It is the responsibility of this method to process
 * the changeset to ensure the connection's state is properly updated.
**/
- (void)processChangeset:(NSDictionary __unused *)changeset
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * The default implementation likely does the right thing for most extensions.
 * That is, most extensions only need the information they store in the changeset.
 * However, the full changeset also contains information about what was changed in the main database table:
 * - YapDatabaseObjectChangesKey
 * - YapDatabaseMetadataChangesKey
 * - YapDatabaseRemovedKeysKey
 * - YapDatabaseRemovedCollectionsKey
 * - YapDatabaseAllKeysRemovedKey
 * 
 * So if the extension needs this information, it's better to re-use what's already available,
 * rather than have the extension duplicate the same information within its local changeset.
 * 
 * @param changeset
 *   The FULL changeset dictionary, including the core changeset info,
 *   as well as the changeset info for every registered extension.
 * 
 * @param registeredName
 *   The registeredName of the extension.
 *   This is the same as parent.registeredName, and is simply passed as a convenience.
**/
- (void)noteCommittedChangeset:(NSDictionary *)changeset registeredName:(NSString *)registeredName
{
	NSDictionary *ext_changeset = [[changeset objectForKey:YapDatabaseExtensionsKey] objectForKey:registeredName];
	if (ext_changeset)
	{
		[self processChangeset:ext_changeset];
	}
}

#pragma mark Generic Accessor

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
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

@end
