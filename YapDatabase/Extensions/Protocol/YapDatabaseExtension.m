#import "YapDatabaseExtension.h"
#import "YapDatabaseExtensionPrivate.h"


@implementation YapDatabaseExtension

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

+ (NSArray *)previousClassNames
{
	return nil;
}

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
