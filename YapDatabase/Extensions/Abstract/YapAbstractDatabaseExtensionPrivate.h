#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseExtension.h"
#import "YapAbstractDatabaseExtensionConnection.h"
#import "YapAbstractDatabaseExtensionTransaction.h"

#import "YapAbstractDatabase.h"
#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabaseTransaction.h"

#import "sqlite3.h"


@interface YapAbstractDatabaseExtension ()

/**
 * 
**/
+ (BOOL)dropTablesForRegisteredName:(NSString *)registeredName
                           database:(YapAbstractDatabase *)database
                             sqlite:(sqlite3 *)db;

/**
 * After an extension has been successfully registered with a database,
 * the registeredName property will be set by the database.
**/
@property (atomic, copy, readwrite) NSString *registeredName;

/**
 * Subclasses must implement this method.
 * This method is called during the view registration process to enusre the extension supports the database type.
 * 
 * Return YES if the class/instance supports the particular type of database (YapDatabase vs YapCollectionsDatabase).
**/
- (BOOL)supportsDatabase:(YapAbstractDatabase *)database;

/**
 * Subclasses must override this method to create and return a proper instance of the
 * YapAbstractDatabaseExtensionConnection subclass.
**/
- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapAbstractDatabaseExtensionConnection () {

// You should store a strong reference to the parent,
// and an unretained reference to the corresponding database connection.
// 
// Yours should be similar to the example below, but typed according to your needs.

/* Example from YapDatabaseViewConnection
 
@public
	__strong YapDatabaseView *view;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;

*/
}

/**
 * Subclasses must override these methods to create and return a proper instance of the
 * YapAbstractDatabaseExtensionTransaction subclass.
**/
- (id)newReadTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction;
- (id)newReadWriteTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction;

- (void)_flushMemoryWithLevel:(int)level;

- (void)postRollbackCleanup;

- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr externalChangeset:(NSMutableDictionary **)externalPtr;
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
 *     //         ^ Returns a YapAbstractDatabaseExtensionTransaction subclass instance.
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
@interface YapAbstractDatabaseExtensionTransaction () {

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
 * The following methods are implemented by YapAbstractDatabaseExtension.
 * Subclasses may override them if desired.
**/
- (void)willRegister:(BOOL *)isFirstTimeExtensionRegistration;
- (void)didRegister:(BOOL)isFirstTimeExtensionRegistration;

/**
 * Subclasses must implement this method in order to properly create the extension.
 * This includes creating any necessary tables,
 * as well as populating the tables by enumerating over the existing rows in the database.
 * 
 * The given BOOL indicates if this is the first time the extension has been registered.
 * That is, this value will be YES the very first time the extension is registered with this name.
 * Subsequent registrations (on later app launches) will pass NO.
 * 
 * In general, a YES parameter means the extension needs to create the tables and populate itself.
 * A NO parameter means the extension is likely ready to go.
**/
- (BOOL)createFromScratch:(BOOL)isFirstTimeExtensionRegistration;

/**
 * Subclasses must implement this method in order to do whatever setup is needed for use.
 * Remember, an extension transaction should store the majority of its state within the extension connection.
 * Thus an extension should generally only need to prepare itself once (with the exception of rollback operations).
 *
 * Changes that occur on other connections should get incorporated via the changeset architecture
 * from within the extension connection subclass.
 * 
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded;

/**
 * This method is only called if within a readwrite transaction.
 * This method is optional.
 *
 * Subclasses may implement it to perform any "cleanup" before the changeset is requested.
 * Remember, the changeset is requested before the commitTransaction method is invoked.
**/
- (void)preCommitTransaction;

/**
 * This method is only called if within a readwrite transaction.
**/
- (void)commitTransaction;

/**
 * Subclasses must implement these methods.
 * They are needed by the utility methods listed below.
**/
- (YapAbstractDatabaseTransaction *)databaseTransaction;
- (NSString *)registeredName;

/**
 * The following method are convenience methods for getting and setting persistent values for the extension.
 * The persistent values are stored in the yap2 table, which is specifically designed for this use.
**/

- (int)intValueForExtensionKey:(NSString *)key;
- (void)setIntValue:(int)value forExtensionKey:(NSString *)key;

- (double)doubleValueForExtensionKey:(NSString *)key;
- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key;

- (NSString *)stringValueForExtensionKey:(NSString *)key;
- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key;

- (NSData *)dataValueForExtensionKey:(NSString *)key;
- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The YapAbstractDatabaseExtensionTransaction subclass MUST implement the methods in this protocol if
 * it supports YapDatabase.
**/
@protocol YapAbstractDatabaseExtensionTransaction_KeyValue
@required

- (void)handleSetObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata;
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key;
- (void)handleRemoveObjectForKey:(NSString *)key;
- (void)handleRemoveObjectsForKeys:(NSArray *)keys;
- (void)handleRemoveAllObjects;

@end

/**
 * The YapAbstractDatabaseExtensionTransaction subclass MUST implement the methods in this protocol if
 * it supports YapCollectionsDatabase.
**/
@protocol YapAbstractDatabaseExtensionTransaction_CollectionKeyValue
@required

- (void)handleSetObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata;
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)handleRemoveObjectForKey:(NSString *)key inCollection:(NSString *)collection;
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection;
- (void)handleRemoveAllObjectsInCollection:(NSString *)collection;
- (void)handleRemoveAllObjectsInAllCollections;

@end
