#import <Foundation/Foundation.h>

#import "YapFilePath.h"

/**
 * The YapFileTree class makes it efficient to see if a single YapFilePath is contained within a set of YapFilePaths.
 * 
 * For example, consider the following set of file paths:
 * - /foo/
 * - /bar/
 * - /animals/duck/
 *
 * Now what if you wanted to know if the following was contained in any of the above directories:
 * - /foo/man/chu
 * - /i/like/cheese
 * - /animals/duck/quack
 * - /animals/bird/sparrow
**/
@interface YapFileTree : NSObject

- (instancetype)init;

/**
 * Adds a filePath to the set contained by the tree.
 * 
 * The given filePath can represent a file or directory.
**/
- (void)addFilePath:(YapFilePath *)filePath;

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
- (BOOL)containsFilePath:(YapFilePath *)path;

@end
