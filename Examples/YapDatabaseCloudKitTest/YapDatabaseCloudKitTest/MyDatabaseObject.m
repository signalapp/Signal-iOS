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

- (NSSet *)changedProperties
{
	// We may have tracked changes to properties that are excluded from the list.
	// For example, temp properties used for caching transformed values.
	//
	// @see [MyDatabaseObject immutableProperties]
	//
	[changedProperties unionSet:[[self class] immutableProperties]];
	
	// And return immutable NSSet
	return [changedProperties copy];
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
	// upon all other properties in the class that should become immutable..
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
	//     // ... normal code ...
	// }
	
	return [self immutableProperties];
}

+ (NSMutableSet *)immutableProperties
{
	// This method returns a list of all properties that should be considered immutable once
	// the makeImmutable method has been invoked.
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
	// + (NSMutableSet *)immutableProperties
	// {
	//     NSMutableSet *immutableProperties = [super immutableProperties];
	//     [immutableProperties removeObject:@"cachedTransformedAvatarImage"];
	//
	//     return immutableProperties;
	// }
	
	NSMutableSet *dependencies = nil;
	
	Class rootClass = [MyDatabaseObject class];
	Class subClass = [self class];
	
	while (subClass != rootClass)
	{
		unsigned int count = 0;
		objc_property_t *properties = class_copyPropertyList(subClass, &count);
		if (properties)
		{
			if (dependencies == nil)
				dependencies = [NSMutableSet setWithCapacity:count];
			
			for (unsigned int i = 0; i < count; i++)
			{
				const char *name = property_getName(properties[i]);
				NSString *property = [NSString stringWithUTF8String:name];
				
				[dependencies addObject:property];
			}
			
			free(properties);
		}
		
		subClass = [subClass superclass];
	}
	
	return dependencies;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
	// Nothing to do
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
