#import "YapAbstractDatabaseExtension.h"
#import "YapAbstractDatabaseExtensionPrivate.h"


@implementation YapAbstractDatabaseExtension

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
}

@synthesize registeredName;

/**
 * Subclasses must implement this method.
 * This method is called during the view registration process to enusre the extension supports the database type.
 * 
 * Return YES if the class/instance supports the particular type of database (YapDatabase vs YapCollectionsDatabase).
**/
- (BOOL)supportsDatabase:(YapAbstractDatabase *)database
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return NO;
}

/**
 * Subclasses may optionally implement this method to support dependencies.
 * This method is called during the view registration process to enusre the dependencies are available.
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
 * Returns a proper instance of the YapAbstractDatabaseExtensionConnection subclass.
**/
- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	NSAssert(NO, @"Missing required method(%@) in class(%@)", NSStringFromSelector(_cmd), [self class]);
	return nil;
}

@end
