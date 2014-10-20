#import "YapDatabaseCloudKitOptions.h"

@implementation YapDatabaseCloudKitOptions

@synthesize allowedCollections = allowedCollections;

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseCloudKitOptions *copy = [[[self class] alloc] init]; // [self class] required to support subclassing
	copy->allowedCollections = allowedCollections;
	
	return copy;
}

@end
