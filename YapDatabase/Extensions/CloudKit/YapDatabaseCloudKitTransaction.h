#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionTransaction.h"

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseCloudKitTransaction : YapDatabaseExtensionTransaction

/**
 * If the given recordID & databaseIdentifier are associated with a row in the database,
 * then this method will return YES, and set the collectionPtr/keyPtr with the collection/key of the associated row.
 * 
 * @param keyPtr (optional)
 *   If non-null, and this method returns YES, then the keyPtr will be set to the associated row's key.
 * 
 * @param collectionPtr (optional)
 *   If non-null, and this method returns YES, then the collectionPtr will be set to the associated row's collection.
 * 
 * @param recordID
 *   The CKRecordID to look for.
 * 
 * @param databaseIdentifier
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseIdentifierBlock.
 * 
 * @return
 *   YES if the given recordID & databaseIdentifier are associated with a row in the database.
 *   NO otherwise.
 * 
 *
 * Note:
 *   It's possible to associate multiple items in the database with a single CKRecord/databaseIdentifier.
 *   This is completely legal, and supported by YapDatabaseCloudKit extension.
 *   However, if you do this keep in mind that this method will only return 1 of the associated items.
 *   Further, which item it returns is not guaranteed, and may change between method invocations.
 *   So, in this particular case, you likely should be using 'collectionKeysForRecordID:databaseIdentifier:'.
**/
- (BOOL)getKey:(NSString * _Nonnull * _Nullable)keyPtr collection:(NSString * _Nonnull * _Nullable)collectionPtr
                                                      forRecordID:(CKRecordID *)recordID
                                               databaseIdentifier:(nullable NSString *)databaseIdentifier;

/**
 * It's possible to associate multiple items in the database with a single CKRecord/databaseIdentifier.
 * This is completely legal, and supported by YapDatabaseCloudKit extension.
 * 
 * This method returns an array of YapCollectionKey objects,
 * each associated with the given recordID/databaseIdentifier.
 * 
 * @see YapCollectionKey
**/
- (NSArray<YapCollectionKey *> *)collectionKeysForRecordID:(CKRecordID *)recordID
                                        databaseIdentifier:(nullable NSString *)databaseIdentifier;

/**
 * If the given key/collection tuple is associated with a record,
 * then this method returns YES, and sets the recordIDPtr & databaseIdentifierPtr accordingly.
 * 
 * @param recordIDPtr (optional)
 *   If non-null, and this method returns YES, then the recordIDPtr will be set to the associated recordID.
 * 
 * @param databaseIdentifierPtr (optional)
 *   If non-null, and this method returns YES, then the databaseIdentifierPtr will be set to the associated value.
 *   Keep in mind that nil is a valid databaseIdentifier,
 *   and is generally used to signify the defaultContainer/privateCloudDatabase.
 *
 * @param key
 *   The key of the row in the database.
 * 
 * @param collection
 *   The collection of the row in the database.
 * 
 * @return
 *   YES if the given collection/key is associated with a CKRecord.
 *   NO otherwise.
**/
- (BOOL)getRecordID:(CKRecordID * _Nonnull * _Nullable)recordIDPtr
 databaseIdentifier:(NSString * _Nonnull * _Nullable)databaseIdentifierPtr
             forKey:(NSString *)key
       inCollection:(nullable NSString *)collection;

/**
 * Returns a copy of the CKRcord for the given recordID/databaseIdentifier.
 * 
 * Keep in mind that YapDatabaseCloudKit stores ONLY the system fields of a CKRecord.
 * That is, it does NOT store any key/value pairs.
 * It only stores "system fields", which is the internal metadata that CloudKit uses to handle sync state.
 * 
 * So if you invoke this method from within a read-only transaction,
 * then you will receive a "base" CKRecord, which is really only useful for extracting "system field" metadata,
 * such as the 'recordChangeTag'.
 * 
 * If you invoke this method from within a read-write transaction,
 * then you will receive the "base" CKRecord, along with any modifications that have been made to the CKRecord
 * during the current read-write transaction.
 * 
 * Also keep in mind that you are receiving a copy of the record which YapDatabaseCloudKit is using internally.
 * If you intend to manually modify the CKRecord directly,
 * then you need to save those changes back into YapDatabaseCloudKit via 'saveRecord:databaseIdentifier'.
 * 
 * @see saveRecord:databaseIdentifier:
**/
- (CKRecord *)recordForRecordID:(CKRecordID *)recordID databaseIdentifier:(nullable NSString *)databaseIdentifier;

/**
 * Convenience method.
 * Combines the following two methods into a single call:
 * 
 * - getRecordID:databaseIdentifier:forKey:inCollection:
 * - recordForRecordID:databaseIdentifier:
 * 
 * @see recordForRecordID:databaseIdentifier:
**/
- (CKRecord *)recordForKey:(NSString *)key inCollection:(nullable NSString *)collection;

