#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseView.h"
#import "YapAbstractDatabaseViewConnection.h"
#import "YapAbstractDatabaseViewTransaction.h"

#import "YapAbstractDatabase.h"
#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabaseTransaction.h"

#import "sqlite3.h"


@interface YapAbstractDatabaseView ()

/**
 * This method is invoked as part of the view registration process.
 * All views must implement this method and attempt to create (if needed) their table(s) from within this method.
 * 
 * A view may use zero or more tables for its operations.
 *
 * A view MUST take steps to avoid table name collisions.
 * For example, a view cannot choose to name its table "database", as that name is reserved for the primary table.
 *
 * The following best practices are recommended:
 * - incorporate the registeredName into the table name(s).
 * - incorporate a unique word (e.g. "view") into the table name(s).
 *
 * For example: "view_[registeredName]"
 *
 * A view class may support YapDatabase, YapCollectionsDatabase, or both.
 * The implementation of this method should inspect database parameter class type to ensure proper support.
 * 
 * The db parameter is for one-time use within this method, and should not be saved in any manner.
 * 
 * If an error occurs, this method should return NO and set the error parameter.
 * Otherwise return YES after creating the tables.
**/
+ (BOOL)createTablesForRegisteredName:(NSString *)registeredName
                             database:(YapAbstractDatabase *)database
                               sqlite:(sqlite3 *)db
                                error:(NSError **)errorPtr;

/**
 * 
**/
+ (BOOL)dropTablesForRegisteredName:(NSString *)registeredName
                           database:(YapAbstractDatabase *)database
                             sqlite:(sqlite3 *)db
                              error:(NSError **)errorPtr;

/**
 * After a view has been successfully registered with a database,
 * the registeredName property will be set by the database.
**/
@property (atomic, copy, readwrite) NSString *registeredName;

/**
 * Subclasses must override this method to create and return a proper instance of the
 * YapAbstractDatabaseViewConnection subclass.
**/
- (YapAbstractDatabaseViewConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapAbstractDatabaseViewConnection () {
@public
	__strong YapAbstractDatabaseView *abstractView;
	__unsafe_unretained YapAbstractDatabaseConnection *databaseConnection;
}

/**
 * Subclasses should invoke this init method from within their own init method(s), if they have any.
**/
- (id)initWithView:(YapAbstractDatabaseView *)view databaseConnection:(YapAbstractDatabaseConnection *)connection;

/**
 * Subclasses must override this method to create and return a proper instance of the
 * YapAbstractDatabaseViewTransaction subclass.
**/
- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction;

- (void)postRollbackCleanup;

- (NSMutableDictionary *)changeset;
- (void)processChangeset:(NSDictionary *)changeset;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * A view transaction is where a majority of the action happens.
 * Subclasses will list the majority of their public API within the transaction.
 * 
 * [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
 * 
 *     object = [[transaction view:@"myview"] objectAtIndex:index];
 *     //         ^^^^^^^^^^^^^^^^^^^^^^^^^^
 *     //         ^ Returns a YapAbstractDatabaseViewTransaction subclass instance.
 * }];
 *
 * A view transaction has a reference to the database transction (and therefore to sqlite),
 * as well as a reference to its parent view connection. It is the same in architecture as
 * database connections and transactions. That is, all access (read-only or read-write) goes
 * through a transaction. Further, each connection only has a single transaction at a time.
 * Thus transactions are optimized by storing a majority of their state within their respective connection.
 * 
 * A view transaction is created on-demand (or as needed) from within a database transaction.
 *
 * During a read-only transaction:
 * - If the view is not requested, then it is not created.
 * - If the view is requested, it is created once per transaction.
 * - Additional requests for the same view return the existing instance.
 *
 * During a read-write transaction:
 * - If a modification to the database is initiated,
 *   every registered view has an associated transaction created in order to handle the associated hook calls.
 * - If the view is requested, it is created once per transaction.
 * - Additional requests for the same view return the existing instance.
 *
 * The view transaction is only valid from within the database transaction.
**/
@interface YapAbstractDatabaseViewTransaction () {
@protected
	__unsafe_unretained YapAbstractDatabaseViewConnection *abstractViewConnection;
	__unsafe_unretained YapAbstractDatabaseTransaction *databaseTransaction;
}

/**
 * Subclasses should invoke this init method from within their own init method(s), if they have any.
**/
- (id)initWithViewConnection:(YapAbstractDatabaseViewConnection *)viewConnection
         databaseTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction;

/**
 * Subclasses may override this method in order to do whatever setup is needed for use.
 * Remember, a view transaction should store the majority of its state within the view connection.
 * Thus a view should generally only need to prepare itself once (with the exception of rollback operations).
 *
 * Changes that occur on other connections should get incorporated via the changeset architecture
 * from within the view connection subclass.
**/
- (BOOL)prepareIfNeeded;

/**
 * This method is called if within a readwrite transaction.
 * Subclasses should invoke [super commitTransaction] at the END of their implementation.
**/
- (void)commitTransaction;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The YapAbstractDatabaseViewTransaction subclass MUST implement the methods in this protocol if
 * it supports YapDatabase.
**/
@protocol YapAbstractDatabaseViewKeyValueTransaction
@required

- (void)handleSetObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata;
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key;
- (void)handleRemoveObjectForKey:(NSString *)key;
- (void)handleRemoveObjectsForKeys:(NSArray *)keys;
- (void)handleRemoveAllObjects;

@end

/**
 * The YapAbstractDatabaseViewTransaction subclass MUST implement the methods in this protocol if
 * it supports YapCollectionsDatabase.
**/
@protocol YapAbstractDatabaseViewCollectionKeyValueTransaction
@required

- (void)handleSetObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata inCollection:(NSString *)collection;
- (void)handleSetMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)handleRemoveObjectForKey:(NSString *)key inCollection:(NSString *)collection;
- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection;
- (void)handleRemoveAllObjectsInCollection:(NSString *)collection;
- (void)handleRemoveAllObjectsInAllCollections;

@end
