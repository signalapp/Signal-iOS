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
 * You can use your own serializer/deserializer if you need extra features.
**/
+ (YapDatabaseRelationshipFileURLSerializer)defaultFileURLSerializer
{
	return ^NSData* (YapDatabaseRelationshipEdge *edge){ @autoreleasepool {
		
		NSData *data =
		  [edge.destinationFileURL bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile
		                    includingResourceValuesForKeys:nil
		                                     relativeToURL:nil
		                                             error:NULL];
		
		return data;
	}};
}

+ (YapDatabaseRelationshipFileURLDeserializer)defaultFileURLDeserializer
{
	return ^NSURL* (YapDatabaseRelationshipEdge *edge, NSData *data){ @autoreleasepool {
		
		if (data.length == 0) return nil;
		
		NSURL *fileURL =
		  [NSURL URLByResolvingBookmarkData:data
		                            options:NSURLBookmarkResolutionWithoutUI
		                      relativeToURL:nil
		                bookmarkDataIsStale:NULL
		                              error:NULL];
		
		return fileURL;
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