/**
 * High performance lookup method, if you only need to know if YapDatabaseCloudKit has a
 * record for the given recordID/databaseIdentifier.
 *
 * This method is much faster than invoking recordForRecordID:databaseIdentifier:,
 * if you don't actually need the record.
 * 
 * @return
 *   Whether or not YapDatabaseCloudKit is currently managing a record for the given recordID/databaseIdentifer.
 *   That is, whether or not there is currently one or more rows in the database attached to the CKRecord.
**/
- (BOOL)containsRecordID:(CKRecordID *)recordID databaseIdentifier:(nullable NSString *)databaseIdentifier;

/**
 * Use this method during CKFetchRecordChangesOperation.fetchRecordChangesCompletionBlock.
 * The values returned by this method will help you determine how to process each reported changedRecord.
 *
 * @param outRecordChangeTag
 *   If YapDatabaseRecord is managing a record for the given recordID/databaseIdentifier,
 *   this this will be set to the local record.recordChangeTag value.
 *   Remember that CloudKit tells us about changes that we made.
 *   It doesn't do so via push notification, but it still does when we use a CKFetchRecordChangesOperation.
 *   Thus its advantageous for us to ignore our own changes.
 *   This can be done by comparing the changedRecord.recordChangeTag vs outRecordChangeTag.
 *   If they're the same, then we already have this CKRecord (this change) in our system, and we can ignore it.
 *   
 *   Note: Sometimes during development, we may screw up some merge operations.
 *   This may happen when we're changing our data model(s) and record.
 *   If this happens, you can ignore the recordChangeTag,
 *   and force another merge by invoking mergeRecord:databaseIdentifier: again.
 * 
 * @param outPendingModifications
 *   Tells you if there are changes in the queue for the given recordID/databaseIdentifier.
 *   That is, whether or not this record has been modified, and we have modifications that are still
 *   pending upload to the CloudKit servers.
 *   If this value is YES, then you MUST invoke mergeRecord:databaseIdentifier:.
 *   
 *   Note: It's possible for this value to be YES, and for outRecordChangeTag to be nil.
 *   This may happen if the user modified a record, deleted it, and neither of these changes have hit the server yet.
 *   Thus YDBCK no longer actively manages the record, but it does have changes for it sitting in the queue.
 *   Failure to observe this value could result in an infinite loop:
 *   attempt upload, partial error, fetch changes, failure to invoke merge properly, attempt upload, partial error...
 *
 * @param outPendingDelete
 *   Tells you if there is a pending delete of the record in the queue.
 *   That is, if we deleted the item locally, and the delete operation is pending upload to the cloudKit server.
 *   If this value is YES, then you may not want to create a new database item for the record.
**/
- (void)getRecordChangeTag:(NSString * _Nullable * _Nullable)outRecordChangeTag
   hasPendingModifications:(nullable BOOL *)outPendingModifications
          hasPendingDelete:(nullable BOOL *)outPendingDelete
               forRecordID:(CKRecordID *)recordID
        databaseIdentifier:(nullable NSString *)databaseIdentifier;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudKitTransaction (ReadWrite)

/**
 * This method is used to associate an existing CKRecord with a row in the database.
 * There are two primary use cases for this method.
 * 
 * 1. To associate a discovered/pulled CKRecord with a row in the database before you insert the row.
 *    In particular, for the following situation:
 *    
 *    - You're pulling record changes from the server via CKFetchRecordChangesOperation (or similar).
 *    - You discover a record that was inserted by another device.
 *    - You need to add a corresponding row to the database,
 *      but you also need to inform the YapDatabaseCloudKit extension about the existing record,
 *      so it won't bother invoking the recordHandler, or attempting to upload the existing record.
 *    - So you invoke this method FIRST.
 *    - And THEN you insert the corresponding object into the database via the
 *      normal setObject:forKey:inCollection: method (or similar methods).
 *
 * 2. To assist in the migration process when switching to YapDatabaseCloudKit.
 *    In particular, for the following situation:
 *
 *    - You've been handling CloudKit manually (not via YapDatabaseCloudKit).
 *    - And you now want YapDatabaseCloudKit to manage the CKRecord for you.
 *    - So you can invoke this method for an object that already exists in the database,
 *      OR you can invoke this method FIRST, and then insert the new object that you want linked to the record.
 * 
 * Thus, this method works as a simple "hand-off" of the CKRecord to the YapDatabaseCloudKit extension.
 *
 * In other words, YapDatbaseCloudKit will write the system fields of the given CKRecord to its internal table,
 * and associate it with the given collection/key tuple.
 * 
 * @param record
 *   The CKRecord to associate with the collection/key tuple.
 * 
 * @param databaseIdentifier
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseIdentifierBlock.
 *
 * @param key
 *   The key of the row to associate the record with.
 * 
 * @param collection
 *   The collection of the row to associate the record with.
 * 
 * @param shouldUploadRecord
 *   If NO, then the record is simply associated with the collection/key,
 *     and YapDatabaseCloudKit doesn't attempt to push the record to the cloud.
 *   If YES, then the record is associated with the collection/key,
 *     and YapDatabaseCloutKit assumes the given record is dirty and will push the record to the cloud.
 * 
 * @return
 *   YES if the record was associated with the given collection/key.
 *   NO if one of the following errors occurred.
 * 
 * The following errors will prevent this method from succeeding:
 * - The given record is nil.
 * - The given collection/key is already associated with a different record (so must detach it first).
 * 
 * Important: This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
**/
- (BOOL)attachRecord:(CKRecord *)record
  databaseIdentifier:(nullable NSString *)databaseIdentifier
              forKey:(NSString *)key
        inCollection:(nullable NSString *)collection
  shouldUploadRecord:(BOOL)shouldUploadRecord;

