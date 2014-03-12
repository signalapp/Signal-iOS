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
 * This method is called if within a readwrite transaction.
 * This method is optional.
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

- (BOOL)getBoolValue:(BOOL *)valuePtr forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	return [[self databaseTransaction] getBoolValue:valuePtr forKey:key extension:registeredName];
}

- (BOOL)boolValueForExtensionKey:(NSString *)key
{
	BOOL value = NO;
	[self getBoolValue:&value forExtensionKey:key];
	return value;
}

- (void)setBoolValue:(BOOL)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	[[self databaseTransaction] setBoolValue:value forKey:key extension:registeredName];
}

- (BOOL)getIntValue:(int *)valuePtr forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	return [[self databaseTransaction] getIntValue:valuePtr forKey:key extension:registeredName];
}

- (int)intValueForExtensionKey:(NSString *)key
{
	int value = 0;
	[self getIntValue:&value forExtensionKey:key];
	return value;
}

- (void)setIntValue:(int)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	[[self databaseTransaction] setIntValue:value forKey:key extension:registeredName];
}

- (BOOL)getDoubleValue:(double *)valuePtr forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	return [[self databaseTransaction] getDoubleValue:valuePtr forKey:key extension:registeredName];
}

- (double)doubleValueForExtensionKey:(NSString *)key
{
	double value = 0.0;
	[self getDoubleValue:&value forExtensionKey:key];
	return value;
}

- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	[[self databaseTransaction] setDoubleValue:value forKey:key extension:registeredName];
}

- (NSString *)stringValueForExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	return [[self databaseTransaction] stringValueForKey:key extension:registeredName];
}

- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	[[self databaseTransaction] setStringValue:value forKey:key extension:registeredName];
}

- (NSData *)dataValueForExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	return [[self databaseTransaction] dataValueForKey:key extension:registeredName];
}

- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	[[self databaseTransaction] setDataValue:value forKey:key extension:registeredName];
}

- (void)removeValueForExtensionKey:(NSString *)key
{
	NSString *registeredName = [[[self extensionConnection] extension] registeredName];
	[[self databaseTransaction] removeValueForKey:key extension:registeredName];
}

@end
