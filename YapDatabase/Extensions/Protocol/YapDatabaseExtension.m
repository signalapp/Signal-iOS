#import "YapDatabaseExtension.h"
#import "YapDatabaseExtensionPrivate.h"


@implementation YapDatabaseExtension

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * If an extension class is renamed this method should be used to properly transition.
 * The extension architecture will verify that a re-registered extension is using the same
 * extension class that it was previously using. If the class names differ, then the extension architecture
 * will automatically try to unregister the previous extension using the previous extension class.
 *
 * That is, it will attempt to invoke [PreviousExtensionClass dropTablesForRegisteredName: withTransaction:].
 * Of course this won't work because the PreviousExtensionClass no longer exists.
 * So the end result is that you will likely see the database spit out a warning like this:
 *
 * - Dropping tables for previously registered extension with name(order),
 *     class(YapDatabaseQuack) for new class(YapDatabaseDuck)
 * - Unable to drop tables for previously registered extension with name(order),
 *     unknown class(YapDatabaseQuack)
 *
 * This method helps the extension architecture to understand what's happening, and it won't spit out any warnings.
 *
 * The default implementation returns nil.
**/
+ (NSArray *)previousClassNames
{
	return nil;
}

/**
 * Read-only property.
 * Automatically set by YapDatabase instance during the registration process.
**/
@synthesize registeredName;

/**
 * Subclasses must implement this method.
 * This method is called during the view registration process to enusre the extension supports the database type.
 * 
 * Return YES if the class/instance supports the database configuration.
**/
- (BOOL)supportsDatabase:(YapDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

/**
 * Subclasses MUST implement this method IF they have dependencies.
 * This method is called during the view registration simply to record the needed dependencies.
 * If any of the dependencies are unregistered, this extension will automatically be unregistered.
 *
 * Return a set of NSString objects, representing the name(s) of registered extensions
 * that this extension is dependent upon.
 *
 * If there are no dependencies, return nil (or an empty set).
 * The default implementation returns nil.
**/
- (NSSet *)dependencies
{
	return nil;
}

/**
 * Subclasses MUST implement this method.
 * Returns a proper instance of the YapDatabaseExtensionConnection subclass.
**/
- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

@end
