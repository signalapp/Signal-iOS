#import "YapFilePath.h"

// Constants for NSCoding
static NSString *const k_pathComponents = @"pathComponents";
static NSString *const k_isDirectory    = @"isDirectory";


@implementation YapFilePath

+ (NSArray<NSString *> *)sanitizePathComponents:(NSArray<NSString *> *)inPathComponents
{
	NSMutableArray *sanitizedPathComponents = [NSMutableArray arrayWithCapacity:(inPathComponents.count + 1)];
	NSCharacterSet *legalCharacters = [[self illegalCharacters] invertedSet];
	
	for (NSString *pathComponent in inPathComponents)
	{
		if ([pathComponent isEqualToString:@"/"])
		{
			[sanitizedPathComponents addObject:pathComponent];
		}
		else
		{
			NSString *sanitizedPath = [pathComponent stringByAddingPercentEncodingWithAllowedCharacters:legalCharacters];
			
			if (sanitizedPath) {
				[sanitizedPathComponents addObject:sanitizedPath];
			}
		}
	}
	
	// Removing the following entries:
	// - "/" (extra separators, excluding first entry)
	// - ""  (empty string)
	//
	
	BOOL isAbsolute = NO;
	
	NSUInteger i = 0;
	while (i < sanitizedPathComponents.count)
	{
		__unsafe_unretained NSString *pathComponent = sanitizedPathComponents[i];
		
		if (pathComponent.length == 0)
		{
			[sanitizedPathComponents removeObjectAtIndex:i];
		}
		else if ([pathComponent isEqualToString:@"/"])
		{
			if (i == 0) {
				isAbsolute = YES;
				i++;
			}
			else {
				[sanitizedPathComponents removeObjectAtIndex:i];
			}
		}
		else
		{
			i++;
		}
	}
	
	if (!isAbsolute) {
		[sanitizedPathComponents insertObject:@"/" atIndex:0];
	}
	
	return [sanitizedPathComponents copy];
}

+ (NSCharacterSet *)illegalCharacters
{
	NSMutableCharacterSet *charSet = [[NSMutableCharacterSet alloc] init];
	
	[charSet formUnionWithCharacterSet:[NSCharacterSet controlCharacterSet]];
	[charSet addCharactersInString:@"/"];
	
	return [charSet copy];
}

