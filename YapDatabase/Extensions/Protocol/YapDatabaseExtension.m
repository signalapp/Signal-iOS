#import "YapDatabaseExtension.h"
#import "YapDatabaseExtensionPrivate.h"


@implementation YapDatabaseExtension

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
+ (void)dropTablesForRegisteredName:(NSString __unused *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction __unused *)transaction
                      wasPersistent:(BOOL __unused)wasPersistent
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * If an extension class is renamed this method should be used to properly transition.
 * The extension architecture will verify that a re-registered extension is using the same
 * extension class that it was previously using. If the class names differ, then the extension architecture
 * will automatically try to unregister the previous extension using the previous extension class.
 *
 * That is, it will attempt to invoke [PreviousExtensionClass dropTablesForRegisteredName: withTransaction::].
 * Of course this won't work because the PreviousExtensionClass no longer exists.
 * So the end result is that you will likely see the database spit out a warning like this:
 *
 * - Dropping tables for previously registered extension with name(order),
 *     class(YapDatabaseQuack) for new class(YapDatabaseDuck)
 * - Unable to drop tables for previously registered extension with name(order),
 *     unknown class(YapDatabaseQuack)
 *
 * This method helps the extension architecture to understand what's happening, and it won't spit out any warnings.
 *
 * The default implementation returns nil.
**/
+ (NSArray *)previousClassNames
{
	return nil;
}

/**
 * After an extension has been successfully registered with a database,
 * these properties will be set by YapDatabase instance.
 *
 * These properties should be considered READ-ONLY once set.
**/
@synthesize registeredName;
@synthesize registeredDatabase;

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is called during the extension registration process to enusre the extension (as configured)
 * will support the given database configuration. This is primarily for extensions with dependecies.
 *
 * For example, the YapDatabaseFilteredView is configured with the registered name of a parent View instance.
 * So that class should implement this method to ensure:
 * - The parentView actually exists
 * - The parentView is actually a YapDatabaseView class/subclass
 * 
 * When this method is invoked, the 'self.registeredName' & 'self.registeredDatabase' properties
 * will be set and available for inspection.
 * 
 * @param registeredExtensions
 *   The current set of registered extensions. (i.e. self.registeredDatabase.registeredExtensions)
 * 
 * Return YES if the class/instance supports the database configuration.
**/
- (BOOL)supportsDatabaseWithRegisteredExtensions:(NSDictionary __unused *)registeredExtensions
{
	return YES;
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * 
 * This is a simple hook method to let the extension now that it's been registered with the database.
 * This method is invoked after the readWriteTransaction (that registered the extension) has been committed.
 * 
 * Important:
 *   This method is invoked within the writeQueue.
 *   So either don't do anything expensive/time-consuming in this method, or dispatch_async to do it in another queue.
**/
- (void)didRegisterExtension
{
	// Override me if needed
}

/**
 * Subclasses MUST implement this method IF they have dependencies.
 * This method is called during the view registration simply to record the needed dependencies.
 * If any of the dependencies are unregistered, this extension will automatically be unregistered.
 *
 * Return a set of NSString objects, representing the name(s) of registered extensions
 * that this extension is dependent upon.
 *
 * If there are no dependencies, return nil (or an empty set).
 * The default implementation returns nil.
**/
- (NSSet *)dependencies
{
	return nil;
}

/**
 * Subclasses MUST implement this method IF they are non-persistent (in-memory only).
 * By doing so, they allow various optimizations, such as not persisting extension info in the yap2 table.
**/
- (BOOL)isPersistent
{
	return YES;
}

/**
 * Subclasses MUST implement this method.
 * Returns a proper instance of the YapDatabaseExtensionConnection subclass.
**/
- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection __unused *)databaseConnection
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * This method is invoked on the snapshot queue.
 * The given changeset is the most recent commit.
 *
 * This method exists as a possible optimization.
 * For example, the YapDatabaseView extension uses this method to capture the most recent view state.
 * This allows new view connections to be able to (sometimes) fetch the view state from their extension,
 * rather than read it from the database and piece it together manually.
**/
- (void)processChangeset:(NSDictionary __unused *)changeset
{
	// Override me if needed (for optimizations)
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
 * @param extName
 *   The registeredName of the extension.
 *   This is the same as self.registeredName, and is simply passed as a convenience.
**/
- (void)noteCommittedChangeset:(NSDictionary *)changeset registeredName:(NSString *)extName
{
	NSDictionary *ext_changeset = [[changeset objectForKey:YapDatabaseExtensionsKey] objectForKey:extName];
	if (ext_changeset)
	{
		[self processChangeset:ext_changeset];
	}
}

@end
