#import "YapAbstractDatabaseExtensionTransaction.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapAbstractDatabasePrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
 **/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapAbstractDatabaseExtensionTransaction

/**
 * This method is invoked as part of the registration process.
**/
- (void)willRegister:(BOOL *)isFirstTimeExtensionRegistration
{
	NSString *prevClassName = [self stringValueForExtensionKey:@"class"];
	
	if (prevClassName == nil)
	{
		*isFirstTimeExtensionRegistration = YES;
		return;
	}
	
	NSString *ourClassName = NSStringFromClass([self class]);
	
	if ([prevClassName isEqualToString:ourClassName])
	{
		*isFirstTimeExtensionRegistration = NO;
		return;
	}
	
	YDBLogWarn(@"Dropping tables for previously registered extension with name(%@), class(%@) for new class(%@)",
	           [self registeredName], prevClassName, ourClassName);
	
	Class class = NSClassFromString(prevClassName);
	
	if (class == NULL)
	{
		YDBLogError(@"Unable to drop tables for previously registered extension with name(%@), unknown class(%@)",
		            [self registeredName], prevClassName);
		
		*isFirstTimeExtensionRegistration = YES;
		return;
	}
	else
	{
		// Todo: Invoke drop tables method...
	}
	
	*isFirstTimeExtensionRegistration = YES;
}

/**
 * This method is invoked as part of the registration process.
**/
- (void)didRegister:(BOOL)isFirstTimeExtensionRegistration
{
	if (isFirstTimeExtensionRegistration)
	{
		[self setStringValue:NSStringFromClass([self class]) forExtensionKey:@"class"];
	}
}

/**
 * See YapAbstractDatabaseExtensionPrivate for discussion of this method.
**/
- (BOOL)createFromScratch:(BOOL)isFirstTimeExtensionRegistration
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

/**
 * See YapAbstractDatabaseExtensionPrivate for discussion of this method.
**/
- (BOOL)prepareIfNeeded
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

/**
 * This method is called if within a readwrite transaction.
 * This method is optional.
**/
- (void)preCommitTransaction
{
	// Subclasses may optionally override this method to perform any "cleanup" before the changesets are requested.
	// Remember, the changesets are requested before the commitTransaction method is invoked.
}

/**
 * This method is called if within a readwrite transaction.
**/
- (void)commitTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	// Subclasses should include the code similar to the following at the end of their implementation:
	//
	// viewConnection = nil;
	// databaseTransaction = nil;
}

- (YapAbstractDatabaseTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (NSString *)registeredName
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Persistent Values
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The following method are convenience methods for getting and setting persistent values for the extension.
 * The persistent values are stored in the yap2 table, which is specifically designed for this use.
**/

- (int)intValueForExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	sqlite3_stmt *statement = [databaseConnection yapGetDataForKeyStatement];
	if (statement == NULL) return 0;
	
	int result = 0;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = sqlite3_column_int(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return result;
}

- (void)setIntValue:(int)value forExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	sqlite3_stmt *statement = [databaseConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	sqlite3_bind_int(statement, 3, value);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (double)doubleValueForExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	sqlite3_stmt *statement = [databaseConnection yapGetDataForKeyStatement];
	if (statement == NULL) return 0.0;
	
	double result = 0.0;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		result = sqlite3_column_double(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
					status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return result;
}

- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	sqlite3_stmt *statement = [databaseConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	sqlite3_bind_double(statement, 3, value);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
					status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

- (NSString *)stringValueForExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	sqlite3_stmt *statement = [databaseConnection yapGetDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSString *string = nil;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const unsigned char *text = sqlite3_column_text(statement, 0);
		int textSize = sqlite3_column_bytes(statement, 0);
		
		string = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return string;
}

- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	sqlite3_stmt *statement = [databaseConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	YapDatabaseString _value; MakeYapDatabaseString(&_value, value);
	sqlite3_bind_text(statement, 3, _value.str, _value.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	FreeYapDatabaseString(&_value);
}

- (NSData *)dataValueForExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	sqlite3_stmt *statement = [databaseConnection yapGetDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSData *data = nil;
	
	// SELECT data FROM 'yap2' WHERE extension = ? AND key = ? ;
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		data = [[NSData alloc] initWithBytes:(void *)blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'yapGetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
	
	return data;
}

- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key
{
	YapAbstractDatabaseTransaction *databaseTransaction = [self databaseTransaction];
	YapAbstractDatabaseConnection *databaseConnection = databaseTransaction->abstractConnection;
	
	if (!databaseTransaction->isReadWriteTransaction)
	{
		YDBLogError(@"Cannot modify database outside readwrite transaction.");
		return;
	}
	
	sqlite3_stmt *statement = [databaseConnection yapSetDataForKeyStatement];
	if (statement == NULL) return;
	
	// INSERT OR REPLACE INTO "yap2" ("extension", "key", "data") VALUES (?, ?, ?);
	
	YapDatabaseString _extension; MakeYapDatabaseString(&_extension, [self registeredName]);
	sqlite3_bind_text(statement, 1, _extension.str, _extension.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	__attribute__((objc_precise_lifetime)) NSData *data = value;
	sqlite3_bind_blob(statement, 3, data.bytes, (int)data.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'yapSetDataForKeyStatement': %d %s",
		                                                       status, sqlite3_errmsg(databaseConnection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_extension);
	FreeYapDatabaseString(&_key);
}

@end
