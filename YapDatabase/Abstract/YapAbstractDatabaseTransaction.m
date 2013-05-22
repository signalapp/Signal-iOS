#import "YapAbstractDatabaseTransaction.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseViewPrivate.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapAbstractDatabaseTransaction

- (id)initWithConnection:(YapAbstractDatabaseConnection *)aConnection isReadWriteTransaction:(BOOL)flag
{
	if ((self = [super init]))
	{
		abstractConnection = aConnection;
		isReadWriteTransaction = flag;
	}
	return self;
}

- (void)beginTransaction
{
	sqlite3_stmt *statement = [abstractConnection beginTransactionStatement];
	if (statement == NULL) return;
	
	// BEGIN TRANSACTION;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Couldn't begin transaction: %d %s", status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_reset(statement);
}

- (void)commitTransaction
{
	if (isReadWriteTransaction)
	{
		[views enumerateKeysAndObjectsUsingBlock:^(id viewNameObj, id viewTransactionObj, BOOL *stop) {
			
			[(YapAbstractDatabaseViewTransaction *)viewTransactionObj commitTransaction];
		}];
	}
	
	sqlite3_stmt *statement = [abstractConnection commitTransactionStatement];
	if (statement == NULL) return;
	
	// COMMIT TRANSACTION;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Couldn't commit transaction: %d %s", status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_reset(statement);
}

- (void)rollbackTransaction
{
	sqlite3_stmt *statement = [abstractConnection rollbackTransactionStatement];
	if (statement == NULL) return;
	
	// ROLLBACK TRANSACTION;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Couldn't rollback transaction: %d %s", status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_reset(statement);
}

#pragma mark Public API

/**
 * Under normal circumstances, when a read-write transaction block completes,
 * the changes are automatically committed. If, however, something goes wrong and
 * you'd like to abort and discard all changes made within the transaction,
 * then invoke this method.
 *
 * You should generally return (exit the transaction block) after invoking this method.
 * Any changes made within the the transaction before and after invoking this method will be discarded.
 *
 * Invoking this method from within a read-only transaction does nothing.
**/
- (void)rollback
{
	abstractConnection->rollback = YES;
}

/**
 * Returns a view transaction corresponding to the view type registered under the given name.
 * If the view has not yet been opened, it is done so automatically.
 *
 * @return
 *     A subclass of YapAbstractDatabaseViewTransaction,
 *     according to the type of view registered under the given name.
 *
 * One must register a view with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the view name.
 *
 * @see [YapAbstractDatabase registerView:withName:]
**/
- (id)view:(NSString *)viewName
{
	if (viewsReady)
		return [views objectForKey:viewName];
	
	if (views == nil)
		views = [[NSMutableDictionary alloc] init];
	
	YapAbstractDatabaseViewTransaction *viewTransaction = [views objectForKey:viewName];
	if (viewTransaction == nil)
	{
		YapAbstractDatabaseViewConnection *viewConnection = [abstractConnection view:viewName];
		if (viewConnection)
		{
			viewTransaction = [viewConnection newTransaction:self];
			if ([viewTransaction prepareIfNeeded])
			{
				[views setObject:viewTransaction forKey:viewName];
			}
		}
	}
	else if (![viewTransaction prepareIfNeeded])
	{
		[views removeObjectForKey:viewName];
		viewTransaction = nil;
	}
	
	return viewTransaction;
}

#pragma mark Internal API

- (NSDictionary *)views
{
	if (viewsReady)
		return views;
	
	if (views == nil)
		views = [[NSMutableDictionary alloc] init];
	
	NSDictionary *viewConnections = [abstractConnection views];
	
	[viewConnections enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSString *viewName = key;
		__unsafe_unretained YapAbstractDatabaseViewConnection *viewConnection = obj;
		
		YapAbstractDatabaseViewTransaction *viewTransaction = [views objectForKey:viewName];
		if (viewTransaction == nil)
		{
			viewTransaction = [viewConnection newTransaction:self];
			if ([viewTransaction prepareIfNeeded])
			{
				[views setObject:viewTransaction forKey:viewName];
			}
		}
		else if (![viewTransaction prepareIfNeeded])
		{
			[views removeObjectForKey:viewName];
		}
	}];
	
	viewsReady = YES;
	return views;
}

@end
