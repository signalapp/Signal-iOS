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
	
	NSString *ourClassName = NSStringFromClass([[self extension] class]);
	
	if ([prevClassName isEqualToString:ourClassName])
	{
		*isFirstTimeExtensionRegistration = NO;
		return;
	}
	
	YDBLogWarn(@"Dropping tables for previously registered extension with name(%@), class(%@) for new class(%@)",
	           [[self extension] registeredName], prevClassName, ourClassName);
	
	Class prevClass = NSClassFromString(prevClassName);
	
	if (prevClass == NULL)
	{
		YDBLogError(@"Unable to drop tables for previously registered extension with name(%@), unknown class(%@)",
		            [[self extension] registeredName], prevClassName);
	}
	else if (![prevClass isSubclassOfClass:[YapAbstractDatabaseExtension class]])
	{
		YDBLogError(@"Unable to drop tables for previously registered extension with name(%@), invalid class(%@)",
		            [[self extension] registeredName], prevClassName);
	}
	else
	{
		[prevClass dropTablesForRegisteredName:[[self extension] registeredName]
		                       withTransaction:[self databaseTransaction]];
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
		NSString *ourClassName = NSStringFromClass([[self extension] class]);
		
		[self setStringValue:ourClassName forExtensionKey:@"class"];
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
- (void)preCommitReadWriteTransaction
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

- (YapAbstractDatabaseExtension *)extension
{
	NSAssert(NO, @"Missing required override method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

- (YapAbstractDatabaseExtensionConnection *)extensionConnection
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
	NSString *registeredName = [[self extension] registeredName];
	
	return [[self databaseTransaction] intValueForKey:key extension:registeredName];
}

- (void)setIntValue:(int)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[self extension] registeredName];
	
	[[self databaseTransaction] setIntValue:value forKey:key extension:registeredName];
}

- (double)doubleValueForExtensionKey:(NSString *)key
{
	NSString *registeredName = [[self extension] registeredName];
	
	return [[self databaseTransaction] doubleValueForKey:key extension:registeredName];
}

- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[self extension] registeredName];
	
	[[self databaseTransaction] setDoubleValue:value forKey:key extension:registeredName];
}

- (NSString *)stringValueForExtensionKey:(NSString *)key
{
	NSString *registeredName = [[self extension] registeredName];
	
	return [[self databaseTransaction] stringValueForKey:key extension:registeredName];
}

- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[self extension] registeredName];
	
	[[self databaseTransaction] setStringValue:value forKey:key extension:registeredName];
}

- (NSData *)dataValueForExtensionKey:(NSString *)key
{
	NSString *registeredName = [[self extension] registeredName];
	
	return [[self databaseTransaction] dataValueForKey:key extension:registeredName];
}

- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key
{
	NSString *registeredName = [[self extension] registeredName];
	
	[[self databaseTransaction] setDataValue:value forKey:key extension:registeredName];
}

@end
