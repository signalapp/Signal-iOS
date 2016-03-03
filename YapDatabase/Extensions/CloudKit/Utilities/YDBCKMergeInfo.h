#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * This utility class is used by the YapDatabaseCloudKitMergeBlock.
**/
@interface YDBCKMergeInfo : NSObject

/**
 * Apple's CloudKit framework does NOT tell us which properties of a CKRecord were remotely changed.
 * That is, when we fetch CKRecords that have been changed by a different device, we are only given:
 *
 * - The CKRecord that was changed
 * - The most recent key/value pairs for the CKRecord (all key value pairs, even those that didn't change)
 * 
 * This becomes problematic when we are tasked with performing a merge.
 * For example:
 * 
 * - We change contact.firstName property
 * - We attempt to upload the corresponding CKRecord
 * - CloudKit gives us an error - record is out-of-date (changed remotely)
 * - We then pull down the latest version of the CKRecord
 * - And we are now tasked with merging this version with our version
 * 
 * The big question is: Did the remote device change the firstName property ???
 *
 * Unfortunately, this is not possible to answer this question with only the following information:
 * - The latest version of the CKRecord from the server
 * - The latest version of the CKRecord locally (pending upload)
 * - The list of properties that were changed locally (pending upload)
 * 
 * There is one critical piece of information that is missing:
 * - The original values for the properties that were changed locally
 * 
 * With this critical piece of information in hand, we can:
 * - Enumerate the key/value pairs of the CKRecord from the server
 * - Compare each value with our own local value
 * - If they match, then we don't have any problems
 * - If they don't match, and we didn't change the value locally, then we can simply accept the new value from remote
 * - If they don't match, and we did change the value locally:
 *   - If the remote value matches our original value,
 *     then the remote device didn't change the value, and we can keep our local change.
 *   - If the remote value doesn't match our original value,
 *     then we have a conflict, and we'll need to choose which value to keep. (generally remote wins)
 * 
 * So how do we go about storing the originalValues ?
 * YapDatabaseCloudKit will store it for you if you provide the info via the recordBlock.
 * That is, the recordBlock has a YDBCKRecordInfo parameter.
 * And YDBCKRecordInfo has an originalValues property that you can set.
 * If you set this, then YapDatabaseCloudKit will handle everything else for you.
 * 
 * See MyDatabaseObject for an example of how you might use KVO to track originalValue(s).
 * See CloudKitTodo sample project for a complete Xcode project example.
**/
@property (nonatomic, strong, readonly) NSDictionary<NSString *, id> *originalValues;

/**
 *
**/
@property (nonatomic, strong, readonly, nullable) CKRecord *pendingLocalRecord;

/**
 *
**/
@property (nonatomic, strong, readonly) CKRecord *updatedPendingLocalRecord;

@end

NS_ASSUME_NONNULL_END
