#import "YapDatabaseRelationshipOptions.h"
#import "YapDatabaseRelationshipPrivate.h"
#import "YapDatabaseLogging.h"

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

static NSString *const kPlistKey_Version        = @"version";
static NSString *const kPlistKey_BookmarkData   = @"bookmarkData";
static NSString *const kPlistKey_PathComponents = @"pathComponents";


@implementation YapDatabaseRelationshipOptions

@synthesize disableYapDatabaseRelationshipNodeProtocol = disableYapDatabaseRelationshipNodeProtocol;
@synthesize allowedCollections = allowedCollections;
@synthesize fileURLSerializer = fileURLSerializer;
@synthesize fileURLDeserializer = fileURLDeserializer;
@synthesize migration = migration;

- (id)init
{
	if ((self = [super init]))
	{
		disableYapDatabaseRelationshipNodeProtocol = NO;
		allowedCollections = nil;
		fileURLSerializer = [[self class] defaultFileURLSerializer];
		fileURLDeserializer = [[self class] defaultFileURLDeserializer];
		migration = [[self class] defaultMigration];
	}
	return self;
}

- (void)setFileURLSerializer:(YapDatabaseRelationshipFileURLSerializer)inSerializer
{
	if (inSerializer)
		fileURLSerializer = inSerializer;
	else
		fileURLSerializer = [[self class] defaultFileURLSerializer];
}

- (void)setFileURLDeserializer:(YapDatabaseRelationshipFileURLDeserializer)inDeserializer
{
	if (inDeserializer)
		fileURLDeserializer = inDeserializer;
	else
		fileURLDeserializer = [[self class] defaultFileURLDeserializer];
}

- (void)setMigration:(YapDatabaseRelationshipMigration)inMigration
{
	if (inMigration)
		migration = inMigration;
	else
		migration = [[self class] defaultMigration];
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseRelationshipOptions *copy = [[YapDatabaseRelationshipOptions alloc] init];
	copy->disableYapDatabaseRelationshipNodeProtocol = disableYapDatabaseRelationshipNodeProtocol;
	copy->allowedCollections = allowedCollections;
	copy->fileURLSerializer = fileURLSerializer;
	copy->fileURLDeserializer = fileURLDeserializer;
	copy->migration = migration;
	
	return copy;
}

/**
 * Apple recommends persisting file locations using bookmarks.
 *
 * From their documentation on the topic: https://goo.gl/0Uqn5J
 *
 *   If you want to save the location of a file persistently, use the bookmark capabilities of NSURL.
 *   A bookmark is an opaque data structure, enclosed in an NSData object, that describes the location of a file.
 *   Whereas path and file reference URLs are potentially fragile between launches of your app,
 *   a bookmark can usually be used to re-create a URL to a file even in cases where the file was moved or renamed.
 *
 * The default serializer will attempt to use the bookmark capabilities of NSURL.
 * If this fails because the file doesn't exist, the serializer will fallback to a hybrid binary plist system.
 * It will look for a parent directory that does exist, generate a bookmark of that,
 * and store the remainder as a relative path.
 *
 * You can use your own serializer/deserializer if you need extra features.
**/
+ (YapDatabaseRelationshipFileURLSerializer)defaultFileURLSerializer
{
	return ^NSData* (YapDatabaseRelationshipEdge *edge){ @autoreleasepool {
		
		NSURL *url = edge.destinationFileURL;
		if (url == nil) return nil;
		
		NSData *bookmarkData = [url bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile
		                     includingResourceValuesForKeys:nil
	                                         relativeToURL:nil
		                                              error:NULL];
		
		if (bookmarkData) {
			return bookmarkData;
		}
		
		// Failed to create bookmark data.
		// This is usually because the file doesn't exist.
		// As a backup plan, we're going to get a bookmark of the closest parent directory that does exist.
		// And combine it with the relative path after that point.
		
		if (!url.isFileURL) {
			return nil;
		}
		
		NSMutableArray *pathComponents = [NSMutableArray arrayWithCapacity:2];
		
		NSString *lastPathComponent = nil;
		NSURL *lastURL = nil;
		NSURL *parentURL = nil;
		
		lastURL = url;
		
		lastPathComponent = [lastURL lastPathComponent];
		if (lastPathComponent)
			[pathComponents addObject:lastPathComponent];
		
		parentURL = [lastURL URLByDeletingLastPathComponent];
		
		while (![parentURL isEqual:lastURL])
		{
			bookmarkData = [parentURL bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile
			                   includingResourceValuesForKeys:nil
			                                    relativeToURL:nil
			                                            error:NULL];
			
			if (bookmarkData) {
				break;
			}
			else
			{
				lastURL = parentURL;
				
				lastPathComponent = [lastURL lastPathComponent];
				if (lastPathComponent)
					[pathComponents insertObject:lastPathComponent atIndex:0];
				
				parentURL = [lastURL URLByDeletingLastPathComponent];
			}
		}
		
		if (bookmarkData)
		{
			NSDictionary *plistDict = @{
			  kPlistKey_Version: @(1),
			  kPlistKey_BookmarkData: bookmarkData,
			  kPlistKey_PathComponents: pathComponents
			};
			
			NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plistDict
			                                                               format:NSPropertyListBinaryFormat_v1_0
			                                                              options:0
			                                                                error:NULL];
			return plistData;
		}
		
		return nil;
	}};
}

