#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseHooks.h"
#import "YapDatabaseHooksConnection.h"
#import "YapDatabaseHooksTransaction.h"


@interface YapDatabaseHooks () {
@public
	
	YapWhitelistBlacklist *allowedCollections;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseHooksConnection () {
@public
	
	__strong YapDatabaseHooks *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
}

- (id)initWithParent:(YapDatabaseHooks *)inParent databaseConnection:(YapDatabaseConnection *)inDbC;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseHooksTransaction () {
@protected
	
	__unsafe_unretained YapDatabaseHooksConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
	
	YapProxyObject *proxyObject;
	YapProxyObject *proxyMetadata;
}

- (id)initWithParentConnection:(YapDatabaseHooksConnection *)parentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