/**
 * This method is used to unassociate an existing CKRecord with a row in the database.
 * There are three primary use cases for this method.
 * 
 * 1. To properly handle CKRecordID's that are reported as deleted from the server.
 *    In particular, for the following situation:
 *
 *    - You're pulling record changes from the server via CKFetchRecordChangesOperation (or similar).
 *    - You discover a recordID that was deleted by another device.
 *    - You need to remove the associated record from the database,
 *      but you also need to inform the YapDatabaseCloudKit extension that it was remotely deleted,
 *      so it won't bother attempting to upload the already deleted recordID.
 *    - So you invoke this method FIRST.
 *    - And THEN you can remove the corresponding object from the database via the
 *      normal removeObjectForKey:inCollection: method (or similar methods) (if needed).
 *
 * 2. To assist in various migrations, such as version migrations.
 *    For example:
 * 
 *    - In version 2 of your app, you need to move a few CKRecords into a new zone.
 *    - But you don't want to delete the items from the old zone,
 *      because you need to continue supporting v1.X for awhile.
 *    - So you invoke this method first in order to drop the previous record association(s).
 *    - And then you can attach the new CKRecord(s),
 *      and have YapDatabaseCloudKit upload the new records (to their new zone).
 * 
 * 3. To "move" an object from the cloud to "local-only".
 *    For example:
 * 
 *    - You're making a Notes app that allows user to stores notes locally, or in the cloud.
 *    - The user moves an existing note from the cloud, to local-only storage.
 *    - This method can be used to delete the item from the cloud without deleting it locally.
 * 
 * @param key
 *   The key of the row associated with the record to detach.
 *   
 * @param collection
 *   The collection of the row associated with the record to detach.
 * 
 * @param wasRemoteDeletion
 *   Did the server notify you of a deleted CKRecordID? 
 *   Then make sure you set this parameter to YES.
 *   This allows the extension to properly modify any changeSets that are still queued for upload
 *   so that it can remove potential modifications for this recordID.
 * 
 *   Note: If a record was deleted remotely, and the record was associated with MULTIPLE items in the database,
 *   then you should be sure to invoke this method for each attached collection/key.
 * 
 * @param shouldUploadDeletion
 *   Whether or not the extension should push a deleted CKRecordID to the cloud.
 *   In use case #2 (from the above discussion, concerning migration), you'd pass NO.
 *   In use case #3 (from the above discussion, concerning moving), you'd pass YES.
 *   This parameter is ignored if wasRemoteDeletion is YES (in which it will force shouldUpload to be NO).
 * 
 * Important: This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
 * 
 * @see getKey:collection:forRecordID:databaseIdentifier:
**/
- (void)detachRecordForKey:(NSString *)key
              inCollection:(nullable NSString *)collection
         wasRemoteDeletion:(BOOL)wasRemoteDeletion
      shouldUploadDeletion:(BOOL)shouldUploadDeletion;

/**
 * This method is used to merge a pulled record from the server with what's in the database.
 * In particular, for the following situation:
 *
 * - You're pulling record changes from the server via CKFetchRecordChangesOperation (or similar).
 * - You discover a record that was modified by another device.
 * - You need to properly merge the changes with your own version of the object in the database,
 *   and you also need to inform YapDatabaseCloud extension about the merger
 *   so it can properly handle any changes that were pending a push to the cloud.
 * 
 * Thus, you should use this method, which will invoke your mergeBlock with the appropriate parameters.
 * 
 * @param remoteRecord
 *   A record that was modified remotely, and discovered via CKFetchRecordChangesOperation (or similar).
 *   This value will be passed as the remoteRecord parameter to the mergeBlock.
 * 
 * @param databaseIdentifer
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseIdentifierBlock.
 * 
 * Important: This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
**/
- (void)mergeRecord:(CKRecord *)remoteRecord databaseIdentifier:(nullable NSString *)databaseIdentifer;

/**
 * This method allows you to manually modify a CKRecord.
 * 
 * This is useful for tasks such as migrations, debugging, and various one-off tasks during the development lifecycle.
 * For example, you added a property to some on of your model classes in the database,
 * but you forgot to add the code that creates the corresponding property in the CKRecord.
 * So you might whip up some code that uses this method, and forces that property to get uploaded to the server
 * for all the corresponding model objects that you already updated.
 * 
 * Returns NO if the given recordID/databaseIdentifier is unknown.
 * That is, such a record has not been given to YapDatabaseCloudKit (via the recordHandler),
 * or has not previously been associated with a collection/key,
 * or the record was deleted earlier in this transaction.
 *
 * Important: This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
**/
- (BOOL)saveRecord:(CKRecord *)record databaseIdentifier:(nullable NSString *)databaseIdentifier;

@end

NS_ASSUME_NONNULL_END
