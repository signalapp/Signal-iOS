#import "YapAbstractDatabaseTransaction.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#import <objc/runtime.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapAbstractDatabaseTransaction

+ (void)load
{
	static BOOL loaded = NO;
	if (!loaded)
	{
		// Method swizzle:
		// Both extension: and ext: are designed to be the same method (with ext: shorthand for extension:).
		// So swap out the ext: method to point to extension:.
		
		Method extMethod = class_getInstanceMethod([self class], @selector(ext:));
		IMP extensionIMP = class_getMethodImplementation([self class], @selector(extension:));
		
		method_setImplementation(extMethod, extensionIMP);
		loaded = YES;
	}
}

- (id)initWithConnection:(YapAbstractDatabaseConnection *)aConnection isReadWriteTransaction:(BOOL)flag
{
	if ((self = [super init]))
	{
		abstractConnection = aConnection;
		isReadWriteTransaction = flag;
	}
	return self;
}

@synthesize abstractConnection = abstractConnection;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction States
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

- (void)preCommitReadWriteTransaction
{
	// Allow extensions to perform any "cleanup" code needed before the changesets are requested,
	// and before the commit is executed.
	
	[extensions enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		[(YapAbstractDatabaseExtensionTransaction *)extTransactionObj preCommitReadWriteTransaction];
	}];
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
	[extensions enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		[(YapAbstractDatabaseExtensionTransaction *)extTransactionObj rollbackTransaction];
	}];
	
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Control
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
	if (isReadWriteTransaction)
		rollback = YES;
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extensions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
- (id)extension:(NSString *)extensionName
{
	// This method is PUBLIC
	
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
			if (isReadWriteTransaction)
				extTransaction = [extConnection newReadWriteTransaction:self];
			else
				extTransaction = [extConnection newReadTransaction:self];
			
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

- (id)ext:(NSString *)extensionName
{
	// This method is PUBLIC
	
	// The "+ (void)load" method swizzles the implementation of this class
	// to point to the implementation of the extension: method.
	//
	// So the two methods are literally the same thing.
	
	return [self extension:extensionName]; // This method is swizzled !
}

- (void)prepareExtensions
{
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	NSDictionary *extConnections = [abstractConnection extensions];
	
	[extConnections enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		__unsafe_unretained NSString *extName = key;
		__unsafe_unretained YapAbstractDatabaseExtensionConnection *extConnection = obj;
		
		YapAbstractDatabaseExtensionTransaction *extTransaction = [extensions objectForKey:extName];
		if (extTransaction == nil)
		{
			if (isReadWriteTransaction)
				extTransaction = [extConnection newReadWriteTransaction:self];
			else
				extTransaction = [extConnection newReadTransaction:self];
			
			if ([extTransaction prepareIfNeeded])
			{
				[extensions setObject:extTransaction forKey:extName];
			}
		}
	}];
	
	if (orderedExtensions == nil)
		orderedExtensions = [[NSMutableArray alloc] initWithCapacity:[extensions count]];
	
	for (NSString *extName in abstractConnection->extensionsOrder)
	{
		YapAbstractDatabaseExtensionTransaction *extTransaction = [extensions objectForKey:extName];
		if (extTransaction)
		{
			[orderedExtensions addObject:extTransaction];
		}
	}
	
	extensionsReady = YES;
}

- (NSDictionary *)extensions
{
	// This method is INTERNAL
	
	if (!extensionsReady)
	{
		[self prepareExtensions];
	}
	
	return extensions;
}

- (NSArray *)orderedExtensions
{
	// This method is INTERNAL
	
	if (!extensionsReady)
	{
		[self prepareExtensions];
	}
	
	return orderedExtensions;
}

- (void)addRegisteredExtensionTransaction:(YapAbstractDatabaseExtensionTransaction *)extTransaction
{
	// This method is INTERNAL
	
	if (extensions == nil)
		extensions = [[NSMutableDictionary alloc] init];
	
	NSString *extName = [[[extTransaction extensionConnection] extension] registeredName];
	
	[extensions setObject:extTransaction forKey:extName];
}

