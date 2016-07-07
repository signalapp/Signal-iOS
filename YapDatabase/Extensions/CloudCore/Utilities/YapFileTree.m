#import "YapFileTree.h"


@interface YapFileTreeNode : NSObject {
@public
	
	NSMutableDictionary<NSString *, YapFileTreeNode *> *branches;
	
	NSMutableSet<NSString *> *leaves_files;
	NSMutableSet<NSString *> *leaves_dirs;
}

@end

@implementation YapFileTreeNode

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapFileTree
{
	YapFileTreeNode *root;
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		root = [[YapFileTreeNode alloc] init];
	}
	return self;
}

/**
 * Adds a filePath to the set contained by the tree.
 *
 * The given filePath can represent a file or directory.
**/
- (void)addFilePath:(YapFilePath *)filePath
{
	if (filePath == nil) return;
	
	NSArray<NSString *> *pathComponents = filePath.pathComponents;
	NSUInteger count = pathComponents.count;
	
	YapFileTreeNode *node = root;
	
	NSUInteger idx = 0;
	for (NSString *pathComponent in pathComponents)
	{
		NSString *pathKey = filePath.isCaseSensitive ? pathComponent : [pathComponent lowercaseString];
		
		BOOL isLastComponent = ((idx+1) == count);
		if (isLastComponent)
		{
			if (filePath.isDirectory)
			{
				if (node->leaves_dirs == nil)
					node->leaves_dirs = [[NSMutableSet alloc] initWithCapacity:1];
				
				[node->leaves_dirs addObject:pathKey];
			}
			else
			{
				if (node->leaves_files == nil)
					node->leaves_files = [[NSMutableSet alloc] initWithCapacity:1];
				
				[node->leaves_files addObject:pathKey];
			}
		}
		else
		{
			if (node->branches == nil)
				node->branches = [[NSMutableDictionary alloc] initWithCapacity:2];
			
			YapFileTreeNode *nextNode = node->branches[pathKey];
			
			if (nextNode == nil)
			{
				nextNode = [[YapFileTreeNode alloc] init];
				node->branches[pathKey] = nextNode;
			}
			
			node = nextNode;
		}
		
		idx++;
	}
}

/**
 * A tree is said to contain a given file if ANY of the added filePaths:
 * - is a directory, and that directory contains the given filePath (at any depth)
 * - is a directory, and that directory equals the given filePath
 * - is a file, and that file equals the given filePath
 *
 * For example, if the following filePaths have been added:
 * - /foo/
 * - /bar/
 * - /animals/duck/
 *
 * And you invoked this method with the given filePaths:
 * - /foo/                 -> YES, equal to /foo/
 * - /foo/man/chu          -> YES, contained by /foo/
 * - /i/like/cheese        -> NO
 * - /animals/duck/qu/ack  -> YES, contained by /animals/duck/
 * - /animals/bird/sparrow -> NO
**/
- (BOOL)containsFilePath:(YapFilePath *)filePath
{
	if (filePath == nil) return NO;
	
	NSArray<NSString *> *pathComponents = filePath.pathComponents;
	NSUInteger count = pathComponents.count;
	
	YapFileTreeNode *node = root;
	
	NSUInteger idx = 0;
	for (NSString *pathComponent in pathComponents)
	{
		NSString *pathKey = filePath.isCaseSensitive ? pathComponent : [pathComponent lowercaseString];
		
		BOOL isLastComponent = ((idx+1) == count);
		if (isLastComponent)
		{
			if (filePath.isDirectory)
			{
				if ([node->leaves_dirs containsObject:pathKey])
					return YES;
			}
			else
			{
				if ([node->leaves_files containsObject:pathKey])
					return YES;
			}
		}
		else
		{
			if ([node->leaves_dirs containsObject:pathKey])
				return YES;
			
			node = node->branches[pathKey];
			
			if (node == nil) break;
		}
		
		idx++;
	}
	
	return NO;
}

@end
