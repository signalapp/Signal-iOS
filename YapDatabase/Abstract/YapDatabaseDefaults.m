#import "YapDatabaseDefaults.h"


@implementation YapDatabaseDefaults

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
	YapDatabaseDefaults *copy = [[[self class] alloc] init];
	
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

- (void)setObjectPolicy:(YapDatabasePolicy)newObjectPolicy
{
	// sanity check
	switch (newObjectPolicy)
	{
		case YapDatabasePolicyContainment :
		case YapDatabasePolicyShare       :
		case YapDatabasePolicyCopy        : objectPolicy = newObjectPolicy; break;
		default                           : objectPolicy = YapDatabasePolicyContainment; // revert to default
	}
}

- (void)setMetadataPolicy:(YapDatabasePolicy)newMetadataPolicy
{
	// sanity check
	switch (newMetadataPolicy)
	{
		case YapDatabasePolicyContainment :
		case YapDatabasePolicyShare       :
		case YapDatabasePolicyCopy        : metadataPolicy = newMetadataPolicy; break;
		default                           : metadataPolicy = YapDatabasePolicyContainment; // revert to default
	}
}

@end
