#import "MyDatabaseObject.h"
#import <objc/runtime.h>


@implementation MyDatabaseObject {
@private
	
	BOOL isImmutable;
	NSMutableSet *changedProperties;
}

@synthesize isImmutable = isImmutable;

/**
 * Make sure all your subclasses call this method ([super init]).
**/
- (instancetype)init
{
	if ((self = [super init]))
	{
		// Turn on KVO for object.
		// We do this so we can get notified if the user is about to make changes to one of the object's properties.
		//
		// Don't worry, this doesn't create a retain cycle.
		
		[self addObserver:self forKeyPath:@"isImmutable" options:0 context:NULL];
	}
	return self;
}

- (void)dealloc
{
	[self removeObserver:self forKeyPath:@"isImmutable" context:NULL];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * In this example, all copies are automatically mutable.
 * So all you have to do in your code is something like this:
 * 
 * [databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction]{
 * 
 *     Car *car = [transaction objectForKey:carId inCollection:@"cars"];
 *     car = [car copy]; // make mutable copy
 *     car.speed = newSpeed;
 *     
 *     [transaction setObject:car forKey:carId inCollection:@"cars"];
 * }];
 * 
 * Which means all you have to do is implement the copyWithZone method in your model classes.
**/
- (id)copyWithZone:(NSZone *)zone
{
	// Subclasses should call this method via [super copyWithZone:zone].
	// For example:
	//
	//   MySubclass *copy = [super copyWithZone:zone];
	//   copy->ivar1 = [ivar1 copy];
	//   copy->ivar2 = ivar2;
	//   return copy;
	
	MyDatabaseObject *copy = [[[self class] alloc] init];
	copy->isImmutable = NO;
	copy->changedProperties = [self->changedProperties mutableCopy];
	
	return copy;
}

/**
 * An alternative is to have [object copy] return an immutable copy,
 * and [object mutableCopy] to return a mutable copy.
 * 
 * Some people prefer it like this. If so then:
 * - uncomment this method
 * - change 'copy->isImmutable = NO' to 'copy->isImmutable = YES' in copyWithZone
 * - and add NSMutableCopying to the list of protocols in the header file
 * 
 * Note: The implemenation below just uses a regular copy, and then sets the isImmutable flag to NO.
 * So if you go this route, you don't have to implement mutableCopyWithZone (just copyWithZone).
**/
//- (instancetype)mutableCopyWithZone:(NSZone *)zone
//{
//	id copy = [self copy];
//	((MyDatabaseObject *)copy)->isImmutable = NO;
//	
//	return copy;
//}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)makeImmutable
{
	if (!isImmutable)
	{
		// Set immutable flag
		isImmutable = YES;
	}
}

- (NSSet *)monitoredProperties
{
	return [[self class] monitoredProperties];
}

- (NSSet *)changedProperties
{
	if ([changedProperties count] == 0) return nil;
	
	// Remove untracked properties from the list.
	[changedProperties intersectSet:[[self class] monitoredProperties]];
	
	// And return immutable copy
	return [changedProperties copy];
}

- (BOOL)hasChangedProperties
{
	return ([changedProperties count] > 0);
}

- (NSSet *)allSyncableProperties
{
	NSMutableDictionary *syncablePropertyMappings = [[self class] syncablePropertyMappings];
	NSMutableSet *allSyncableProperties = [NSMutableSet setWithCapacity:syncablePropertyMappings.count];
	
	for (NSString *syncablePropertyName in [syncablePropertyMappings objectEnumerator])
	{
		[allSyncableProperties addObject:syncablePropertyName];
	}
	
	return allSyncableProperties;
}

- (NSSet *)changedSyncableProperties
{
	if ([changedProperties count] == 0) return nil;
	
	NSMutableSet *changedSyncableProperties = [NSMutableSet setWithCapacity:changedProperties.count];
	NSMutableDictionary *syncablePropertyMappings = [[self class] syncablePropertyMappings];
	
	for (NSString *propertyName in changedProperties)
	{
		NSString *syncablePropertyName = [syncablePropertyMappings objectForKey:propertyName];
		if (syncablePropertyName) {
			[changedSyncableProperties addObject:syncablePropertyName];
		}
	}
	
	return changedSyncableProperties;
}

- (BOOL)hasChangedSyncableProperties
{
	if ([changedProperties count] == 0) return NO;
	
	NSMutableDictionary *syncablePropertyMappings = [[self class] syncablePropertyMappings];
	
	for (NSString *propertyName in changedProperties)
	{
		NSString *syncablePropertyName = [syncablePropertyMappings objectForKey:propertyName];
		if (syncablePropertyName) {
			return YES;
		}
	}
	
	return NO;
}

- (void)clearChangedProperties
{
	changedProperties = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark KVO
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
	if ([key isEqualToString:@"isImmutable"])
		return YES;
	else
		return [super automaticallyNotifiesObserversForKey:key];
}

