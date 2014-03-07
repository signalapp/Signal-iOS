#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseExtensionConnection.h"
#import "YapDatabaseExtensionTransaction.h"

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"
#import "YapCollectionKey.h"

#import "sqlite3.h"


@interface YapDatabaseExtension ()

/**
 * Subclasses MUST implement this method.
 *
 * This method is used when unregistering an extension in order to drop the related tables.
**/
+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * If an extension class is renamed this method should be used to properly transition.
 * The extension architecture will verify that a re-registered extension is using the same
 * extension class that it was previously using. If the class names differ, then the extension architecture
 * will automatically try to unregister the previous extension using the previous extension class.
 * 
 * That is, it will attempt to invoke [PreviousExtensionClass dropTablesForRegisteredName: withTransaction:].
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
+ (NSArray *)previousClassNames;

/**
 * After an extension has been successfully registered with a database,
 * the registeredName property will be set by the database.
 * 
 * This property is set by YapDatabase after a successful registration.
 * It should be considered read-only once set.
**/
@property (atomic, copy, readwrite) NSString *registeredName;

/**
 * Subclasses MUST implement this method.
 * This method is called during the view registration process to enusre the extension supports the database type.
 * The registered extensions are passed too, in case dependencies need to be checked.
 * 
 * Return YES if the class/instance supports the database configuration.
**/
- (BOOL)supportsDatabase:(YapDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions;

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
- (NSSet *)dependencies;

/**
 * Subclasses MUST implement this method.
 * Returns a proper instance of the YapDatabaseExtensionConnection subclass.
**/
- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseExtensionConnection () {

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
 * Returns a reference to the parent (base class).
 *
 * This method is used by various general utility classes in order to
 * walk-the-chain: extension <-> extConnection <-> extTransaction.
 * 
 * For example:
 * Given an extTransaction, the utility method can walk up to the base extension class, and fetch the registeredName.
**/
- (YapDatabaseExtension *)extension;

/**
 * Subclasses MUST implement these methods.
 * They are to create and return a proper instance of the YapDatabaseExtensionTransaction subclass.
 * 
 * They may optionally use different subclasses for read-only vs read-write transactions.
 * Alternatively they can just store an ivar to determine the type of the transaction in order to protect as needed.
**/
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction;
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction;

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
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags;

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
              hasDiskChanges:(BOOL *)hasDiskChangesPtr;

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
- (void)processChangeset:(NSDictionary *)changeset;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * An extension transaction is where a majority of the action happens.
 * Subclasses will list the majority of their public API within the transaction.
 * 
 * [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 * 
 *     object = [[transaction ext:@"view"] objectAtIndex:index inGroup:@"sales"];
 *     //         ^^^^^^^^^^^^^^^^^^^^^^^
 *     //         ^ Returns a YapDatabaseExtensionTransaction subclass instance.
 * }];
 *
 * An extension transaction has a reference to the database transction (and therefore to sqlite),
 * as well as a reference to its parent extension connection. It is the same in architecture as
 * database connections and transactions. That is, all access (read-only or read-write) goes
 * through a transaction. Further, each connection only has a single transaction at a time.
 * Thus transactions are optimized by storing a majority of their state within their respective connection.
 * 
 * An extension transaction is created on-demand (or as needed) from within a database transaction.
 *
 * During a read-only transaction:
 * - If the extension is not requested, then it is not created.
 * - If the extension is requested, it is created once per transaction.
 * - Additional requests for the same extension return the existing instance.
 *
 * During a read-write transaction:
 * - If a modification to the database is initiated,
 *   every registered extension has an associated transaction created in order to handle the associated hook calls.
 * - If the extension is requested, it is created once per transaction.
 * - Additional requests for the same extension return the existing instance.
 *
 * The extension transaction is only valid from within the database transaction.
**/
@interface YapDatabaseExtensionTransaction () {

// You should store an unretained reference to the parent,
// and an unretained reference to the corresponding database transaction.
//
// Yours should be similar to the example below, but typed according to your needs.
	
/* Example from YapDatabaseViewTransaction

@private
	__unsafe_unretained YapDatabaseViewConnection *viewConnection;
	__unsafe_unretained YapDatabaseTransaction *databaseTransaction;

*/
}

/**
 * Subclasses MUST implement this method.
 * 
 * This method is called during the registration process.
 * Subclasses should perform any tasks needed in order to setup the extension for use by other connections.
 *
 * This includes creating any necessary tables,
 * as well as possibly populating the tables by enumerating over the existing rows in the database.
 * 
 * The method should check to see if it has already been created.
 * That is, is this a re-registration from a subsequent app launch,
 * or is this the first time the extension has been registered under this name?
 * 
 * The recommended way of accomplishing this is via the yap2 table (which was designed for this purpose).
 * There are various convenience methods that allow you store various settings about your extension in this table.
 * See 'intValueForExtensionKey:' and other related methods.
 * 
 * Note: This method is invoked on a special readWriteTransaction that is created internally
 * within YapDatabase for the sole purpose of registering and unregistering extensions.
 * So this method need not setup itself for regular use.
 * It is designed only to do the prep work of creating the extension dependencies (such as tables)
 * so that regular instances (possibly read-only) can operate normally.
 *
 * See YapDatabaseViewTransaction for a reference implementation.
 * 
 * Return YES if completed successfully, or if already created.
 * Return NO if some kind of error occured.
**/
- (BOOL)createIfNeeded;

/**
 * Subclasses MUST implement this method.
 *
 * This method is invoked in order to prepare an extension transaction for use.
 * Remember, transactions are short lived instances.
 * So an extension transaction should store the vast majority of its state information within the extension connection.
 * Thus an extension transaction instance should generally only need to prepare itself once. (*)
 * It should store preparation info in the connection.
 * And future invocations of this method will see that the connection has all the prepared state it needs,
 * and then this method will return immediately.
 * 
 * (*) an exception to this rule may occur if the user aborts a read-write transaction (via rollback),
 *     and the extension connection must dump all its prepared state.
 *
 * Changes that occur on other connections should get incorporated via the changeset architecture
 * from within the extension connection subclass.
 * 
 * This method may be invoked on a read-only OR read-write transaction.
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded;

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should ONLY implement this method if they need to make changes to the 'database' table.
 * That is, the main collection/key/value table that directly stores the user's objects.
 *
 * Return NO if the extension does not directly modify the main database table.
 * Return YES if the extension does modify the main database table,
 * regardless of whether it made changes during this invocation.
 *
 * This method may be invoked several times in a row.
**/
- (BOOL)flushPendingChangesToMainDatabaseTable;

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses may implement it to perform any "cleanup" before the changeset is requested.
 * Remember, the changeset is requested before the commitTransaction method is invoked.
**/
- (void)prepareChangeset;

/**
 * Subclasses MUST implement this method.
 * This method is only called if within a readwrite transaction.
**/
- (void)commitTransaction;

/**
 * Subclasses MUST implement this method.
 * This method is only called if within a readwrite transaction.
**/
- (void)rollbackTransaction;

/**
 * Subclasses MUST implement these methods.
 * They are needed by various utility methods.
**/
- (YapDatabaseReadTransaction *)databaseTransaction;
- (YapDatabaseExtensionConnection *)extensionConnection;

/**
 * The following method are implemented by YapDatabaseExtensionTransaction.
 * 
 * They are convenience methods for getting and setting persistent configuration values for the extension.
 * The persistent values are stored in the yap2 table, which is specifically designed for this use.
 * 
 * The yap2 table is structured like this:
 * 
 * CREATE TABLE IF NOT EXISTS "yap2" (
 *   "extension" CHAR NOT NULL,
 *   "key" CHAR NOT NULL,
 *   "data" BLOB,
 *   PRIMARY KEY ("extension", "key")
 * );
 * 
 * You pass the "key" and the "data" (which can be typed however you want it to be such as int, string, etc).
 * The "extension" value is automatically set to the registeredName.
 * 
 * Usage example:
 * 
 *   The View extension stores a "version" which is given to it during the init method by the user.
 *   If the "version" changes, this signifies that the user has changed something about the view,
 *   such as the sortingBlock or groupingBlock. The view then knows to flush its tables and re-populate them.
 *   It stores the "version" in the yap2 table via the methods below.
 * 
 * When an extension is unregistered, either manually or automatically (if orphaned),
 * then the database system automatically deletes all values from the yap2 table where extension == registeredName.
**/

- (BOOL)getBoolValue:(BOOL *)valuePtr forExtensionKey:(NSString *)key;
- (BOOL)boolValueForExtensionKey:(NSString *)key;
- (void)setBoolValue:(BOOL)value forExtensionKey:(NSString *)key;

- (BOOL)getIntValue:(int *)valuePtr forExtensionKey:(NSString *)key;
- (int)intValueForExtensionKey:(NSString *)key;
- (void)setIntValue:(int)value forExtensionKey:(NSString *)key;

- (BOOL)getDoubleValue:(double *)valuePtr forExtensionKey:(NSString *)key;
- (double)doubleValueForExtensionKey:(NSString *)key;
- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key;

- (NSString *)stringValueForExtensionKey:(NSString *)key;
- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key;

- (NSData *)dataValueForExtensionKey:(NSString *)key;
- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key;

- (void)removeValueForExtensionKey:(NSString *)key;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The YapDatabaseExtensionTransaction subclass MUST implement the methods in this protocol.
**/
@protocol YapDatabaseExtensionTransaction_Hooks
@required

- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid;

- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid;

- (void)handleReplaceObject:(id)object
           forCollectionKey:(YapCollectionKey *)collectionKey
                  withRowid:(int64_t)rowid;

- (void)handleReplaceMetadata:(id)metadata
             forCollectionKey:(YapCollectionKey *)collectionKey
                    withRowid:(int64_t)rowid;

- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;

- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids;

- (void)handleRemoveAllObjectsInAllCollections;

@end