- (void)removeRegisteredExtensionTransaction:(NSString *)extName
{
	// This method is INTERNAL
	
	[extensions removeObjectForKey:extName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Memory Tables
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapMemoryTableTransaction *)memoryTableTransaction:(NSString *)tableName
{
	YapMemoryTable *table = [[abstractConnection registeredTables] objectForKey:tableName];
	if (table)
	{
		uint64_t snapshot = [abstractConnection snapshot];
		
		if (isReadWriteTransaction)
			return [table newReadWriteTransactionWithSnapshot:(snapshot + 1)];
		else
			return [table newReadTransactionWithSnapshot:snapshot];
	}
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Yap2 Table
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)getBoolValue:(BOOL *)valuePtr forKey:(NSString *)key extension:(NSString *)extensionName
{
	int intValue = 0;
	BOOL result = [self getIntValue:&intValue forKey:key extension:extensionName];
	
	if (valuePtr) *valuePtr = (intValue == 0) ? NO : YES;
	return result;
}

- (void)setBoolValue:(BOOL)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	[self setIntValue:(value ? 1 : 0) forKey:key extension:extensionName];
}

- (BOOL)getIntValue:(int *)valuePtr forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapGetDataForKeyStatement];
	if (statement == NULL) {
		if (valuePtr) *valuePtr = 0;
		return NO;
	}
	
	BOOL result = NO;
	int value = 0;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = YES;
		value = sqlite3_column_int(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	if (valuePtr) *valuePtr = value;
	return result;
}

- (void)setIntValue:(int)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (!isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	sqlite3_bind_int(statement, 3, value);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		abstractConnection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (BOOL)getDoubleValue:(double *)valuePtr forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapGetDataForKeyStatement];
	if (statement == NULL) {
		if (valuePtr) *valuePtr = 0.0;
		return NO;
	}
	
	BOOL result = NO;
	double value = 0.0;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = YES;
		value = sqlite3_column_double(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	if (valuePtr) *valuePtr = value;
	return result;
}

- (void)setDoubleValue:(double)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (!isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	sqlite3_bind_double(statement, 3, value);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		abstractConnection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (NSString *)stringValueForKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapGetDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSString *value = nil;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		value = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return value;
}

- (void)setStringValue:(NSString *)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (!isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	YapDatabaseString _value; MakeYapDatabaseString(&_value, value);
	sqlite3_bind_text(statement, 3, _value.str, _value.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		abstractConnection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	FreeYapDatabaseString(&_value);
}

- (NSData *)dataValueForKey:(NSString *)key extension:(NSString *)extensionName
{
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapGetDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSData *value = nil;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		value = [[NSData alloc] initWithBytes:(void *)blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return value;
}

- (void)setDataValue:(NSData *)value forKey:(NSString *)key extension:(NSString *)extensionName
{
	if (!isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	if (extensionName == nil)
		extensionName = @"";
	
	sqlite3_stmt *statement = [abstractConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	__attribute__((objc_precise_lifetime)) NSData *data = value;
	sqlite3_bind_blob(statement, 3, data.bytes, (int)data.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		abstractConnection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(abstractConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (void)removeAllValuesForExtension:(NSString *)extensionName
{
	// Be careful with this statement.
	//
	// The snapshot value is in the yap table, and uses an empty string for the extensionName.
	// The snapshot value is critical to the underlying architecture of the system.
	// Removing it could cripple the system.
	
	NSAssert(extensionName != nil, @"Invalid extensionName. Would result in removing snapshot from yap table!");
	
	sqlite3_stmt *statement = [abstractConnection yapRemoveExtensionStatement];
	if (statement == NULL) return;
	
	// DELETE FROM "yap2" WHERE "extension" = ?;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, extensionName);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_DONE)
	{
		abstractConnection->hasDiskChanges = YES;
	}
	else
	{
		YDBLogError(@"Error executing 'yapRemoveExtensionStatement': %d %s, extension(%@)",
					status, sqlite3_errmsg(abstractConnection->db), extensionName);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)mutationDuringEnumerationException
{
	NSString *reason = [NSString stringWithFormat:
	    @"Database <%@: %p> was mutated while being enumerated.", NSStringFromClass([self class]), self];
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	    @"If you modify the database during enumeration"
		@" you MUST set the 'stop' parameter of the enumeration block to YES (*stop = YES;)."};
	
	return [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
}

@end
