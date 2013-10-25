#import "YapAbstractDatabaseDefaults.h"


@implementation YapAbstractDatabaseDefaults

@synthesize objectCacheEnabled = objectCacheEnabled;
@synthesize objectCacheLimit = objectCacheLimit;

@synthesize metadataCacheEnabled = metadataCacheEnabled;
@synthesize metadataCacheLimit = metadataCacheLimit;

@synthesize objectPolicy = objectPolicy;
@synthesize metadataPolicy = metadataPolicy;

#if TARGET_OS_IPHONE
@synthesize autoFlushMemoryLevel = autoFlushMemoryLevel;
#endif

- (id)init
{
	if ((self = [super init]))
	{
		objectCacheEnabled = YES;
		objectCacheLimit = 250;
		
		metadataCacheEnabled = YES;
		metadataCacheLimit = 500;
		
		objectPolicy = YapDatabasePolicyContainment;
		metadataPolicy = YapDatabasePolicyContainment;
		
		#if TARGET_OS_IPHONE
		autoFlushMemoryLevel = YapDatabaseConnectionFlushMemoryLevelMild;
		#endif
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapAbstractDatabaseDefaults *copy = [[[self class] alloc] init];
	
	copy->objectCacheEnabled = objectCacheEnabled;
	copy->objectCacheLimit = objectCacheLimit;
	
	copy->metadataCacheEnabled = metadataCacheEnabled;
	copy->metadataCacheLimit = metadataCacheLimit;
	
	copy->objectPolicy = objectPolicy;
	copy->metadataPolicy = metadataPolicy;
	
	#if TARGET_OS_IPHONE
	copy->autoFlushMemoryLevel = autoFlushMemoryLevel;
	#endif
	
	return copy;
}

@end
