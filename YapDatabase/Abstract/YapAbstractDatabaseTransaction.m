#import "YapAbstractDatabaseTransaction.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
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
		[extensions enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
			
			[(YapAbstractDatabaseExtensionTransaction *)extTransactionObj commitTransaction];
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
 * The YapDatabaseModifiedNotification is posted following a readwrite transaction which made changes.
 * 
 * These notifications are used in a variety of ways:
 * - They may be used as a general notification mechanism to detect changes to the database.
 * - They may be used by extensions to post change information.
 *   For example, YapDatabaseView will post the index changes, which can easily be used to animate a tableView.
 * - They are integrated into the architecture of long-lived transactions in order to maintain a steady state.
 *
 * Thus it is recommended you integrate your own notification information into this existing notification,
 * as opposed to broadcasting your own separate notification.
 *
 * Invoking this method from within a read-only transaction does nothing.
**/
- (void)setCustomObjectForYapDatabaseModifiedNotification:(id)object
{
	if (isReadWriteTransaction)
		customObjectForNotification = object;
}

/**
 * Returns an extension transaction corresponding to the extension type registered under the given name.
 * If the extension has not yet been prepared, it is done so automatically.
 *
 * @return
 *     A subclass of YapAbstractDatabaseExtensionTransaction,
 *     according to the type of extension registered under the given name.
 *
 * One must register an extension with the database before it can be accessed from within connections or transactions.
 * After registration everything works automatically using just the registered extension name.
 *
 * @see [YapAbstractDatabase registerExtension:withName:]
**/
- (id)extension:(NSString *)extensionName { return [self ext:extensionName]; }
- (id)ext:(NSString *)extensionName
{
	if (extensionsReady)
		return [extensions objectForKey:extensionName];
	
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	YapAbstractDatabaseExtensionTransaction *extTransaction = [extensions objectForKey:extensionName];
	if (extTransaction == nil)
	{
		YapAbstractDatabaseExtensionConnection *extConnection = [abstractConnection extension:extensionName];
		if (extConnection)
		{
			extTransaction = [extConnection newTransaction:self];
			
			if ([extTransaction prepareIfNeeded])
			{
				[extensions setObject:extTransaction forKey:extensionName];
			}
			else
			{
				extTransaction = nil;
			}
		}
	}
	
	return extTransaction;
}

#pragma mark Internal API

- (NSDictionary *)extensions
{
	if (extensionsReady)
		return extensions;
	
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	NSDictionary *extConnections = [abstractConnection extensions];
	
	[extConnections enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSString *extName = key;
		__unsafe_unretained YapAbstractDatabaseExtensionConnection *extConnection = obj;
		
		YapAbstractDatabaseExtensionTransaction *extTransaction = [extensions objectForKey:extName];
		if (extTransaction == nil)
		{
			extTransaction = [extConnection newTransaction:self];
			if ([extTransaction prepareIfNeeded])
			{
				[extensions setObject:extTransaction forKey:extName];
			}
		}
	}];
	
	extensionsReady = YES;
	return extensions;
}

@end