+ (YapDatabaseRelationshipFileURLDeserializer)defaultFileURLDeserializer
{
	return ^NSURL* (YapDatabaseRelationshipEdge *edge, NSData *data){ @autoreleasepool {
		
		if (data.length == 0) return nil;
		
		const void *bytes = data.bytes;
		
		BOOL isBookmarkData = NO;
		BOOL isPlistData = NO;
		
		{
			NSData *magic = [@"book" dataUsingEncoding:NSASCIIStringEncoding];
			if (data.length > magic.length)
			{
				isBookmarkData = (memcmp(bytes, magic.bytes, magic.length) == 0);
			}
		}
		
		if (!isBookmarkData)
		{
			NSData *magic = [@"bplist" dataUsingEncoding:NSASCIIStringEncoding];
			if (data.length > magic.length)
			{
				isPlistData = (memcmp(bytes, magic.bytes, magic.length) == 0);
			}
		}
		
		BOOL isUnknown = !isBookmarkData && !isPlistData;
		
		if (isBookmarkData || isUnknown)
		{
			NSURL *url =
			  [NSURL URLByResolvingBookmarkData:data
			                            options:NSURLBookmarkResolutionWithoutUI
			                      relativeToURL:nil
			                bookmarkDataIsStale:NULL
			                              error:NULL];
			
			if (url) {
				return url;
			}
		}
		
		if (isPlistData || isUnknown)
		{
			id plistObj = [NSPropertyListSerialization propertyListWithData:data
			                                                        options:NSPropertyListImmutable
			                                                         format:NULL
			                                                          error:NULL];
			if ([plistObj isKindOfClass:[NSDictionary class]])
			{
				NSDictionary *plistDict = (NSDictionary *)plistObj;
				
				id plistData = plistDict[kPlistKey_BookmarkData];
				id plistComp = plistDict[kPlistKey_PathComponents];

				if ([plistData isKindOfClass:[NSData class]] && [plistComp isKindOfClass:[NSArray class]])
				{
					NSData *bookmarkData = (NSData *)plistData;
					NSArray *pathComponents = (NSArray *)plistComp;
					
					NSURL *url = [NSURL URLByResolvingBookmarkData:bookmarkData
					                                       options:NSURLBookmarkResolutionWithoutUI
					                                 relativeToURL:nil
					                           bookmarkDataIsStale:NULL
					                                         error:NULL];
					if (url)
					{
						NSString *path = [pathComponents componentsJoinedByString:@"/"];
						
						return [[NSURL URLWithString:path relativeToURL:url] absoluteURL];
					}
				}
			}
		}
		
		return nil;
	}};
}

/**
 * For iOS:
 *
 *   An optimistic migration is performed.
 *   This method inspects the filePath to determine what the relative path of the file was originally.
 *   It then uses this relativePath to generate a NSURL based on the current app directory.
 *   If this actually points to an existing file, and the prevoius filePath does not,
 *   then the (previously broken) filePath is automatically replaced by the generated NSURL in the app directory.
 *
 * For Mac OS X - a simplistic migration is performed.
 *
 *   A simplistic migration is performed - simply converts string-based filePath's to NSURL's.
**/
+ (YapDatabaseRelationshipMigration)defaultMigration
{
	return ^NSURL* (NSString *filePath, NSData *data) { @autoreleasepool {
		
		if (filePath)
		{
		#if TARGET_OS_IPHONE
			
			NSArray *pathComponents = [filePath pathComponents];
			
			NSCharacterSet *hexset = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF-"];
			
			__block BOOL found = NO;
			__block NSUInteger lastHexIdx = 0;
			
			[pathComponents enumerateObjectsUsingBlock:^(NSString *pathComponent, NSUInteger idx, BOOL *stop) {
				
				if (pathComponent.length == 36)
				{
					NSRange range = [pathComponent rangeOfCharacterFromSet:hexset];
					if (range.location == 0 && range.length == pathComponent.length)
					{
						found = YES;
						lastHexIdx = idx;
					}
				}
			}];
			
			if (found)
			{
				NSString *migratedPath = NSHomeDirectory();
				for (NSUInteger idx = lastHexIdx; idx < pathComponents.count; idx++)
				{
					migratedPath = [migratedPath stringByAppendingPathComponent:[pathComponents objectAtIndex:idx]];
				}
				
				if ([[NSFileManager defaultManager] fileExistsAtPath:migratedPath])
				{
					if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
					{
						return [NSURL fileURLWithPath:migratedPath];
					}
				}
			}
			
		#endif
			
			return [NSURL fileURLWithPath:filePath];
		}
		
		if (data)
		{
			// If 'data' is non-nil, this means the relationship extension was previously configured
			// with a filePathEncryption block. Meaning that 'data' is an encrypted version of 'filePath' somehow.
			//
			// This default migration cannot decrypt it (obviously).
			
			YDBLogWarn(@"YapDatabaseRelationshipMigration - defaultMigration: Cannot migrate encrypted filePath");
		}
		
		return nil;
	}};
}



@end
