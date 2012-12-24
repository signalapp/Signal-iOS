#import <Foundation/Foundation.h>

#import "YapOrderedCollectionsDatabase.h"
#import "YapOrderedCollectionsDatabaseConnection.h"
#import "YapOrderedCollectionsDatabaseTransaction.h"
#import "sqlite3.h"

@interface YapOrderedCollectionsDatabase ()

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapOrderedCollectionsDatabaseConnection () {
@private
	sqlite3_stmt *getOrderDataForKeyStatement;
	sqlite3_stmt *setOrderDataForKeyStatement;
	sqlite3_stmt *removeOrderDataForKeyStatement;
	sqlite3_stmt *removeOrderDataForCollectionStatement;
	sqlite3_stmt *removeAllOrderDataStatement;
	
@public
	NSMutableDictionary *orderDict;
}

- (id)initWithDatabase:(YapOrderedCollectionsDatabase *)inDatabase;

- (sqlite3_stmt *)getOrderDataForKeyStatement;
- (sqlite3_stmt *)setOrderDataForKeyStatement;
- (sqlite3_stmt *)removeOrderDataForKeyStatement;
- (sqlite3_stmt *)removeOrderDataForCollectionStatement;
- (sqlite3_stmt *)removeAllOrderDataStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapOrderedCollectionsDatabaseReadTransactionProxy : NSObject <YapOrderReadTransaction> {
@protected
	__unsafe_unretained YapOrderedCollectionsDatabaseConnection *connection;
	
	__strong id transaction; // YapCollectionsDatabaseReadTransaction or YapCollectionsDatabaseReadWriteTransaction
}

- (id)initWithConnection:(YapOrderedCollectionsDatabaseConnection *)connection
             transaction:(YapCollectionsDatabaseReadTransaction *)transaction;

- (YapDatabaseOrder *)orderForCollection:(NSString *)collection;

@end

@interface YapOrderedCollectionsDatabaseReadWriteTransactionProxy : YapOrderedCollectionsDatabaseReadTransactionProxy
                                                                   <YapOrderReadWriteTransaction>

@end