+ (NSSet *)keyPathsForValuesAffectingIsImmutable
{
	// In order for the KVO magic to work, we specify that the isImmutable property is dependent
	// upon all other properties in the class that should become immutable.
	//
	// The code below ** attempts ** to do this automatically.
	// It does so by creating a list of all the properties in the class.
	//
	// Obviously this will not work for every situation.
	// In particular:
	//
	// - if you have custom setter methods that aren't specified as properties
	// - if you have other custom methods that modify the object
	//
	// To cover these edge cases, simply add code like the following at the beginning of such methods:
	//
	// - (void)recalculateFoo
	// {
	//     if (self.isImmutable) {
	//         @throw [self immutableExceptionForKey:@"foo"];
	//     }
	//
	//     // ... normal code that modifies foo ivar ...
	// }
	
	return [self monitoredProperties];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
	// Nothing to do (but method is required to exist)
}

- (void)willChangeValueForKey:(NSString *)key
{
	if (isImmutable)
	{
		@throw [self immutableExceptionForKey:key];
	}
	
	[super willChangeValueForKey:key];
}

- (void)didChangeValueForKey:(NSString *)key
{
	if (changedProperties == nil)
		changedProperties = [[NSMutableSet alloc] init];
	
	[changedProperties addObject:key];
	[super didChangeValueForKey:key];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSMutableSet *)monitoredProperties
{
	// This method returns a list of all properties that should be monitored.
	// That is, they should show up in the changedProperties set if they are modified..
	// And they should be considered immutable once the makeImmutable method has been invoked.
	//
	// By default this method returns a list of all properties in each subclass in the
	// hierarchy leading to "[self class]".
	//
	// However, this is not always exactly what you want.
	// For example, if you have any properties which are simply used for caching.
	//
	// @property (nonatomic, strong, readwrite) UIImage *avatarImage;
	// @property (nonatomic, strong, readwrite) UIImage *cachedTransformedAvatarImage;
	//
	// In this example, you store the user's plain avatar image.
	// However, your code transforms the avatar in various ways for display in the UI.
	// So to reduce overhead, you'd like to cache these transformed images in the user object.
	// Thus the 'cachedTransformedAvatarImage' property doesn't actually mutate the user object. It's just temporary.
	//
	// So your subclass would override this method like so:
	//
	// + (NSMutableSet *)monitoredProperties
	// {
	//     NSMutableSet *monitoredProperties = [super immutableProperties];
	//     [monitoredProperties removeObject:@"cachedTransformedAvatarImage"];
	//
	//     return monitoredProperties;
	// }
	
	NSMutableSet *properties = nil;
	
	Class rootClass = [MyDatabaseObject class];
	Class subClass = [self class];
	
	while (subClass != rootClass)
	{
		unsigned int count = 0;
		objc_property_t *propertyList = class_copyPropertyList(subClass, &count);
		if (propertyList)
		{
			if (properties == nil)
				properties = [NSMutableSet setWithCapacity:count];
			
			for (unsigned int i = 0; i < count; i++)
			{
				const char *name = property_getName(propertyList[i]);
				NSString *property = [NSString stringWithUTF8String:name];
				
				[properties addObject:property];
			}
			
			free(propertyList);
		}
		
		subClass = [subClass superclass];
	}
	
	return properties;
}

+ (NSMutableDictionary *)syncablePropertyMappings
{
	// This method returns a mapping from localPropertyName to ckRecordPropertyName.
	//
	// By default this method returns a dictionary including everything in [self immutableProperties],
	// where the key is equal to the value for every item.
	//
	// For example:
	// @{ @"title" = @"title",
	//    @"isCompleted" = @"isCompleted",
	//    @"creationDate" = @"creationDate",
	//    @"lastModified" = @"lastModified",
	//    @"isSeen" = @"isSeen"
	// }
	//
	// However, this is not always exactly what you want.
	// For example, you may not want to sync the 'isSeen' property because its device-specific.
	//
	// Additionally you discover that CKRecord has a built-in creationDate property,
	// and so CKRecord doesn't allow you to use that key for your own purposes. (It's reserved.)
	//
	// You can still name your own property "creationDate",
	// but you'll be forced to use a different name for the CKRecord.
	// So let's say we decide to use "created" as the corresponding key in the CKRecord.
	//
	// Thus your subclass overrides this method like so:
	//
	// + (NSMutableDictionary *)syncablePropertyMappings
	// {
	//     NSMutableDictionary *syncablePropertyMappings = [super syncablePropertyMappings];
	//
	//     [syncablePropertyMappings removeObjectForKey:@"isSeen"];
	//     [syncablePropertyMappings setObject:@"created" forKey:@"creationDate"];
	//
	//     return syncablePropertyMappings;
	// }
	
	NSMutableSet *properties = [self monitoredProperties];
	
	NSMutableDictionary *syncablePropertyMappings = [NSMutableDictionary dictionaryWithCapacity:properties.count];
	
	for (NSString *propertyName in properties)
	{
		[syncablePropertyMappings setObject:propertyName forKey:propertyName];
	}
	
	return syncablePropertyMappings;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Exceptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSException *)immutableExceptionForKey:(NSString *)key
{
	NSString *reason;
	if (key)
		reason = [NSString stringWithFormat:
		    @"Attempting to mutate immutable object. Class = %@, property = %@", NSStringFromClass([self class]), key];
	else
		reason = [NSString stringWithFormat:
		    @"Attempting to mutate immutable object. Class = %@", NSStringFromClass([self class])];
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
		@"To make modifications you should create a copy via [object copy]."
		@" You may then make changes to the copy before saving it back to the database."};
	
	return [NSException exceptionWithName:@"STDatabaseObjectException" reason:reason userInfo:userInfo];
}

@end
