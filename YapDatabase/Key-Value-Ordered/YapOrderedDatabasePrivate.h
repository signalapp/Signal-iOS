#import <Foundation/Foundation.h>

#import "YapOrderedDatabase.h"
#import "YapOrderedDatabaseConnection.h"
#import "YapOrderedDatabaseTransaction.h"
#import "sqlite3.h"

@interface YapOrderedDatabase ()

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapOrderedDatabaseConnection () {
@private
	sqlite3_stmt *getOrderDataForKeyStatement;
	sqlite3_stmt *setOrderDataForKeyStatement;
	sqlite3_stmt *removeOrderDataForKeyStatement;
	sqlite3_stmt *removeAllOrderDataStatement;
	
@public
	YapDatabaseOrder *order;
}

- (id)initWithDatabase:(YapOrderedDatabase *)inDatabase;

- (sqlite3_stmt *)getOrderDataForKeyStatement;
- (sqlite3_stmt *)setOrderDataForKeyStatement;
- (sqlite3_stmt *)removeOrderDataForKeyStatement;
- (sqlite3_stmt *)removeAllOrderDataStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapOrderedDatabaseReadTransactionProxy : NSObject <YapOrderReadTransaction> {
@protected
	__unsafe_unretained YapOrderedDatabaseConnection *connection;
	
	__strong id transaction; // YapDatabaseReadTransaction or YapDatabaseReadWriteTransaction
}

- (id)initWithConnection:(YapOrderedDatabaseConnection *)connection
             transaction:(YapDatabaseReadTransaction *)transaction;

@end

@interface YapOrderedDatabaseReadWriteTransactionProxy : YapOrderedDatabaseReadTransactionProxy
                                                        <YapOrderReadWriteTransaction>

@end