+ (BOOL)isCaseSensitive
{
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize pathComponents = pathComponents;
@synthesize isDirectory = isDirectory;

@dynamic path;

- (instancetype)initWithPath:(NSString *)path isDirectory:(BOOL)inIsDirectory
{
	return [self initWithPathComponents:[path pathComponents] isDirectory:inIsDirectory];
}

- (instancetype)initWithPathComponents:(NSArray<NSString *> *)inPathComponents isDirectory:(BOOL)inIsDirectory
{
	if (inPathComponents.count == 0) return nil;
	
	NSArray<NSString *> *sanitizedPathComponents = [[self class] sanitizePathComponents:inPathComponents];
	
	if ((self = [super init]))
	{
		pathComponents = sanitizedPathComponents;
		isDirectory = inIsDirectory;
		
		if (self.isRootDirectory) {
			isDirectory = YES; // force proper value
		}
	}
	return self;
}

- (instancetype)initWithURL:(NSURL *)url isDirectory:(BOOL)inIsDirectory
{
	return [self initWithPathComponents:[url pathComponents] isDirectory:inIsDirectory];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		pathComponents = [decoder decodeObjectForKey:k_pathComponents];
		isDirectory = [decoder decodeBoolForKey:k_isDirectory];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:pathComponents forKey:k_pathComponents];
	[coder encodeBool:isDirectory forKey:k_isDirectory];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	return self; // Instances are immutable
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Primitives
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isRootDirectory
{
	return (pathComponents.count <= 1);
}

- (BOOL)isCaseSensitive
{
	return [[self class] isCaseSensitive];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark String Conversion
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSMutableString *)_path
{
	NSUInteger capacity = 0;
	
	for (NSString *pathComponent in pathComponents)
	{
		capacity += (1 + pathComponent.length);
	}
	
	if (isDirectory) {
		capacity++; // for trailing "/"
	}
	
	NSMutableString *path = [NSMutableString stringWithCapacity:capacity];
	
	// The first pathComponent is always "/"
	
	[pathComponents enumerateObjectsUsingBlock:^(NSString *pathComponent, NSUInteger idx, BOOL *stop) {
		
		if (idx == 0)
		{
			[path appendString:@"/"];
		}
		else
		{
			if (idx != 1) {
				[path appendString:@"/"];
			}
			[path appendString:pathComponent];
		}
	}];
		
	if (isDirectory) {
		[path appendString:@"/"];
	}
	
	return path;
}

- (NSString *)path
{
	return [[self _path] copy];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@[%p] \"%@\">", [self class], self, [self path]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Comparison
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)hash
{
	NSString *path = [self _path];
	
	if (![[self class] isCaseSensitive])
	{
		path = [path lowercaseString];
	}
	
	return [path hash];
}

- (BOOL)isEqual:(id)object
{
	if ([object isKindOfClass:[YapFilePath class]])
		return [self isEqualToFilePath:(YapFilePath *)object];
	else
		return NO;
}

/**
 * Returns YES if both filePath's have matching pathComponents & isDirectory properties.
 *
 * (Case-sensitivity of the cloud server's filesystem is properly taking into account when comparing fileNames.)
**/
- (BOOL)isEqualToFilePath:(YapFilePath *)another
{
	if (another == nil) return NO;
	
	if (isDirectory != another->isDirectory) return NO;
	
	NSUInteger sCount = self->pathComponents.count;
	NSUInteger aCount = another->pathComponents.count;
	
	if (sCount != aCount) return NO;
	
	BOOL isCaseSensitive = [[self class] isCaseSensitive];
	
	for (NSUInteger i = 0; i < sCount; i++)
	{
		__unsafe_unretained NSString *sPath = self->pathComponents[i];
		__unsafe_unretained NSString *aPath = another->pathComponents[i];
		
		if (isCaseSensitive) {
			if (![sPath isEqualToString:aPath]) return NO;
		}
		else {
			if ([sPath caseInsensitiveCompare:aPath] != NSOrderedSame) return NO;
		}
	}
	
	return YES;
}

/**
 * Returns YES if 'self' is a directory, and 'another' is a file or directory within 'self', at any depth.
 *
 * For example, if 'self' is "/foo" :
 *
 * - "/foo"         -> NO  (but isEqualToFilePath: would return YES)
 * - "/foo/bar"     -> YES
 * - "/foo/man/chu" -> YES
 * - "/Foo/bar"     -> YES (if cloud server is case-insensitive)
 * - "/buzz"        -> NO
**/
- (BOOL)containsFilePath:(YapFilePath *)another
{
	if (another == nil) return NO;
	
	if (!isDirectory) return NO;
	
	NSUInteger sCount = self->pathComponents.count;
	NSUInteger aCount = another->pathComponents.count;
	
	if (sCount >= aCount) return NO;
	
	BOOL isCaseSensitive = [[self class] isCaseSensitive];
	
	for (NSUInteger i = 0; i < sCount; i++)
	{
		__unsafe_unretained NSString *sPath = self->pathComponents[i];
		__unsafe_unretained NSString *aPath = another->pathComponents[i];
		
		if (isCaseSensitive) {
			if (![sPath isEqualToString:aPath]) return NO;
		}
		else {
			if ([sPath caseInsensitiveCompare:aPath] != NSOrderedSame) return NO;
		}
	}
	
	return YES;
}

/**
 * A shortcut for invoking: [fp isEqualToFilePath:another] || [fp containsFilePath:another]
 *
 * (This method is more efficient than invoking both methods.)
**/
- (BOOL)isEqualOrContainsFilePath:(YapFilePath *)another
{
	if (another == nil) return NO;
	
	NSUInteger sCount = self->pathComponents.count;
	NSUInteger aCount = another->pathComponents.count;
	
	if (sCount == aCount)
	{
		// isEqualToFilePath ?
		
		if (isDirectory != another->isDirectory) return NO;
		
		BOOL isCaseSensitive = [[self class] isCaseSensitive];
		
		for (NSUInteger i = 0; i < sCount; i++)
		{
			__unsafe_unretained NSString *sPath = self->pathComponents[i];
			__unsafe_unretained NSString *aPath = another->pathComponents[i];
			
			if (isCaseSensitive) {
				if (![sPath isEqualToString:aPath]) return NO;
			}
			else {
				if ([sPath caseInsensitiveCompare:aPath] != NSOrderedSame) return NO;
			}
		}
		
		return YES;
		
	}
	else if (sCount < aCount)
	{
		// containsFilePath ?
		
		if (!isDirectory) return NO;
		
		BOOL isCaseSensitive = [[self class] isCaseSensitive];
		
		for (NSUInteger i = 0; i < sCount; i++)
		{
			__unsafe_unretained NSString *sPath = self->pathComponents[i];
			__unsafe_unretained NSString *aPath = another->pathComponents[i];
			
			if (isCaseSensitive) {
				if (![sPath isEqualToString:aPath]) return NO;
			}
			else {
				if ([sPath caseInsensitiveCompare:aPath] != NSOrderedSame) return NO;
			}
		}
		
		return YES;
	}
	else
	{
		return NO;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Derivatives
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Conditionally returns a new filePath instance if:
 * - the src is equal to the receiver
 * - or the src conts the receiver
 *
 * In which case a new filePath is returned with the beginning
 * path components represented by src replaced by dst.
 *
 * Otherwise returns nil.
**/
- (YapFilePath *)filePathByMovingFrom:(YapFilePath *)src to:(YapFilePath *)dst
{
	if (src == nil) return nil;
	if (dst == nil) return nil;
	
	// Is match ?
	
	if ([src isEqualToFilePath:self])
	{
		return dst;
	}
	
	// Is within hierarchy (within directory or subdirectory)
	
	if ([src containsFilePath:self])
	{
		__unsafe_unretained NSArray *oldPathComponents = self.pathComponents;
		__unsafe_unretained NSArray *srcPathComponents =  src.pathComponents;
		__unsafe_unretained NSArray *dstPathComponents =  dst.pathComponents;
		
		NSUInteger oldCount = oldPathComponents.count;
		NSUInteger srcCount = srcPathComponents.count;
		NSUInteger dstCount = dstPathComponents.count;
		
		NSUInteger capacity = oldCount - srcCount + dstCount;
		
		NSMutableArray *newPathComponents = [NSMutableArray arrayWithCapacity:capacity];
		[newPathComponents addObjectsFromArray:dstPathComponents];
		
		for (NSUInteger i = srcCount; i < oldCount; i++)
		{
			[newPathComponents addObject:[oldPathComponents objectAtIndex:i]];
		}
		
		return [[YapFilePath alloc] initWithPathComponents:newPathComponents isDirectory:isDirectory];
	}
	
	return nil;
}

/**
 * Returns a new filePath, created by removing the last path component.
 * If the receiver is the root directory, simply returns 'self'.
**/
- (YapFilePath *)filePathByDeletingLastPathComponent
{
	if (self.isRootDirectory) {
		return self;
	}
	
	NSMutableArray *newPathComponents = [pathComponents mutableCopy];
	[newPathComponents removeLastObject];
	
	return [[YapFilePath alloc] initWithPathComponents:newPathComponents isDirectory:YES];
}

/**
 * Returns a new filePath by appending the given pathComponent.
**/
- (YapFilePath *)filePathByAppendingPathComponent:(NSString *)newPathComponent isDirectory:(BOOL)newIsDirectory
{
	if (newPathComponent == nil) {
		return self;
	}
	
	NSArray *newPathComponents = [pathComponents arrayByAddingObject:newPathComponent];
	
	return [[YapFilePath alloc] initWithPathComponents:newPathComponents isDirectory:newIsDirectory];
}

/**
 * Returns a new filePath by appending the given pathExtension to the last component.
 *
 * This will "fail" (return self) if ext is nil, or if the receiver is the root directory.
**/
- (YapFilePath *)filePathByAppendingPathExtension:(NSString *)ext
{
	if (ext == nil) {
		return self;
	}
	
	if (self.isRootDirectory) { // cannot append to root directory ("/")
		return self;
	}
	
	NSMutableArray *newPathComponents = [pathComponents mutableCopy];
	
	NSString *lastPathComponent = [newPathComponents lastObject];
	lastPathComponent = [lastPathComponent stringByAppendingPathExtension:ext];
	
	[newPathComponents replaceObjectAtIndex:(newPathComponents.count - 1) withObject:lastPathComponent];
	
	return [[YapFilePath alloc] initWithPathComponents:newPathComponents isDirectory:isDirectory];
}

@end
