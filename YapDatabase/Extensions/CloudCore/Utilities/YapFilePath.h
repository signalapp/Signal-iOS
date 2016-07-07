#import <Foundation/Foundation.h>

/**
 * The YapFilePath class encapsulates the logic for managing remote file paths.
 * That is, the file path of items on the cloud server.
 * 
 * This includes the following functionality:
 *
 * - Enforces file naming rules, according to cloud server's allowed character set.
 * - Takes case-sensitiving into account during comparisons, according to cloud server's filesystem.
 *
 * You may wish to override this class to correspond to your particular cloud server.
**/
@interface YapFilePath : NSObject <NSCopying, NSCoding> {
@protected
	
	NSArray<NSString *> *pathComponents;
	BOOL isDirectory;
}

- (instancetype)initWithPathComponents:(NSArray<NSString *> *)pathComponents isDirectory:(BOOL)isDirectory;

- (instancetype)initWithPath:(NSString *)path isDirectory:(BOOL)isDirectory;

- (instancetype)initWithURL:(NSURL *)url isDirectory:(BOOL)isDirectory;


#pragma mark Primitives

@property (nonatomic, readonly) NSArray<NSString *> *pathComponents;
@property (nonatomic, readonly) BOOL isDirectory;

@property (nonatomic, readonly) BOOL isRootDirectory;
@property (nonatomic, readonly) BOOL isCaseSensitive;

#pragma mark String Conversion

/**
 * Returns the path, separated by by '/' characters.
 * If the filePath represents a directory, the path will end with a '/' character.
**/
@property (nonatomic, readonly) NSString *path;


#pragma mark Comparison

- (NSUInteger)hash;         // returns a hash of the path (converted to lowercase if case-insensitive)
- (BOOL)isEqual:(id)object; // invokes isEqualToFilePath if object is a YapFilePath

/**
 * Returns YES if both filePath's have matching pathComponents & isDirectory properties.
 * 
 * (Case-sensitivity of the cloud server's filesystem is properly taking into account when comparing fileNames.)
**/
- (BOOL)isEqualToFilePath:(YapFilePath *)another;

/**
 * Returns YES if 'self' is a directory, and 'another' is a file or directory within 'self', at any depth.
 * 
 * For example, if 'self' is "/foo" :
 * 
 * - "/foo"         -> NO  (but isEqualToFilePath: would return YES)
 * - "/foo/bar"     -> YES
 * - "/foo/man/chu" -> YES
 * - "/Foo/bar"     -> YES (if cloud server is case-insensitive, otherwise NO)
 * - "/buzz"        -> NO
**/
- (BOOL)containsFilePath:(YapFilePath *)another;

/**
 * A shortcut for invoking: [fp isEqualToFilePath:another] || [fp containsFilePath:another]
 * 
 * (This method is more efficient than invoking both methods.)
**/
- (BOOL)isEqualOrContainsFilePath:(YapFilePath *)another;


#pragma mark Derivatives

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
- (YapFilePath *)filePathByMovingFrom:(YapFilePath *)src to:(YapFilePath *)dst;

/**
 * Returns a new filePath, created by removing the last path component.
 * If the receiver is the root directory, simply returns 'self'.
**/
- (YapFilePath *)filePathByDeletingLastPathComponent;

/**
 * Returns a new filePath by appending the given pathComponent.
**/
- (YapFilePath *)filePathByAppendingPathComponent:(NSString *)pathComponent isDirectory:(BOOL)isDirectory;

/**
 * Returns a new filePath by appending the given pathExtension to the last component.
 * 
 * This will "fail" (return [self copy]) if ext is nil, or if the receiver is the root directory.
**/
- (YapFilePath *)filePathByAppendingPathExtension:(NSString *)ext;

@end
