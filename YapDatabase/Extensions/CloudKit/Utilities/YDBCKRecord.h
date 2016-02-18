#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CKRecord (YapDatabaseCloudKit)

/**
 * Returns a "sanitized" copy of the given record.
 * That is, a copy that ONLY includes the "system fields" of the record.
 * It will NOT contain any key/value pairs from the original record.
**/
- (id)sanitizedCopy;

/**
 * There was a bug in early versions of CloudKit:
 *
 * Calling [ckRecord copy] was completely broken.
 * This forced us to use a workaround.
 * 
 * The bug was fixed in iOS 9.
**/
- (id)safeCopy;

@end

#pragma mark -

@interface YDBCKRecord : NSObject <NSCoding>

/**
 * This method serializes just the "system fields" of the given record.
 * That is, it won't store any of the user-created key/value pairs.
 * It only stores the CloudKit specific stuff, such as the versioning info, syncing info, etc.
**/
+ (NSData *)serializeRecord:(CKRecord *)record;

/**
 * Deserialize the given record data.
 *
 * If the record data came from [YDBCKRecord serializeRecord:],
 * then the returned record will only contain the "system fields".
**/
+ (CKRecord *)deserializeRecord:(NSData *)data;

#pragma mark Instance

- (instancetype)initWithRecord:(CKRecord *)record;

@property (nonatomic, strong, readonly) CKRecord *record;

@end

NS_ASSUME_NONNULL_END
