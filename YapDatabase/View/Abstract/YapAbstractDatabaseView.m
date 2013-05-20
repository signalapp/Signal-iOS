#import "YapAbstractDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapAbstractDatabaseView

+ (BOOL)createTablesForRegisteredName:(NSString *)registeredName
                             database:(YapAbstractDatabase *)database
                               sqlite:(sqlite3 *)db
                                error:(NSError **)errorPtr
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseView");
	
	if (errorPtr)
	{
		NSDictionary *userInfo = @{
		    NSLocalizedDescriptionKey: @"Missing required override method in subclass of YapAbstractDatabaseView" };
		
		*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:404 userInfo:userInfo];
	}
	return NO;
}

+ (BOOL)dropTablesForRegisteredName:(NSString *)registeredName
                           database:(YapAbstractDatabase *)database
                             sqlite:(sqlite3 *)db
                              error:(NSError **)errorPtr
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseView");
	
	if (errorPtr)
	{
		NSDictionary *userInfo = @{
		    NSLocalizedDescriptionKey: @"Missing required override method in subclass of YapAbstractDatabaseView" };
		
		*errorPtr = [NSError errorWithDomain:@"YapDatabase" code:404 userInfo:userInfo];
	}
	return NO;
}

@synthesize registeredName;

- (YapAbstractDatabaseViewConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	NSAssert(NO, @"Missing required override method in subclass of YapAbstractDatabaseView");
	return nil;
}

@end
