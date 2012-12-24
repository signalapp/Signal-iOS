#import <Foundation/Foundation.h>
#import "YapDatabaseTransaction.h"
#import "YapDatabaseOrder.h"

/**
 * The implementation of this protocol will wrap YapDatabaseReadTransaction.
 * So you'll have access to all the methods in YapDatabaseReadTransaction.
**/
@protocol YapOrderedReadTransaction <NSObject>

/**
 * Returns a list of keys, either all of them, or within a given range.
 * The lists are given in order.
**/
- (NSArray *)allKeys;
- (NSArray *)keysInRange:(NSRange)range;

/**
 * Returns the key/object/metadata at the given index.
**/
- (NSString *)keyAtIndex:(NSUInteger)index;
- (id)objectAtIndex:(NSUInteger)index;
- (id)metadataAtIndex:(NSUInteger)index;

/**
 * Extremely fast in-memory enumeration over keys (in their set order) and associated metadata in the database.
 * You can enumerate all key/metadata pairs, or only a given range.
 * 
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
**/
- (void)enumerateKeysAndMetadataOrderedUsingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndMetadataOrderedWithOptions:(NSEnumerationOptions)options
                                        usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndMetadataOrderedInRange:(NSRange)range
                                  withOptions:(NSEnumerationOptions)options
                                   usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block;

/**
 * Allows you to enumerate the objects in their set order.
 * You can enumerate all key/object pairs, or only a given range.
 * 
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
 * 
 * Note: If order does NOT matter, you can get a performance increase by using the
 * non-ordered enumeration methods in the superclass (YapDatabase).
**/
- (void)enumerateKeysAndObjectsOrderedUsingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndObjectsOrderedWithOptions:(NSEnumerationOptions)options
                                       usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndObjectsOrderedInRange:(NSRange)range
                                  withOptions:(NSEnumerationOptions)options
                                   usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Implementations of this protocol will wrap YapDatabaseReadWriteTransaction.
 * So you'll have access to all the methods in YapDatabaseReadWriteTransaction, with the exception of the following:
 * 
 * - setObject:forKey:
 * - setObject:forKey:withMetadata:
 * 
 * Invoking these methods will throw a MethodNotAvailable exception as they don't provide ordering information.
 * These methods have been replaced with:
 * 
 * - appendObject:forKey:withMetadata:
 * - prependObject:forKey:withMetadata:
 * - insertObject:atIndex:forKey:withMetadata:
 * - updateObject:forKey:withMetadata:
**/
@protocol YapOrderedReadWriteTransaction <YapOrderedReadTransaction>

/**
 * These methods replace setObject:forKey:, and allow you to specify ordering information.
 * 
 * Append  - adds the object to the end of the list.
 * Prepend - adds the object to the beginning of the list.
 * Insert  - adds the object at the given index of the list.
 * Update  - updates in-place the object. If given key doesn't already exist, does nothing.
**/
- (void)appendObject:(id)object forKey:(NSString *)key;
- (void)appendObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata;

- (void)prependObject:(id)object forKey:(NSString *)key;
- (void)prependObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata;

- (void)insertObject:(id)object atIndex:(NSUInteger)index forKey:(NSString *)key;
- (void)insertObject:(id)object atIndex:(NSUInteger)index forKey:(NSString *)key withMetadata:(id)metadata;

- (void)updateObject:(id)object forKey:(NSString *)key;
- (void)updateObject:(id)object forKey:(NSString *)key withMetadata:(id)metadata;

/**
 * Allows you to remove objects with ordering information (using indexes).
**/
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeObjectsInRange:(NSRange)range;

@end
