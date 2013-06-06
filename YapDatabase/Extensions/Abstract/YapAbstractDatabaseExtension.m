#import "YapAbstractDatabaseExtension.h"
#import "YapAbstractDatabaseExtensionPrivate.h"


@implementation YapAbstractDatabaseExtension

+ (BOOL)createTablesForRegisteredName:(NSString *)registeredName
                             database:(YapAbstractDatabase *)database
                               sqlite:(sqlite3 *)db
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseExtension");
	return NO;
}

+ (BOOL)dropTablesForRegisteredName:(NSString *)registeredName
                           database:(YapAbstractDatabase *)database
                             sqlite:(sqlite3 *)db
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseExtension");
	return NO;
}

@synthesize registeredName;

- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseExtension");
	return nil;
}

@end
