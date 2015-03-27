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

	YDBHooks_WillInsertObject willInsertObject;
	YDBHooks_DidInsertObject   didInsertObject;

	YDBHooks_WillUpdateObject willUpdateObject;
	YDBHooks_DidInsertObject   didUpdateObject;

	YDBHooks_WillReplaceObject willReplaceObject;
	YDBHooks_DidReplaceObject   didReplaceObject;

	YDBHooks_WillReplaceMetadata willReplaceMetadata;
	YDBHooks_DidReplaceMetadata   didReplaceMetadata;

	YDBHooks_WillRemoveObject willRemoveObject;
	YDBHooks_DidRemoveObject   didRemoveObject;

	YDBHooks_WillRemoveObjects willRemoveObjects;
	YDBHooks_DidRemoveObjects   didRemoveObjects;

	YDBHooks_WillRemoveAllObjectsInAllCollections willRemoveAllObjectsInAllCollections;
	YDBHooks_DidRemoveAllObjectsInAllCollections didRemoveAllObjectsInAllCollections;
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
}

- (id)initWithParentConnection:(YapDatabaseHooksConnection *)parentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
