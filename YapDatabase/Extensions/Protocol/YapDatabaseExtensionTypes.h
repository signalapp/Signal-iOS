#import <Foundation/Foundation.h>

/**
 * Corresponds to the different type of blocks supported by the various extension subclasses.
**/
typedef NS_ENUM(NSInteger, YapDatabaseBlockType) {
	YapDatabaseBlockTypeWithKey,
	YapDatabaseBlockTypeWithObject,
	YapDatabaseBlockTypeWithMetadata,
	YapDatabaseBlockTypeWithRow
};

/**
 * Advanced options concerning exactly when to invoke the block.
**/
typedef NS_OPTIONS(NSUInteger, YapDatabaseBlockInvoke) {
	
	// Only invoke the block when the row is inserted (or when the extension is initialized)
	YapDatabaseBlockInvokeOnInsertOnly       = 0,
	
	// Invoke the block whenever the object appears to have been modified
	//
	// Corresponds to:
	// - setObject:forKey:inCollection:withMetadata:
	// - replaceObject:forKey:inCollection:
	YapDatabaseBlockInvokeIfObjectModified   = 1 << 0, // 00001
	
	// Invoke the block whenever the metadata appears to have been modified
	//
	// Corresponds to:
	// - setObject:forKey:inCollection:withMetadata:
	// - replaceMetadata:forKey:inCollection:
	YapDatabaseBlockInvokeIfMetadataModified = 1 << 1, // 00010
	
	// Invoke the block whenever the object is manually "touched"
	//
	// Corresponds to:
	// - touchObjectForKey:inCollection:
	// - touchRowForKey:inCollection:
	YapDatabaseBlockInvokeIfObjectTouched    = 1 << 2, // 00100
	
	// Invoke the block whenever the metadata is manually "touched"
	//
	// Corresponds to:
	// - touchMetadataForKey:inCollection:
	// - touchRowForKey:inCollection:
	YapDatabaseBlockInvokeIfMetadataTouched  = 1 << 3, // 01000
	
	// All of the above options
	YapDatabaseBlockInvokeAny                = YapDatabaseBlockInvokeIfObjectModified   |
	                                           YapDatabaseBlockInvokeIfMetadataModified |
	                                           YapDatabaseBlockInvokeIfObjectTouched    |
	                                           YapDatabaseBlockInvokeIfMetadataTouched,
	
	// The default options for YapDatabaseBlockTypeWithKey
	YapDatabaseBlockInvokeDefaultForBlockTypeWithKey      = YapDatabaseBlockInvokeOnInsertOnly,
	
	// The default options for YapDatabaseBlockTypeWithObject
	YapDatabaseBlockInvokeDefaultForBlockTypeWithObject   = YapDatabaseBlockInvokeIfObjectModified |
	                                                        YapDatabaseBlockInvokeIfObjectTouched,
	
	// The default options for YapDatabaseBlockTypeWithMetadata
	YapDatabaseBlockInvokeDefaultForBlockTypeWithMetadata = YapDatabaseBlockInvokeIfMetadataModified |
	                                                        YapDatabaseBlockInvokeIfMetadataTouched,
	
	// The default options for YapDatabaseBlockTypeWithRow
	YapDatabaseBlockInvokeDefaultForBlockTypeWithRow      = YapDatabaseBlockInvokeAny,
};
