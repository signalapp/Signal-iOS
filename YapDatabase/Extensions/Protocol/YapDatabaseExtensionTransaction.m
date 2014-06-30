#import "YapDatabaseExtensionTransaction.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif


@implementation YapDatabaseExtensionTransaction

/**
 * See YapDatabaseExtensionPrivate for discussion of this method.
**/
- (BOOL)createIfNeeded
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

/**
 * See YapDatabaseExtensionPrivate for discussion of this method.
**/
- (BOOL)prepareIfNeeded
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is only called if within a readwrite transaction.
 *
 * Subclasses should ONLY implement this method if they need to make changes to the 'database' table.
 * That is, the main collection/key/value table that directly stores the user's objects.
 *
 * Return NO if the extension does not directly modify the main database table.
 * Return YES if the extension does modify the main database table,
 * regardless of whether it made changes during this invocation.
 *
 * This method may be invoked several times in a row.
**/
- (BOOL)flushPendingChangesToMainDatabaseTable
{
	return NO;
}

/**
 * Subclasses may OPTIONALLY implement this method.
 * This method is called if within a readwrite transaction.
**/
- (void)prepareChangeset
{
	// Subclasses may optionally override this method to perform any "cleanup" before the changesets are requested.
	// Remember, the changesets are requested before the commitTransaction method is invoked.
}

/**
 * This method is only called if within a readwrite transaction.
**/
- (void)commitTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	// Subclasses should include the code similar to the following at the end of their implementation:
	//
	// viewConnection = nil;
	// databaseTransaction = nil;
}

/**
 * This method is only called if within a readwrite transaction.
**/
- (void)rollbackTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	
	// Subclasses should include the code similar to the following at the end of their implementation:
	//
	// viewConnection = nil;
	// databaseTransaction = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Generic Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseReadTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (YapDatabaseExtensionConnection *)extensionConnection
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

- (BOOL)getBoolValue:(BOOL *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] getBoolValue:valuePtr forKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] memoryTableTransaction:@"yap"] objectForKey:ck];
		if (object)
		{
			if (valuePtr) *valuePtr = [object boolValue];
			return YES;
		}
		else
		{
			if (valuePtr) *valuePtr = NO;
			return NO;
		}
	}
}

- (BOOL)boolValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	BOOL value = NO;
	[self getBoolValue:&value forExtensionKey:key persistent:persistent];
	return value;
}

- (void)setBoolValue:(BOOL)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setBoolValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction memoryTableTransaction:@"yap"] setObject:@(value) forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (BOOL)getIntValue:(int *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] getIntValue:valuePtr forKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] memoryTableTransaction:@"yap"] objectForKey:ck];
		if (object)
		{
			if (valuePtr) *valuePtr = [object intValue];
			return YES;
		}
		else
		{
			if (valuePtr) *valuePtr = 0;
			return NO;
		}
	}
}

- (int)intValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	int value = 0;
	[self getIntValue:&value forExtensionKey:key persistent:persistent];
	return value;
}

- (void)setIntValue:(int)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setIntValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction memoryTableTransaction:@"yap"] setObject:@(value) forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (BOOL)getDoubleValue:(double *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] getDoubleValue:valuePtr forKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] memoryTableTransaction:@"yap"] objectForKey:ck];
		if (object)
		{
			if (valuePtr) *valuePtr = [object doubleValue];
			return YES;
		}
		else
		{
			if (valuePtr) *valuePtr = 0.0;
			return NO;
		}
	}
}

- (double)doubleValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	double value = 0.0;
	[self getDoubleValue:&value forExtensionKey:key persistent:persistent];
	return value;
}

- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setDoubleValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction memoryTableTransaction:@"yap"] setObject:@(value) forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (NSString *)stringValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] stringValueForKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] memoryTableTransaction:@"yap"] objectForKey:ck];
		
		if ([object isKindOfClass:[NSString class]])
			return object;
		if ([object isKindOfClass:[NSNumber class]])
			return [(NSNumber *)object stringValue];
		
		return nil;
	}
}

- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setStringValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction memoryTableTransaction:@"yap"] setObject:value forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (NSData *)dataValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	
	if (persistent)
	{
		return [[self databaseTransaction] dataValueForKey:key extension:registeredName];
	}
	else
	{
		YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
		
		id object = [[[self databaseTransaction] memoryTableTransaction:@"yap"] objectForKey:ck];
		
		if ([object isKindOfClass:[NSData class]])
			return (NSData *)object;
		else
			return nil;
	}
}

- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction setDataValue:value forKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction memoryTableTransaction:@"yap"] setObject:value forKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

- (void)removeValueForExtensionKey:(NSString *)key persistent:(BOOL)persistent
{
	YapDatabaseReadTransaction *databaseTransaction = [self databaseTransaction];
	if (databaseTransaction->isReadWriteTransaction)
	{
		NSString *registeredName = [[[self extensionConnection] extension] registeredName];
		
		if (persistent)
		{
			__unsafe_unretained YapDatabaseReadWriteTransaction *rwDatabaseTransaction =
			  (YapDatabaseReadWriteTransaction *)databaseTransaction;
			
			[rwDatabaseTransaction removeValueForKey:key extension:registeredName];
		}
		else
		{
			YapCollectionKey *ck = [[YapCollectionKey alloc] initWithCollection:registeredName key:key];
			
			[[databaseTransaction memoryTableTransaction:@"yap"] removeObjectForKey:ck];
		}
	}
	else
	{
		NSAssert(NO, @"Cannot modify database outside of readWrite transaction!");
	}
}

@end
