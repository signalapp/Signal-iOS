#import "YapAbstractDatabaseExtension.h"
#import "YapAbstractDatabaseExtensionPrivate.h"


@implementation YapAbstractDatabaseExtension

+ (BOOL)createTablesForRegisteredName:(NSString *)registeredName
                             database:(YapAbstractDatabase *)database
                               sqlite:(sqlite3 *)db
                                error:(NSError **)errorPtr
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseExtension");
	
	if (errorPtr)
	{
		NSDictionary *userInfo = @{
		    NSLocalizedDescriptionKey: @"Missing required override method in subclass of YapAbstractDatabaseExtension"
		};
		
		*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:404 userInfo:userInfo];
	}
	return NO;
}

+ (BOOL)dropTablesForRegisteredName:(NSString *)registeredName
                           database:(YapAbstractDatabase *)database
                             sqlite:(sqlite3 *)db
                              error:(NSError **)errorPtr
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseExtension");
	
	if (errorPtr)
	{
		NSDictionary *userInfo = @{
		    NSLocalizedDescriptionKey: @"Missing required override method in subclass of YapAbstractDatabaseExtension"
		};
		
		*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:404 userInfo:userInfo];
	}
	return NO;
}

@synthesize registeredName;

- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseExtension");
	return nil;
}

@end
