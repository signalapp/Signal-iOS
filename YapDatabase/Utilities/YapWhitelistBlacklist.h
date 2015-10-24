#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^YapWhitelistBlacklistFilterBlock)(id item);

/**
 * This class provides a standardized way to create a sort of whitelist / blacklist.
 * It is used often within the options of extensions to create the set of allowedCollections.
**/
@interface YapWhitelistBlacklist : NSObject

/**
 * Creates a whitelist based instance.
 *
 * Only items in the whitelist are allowed.
 * Any items not in the whitelist are disallowed.
**/
- (instancetype)initWithWhitelist:(nullable NSSet *)whitelist;

/**
 * Creates a blacklist based instance.
 * 
 * Only items in the blacklist are disallowed.
 * Any items not in the blacklist are allowed.
**/
- (instancetype)initWithBlacklist:(nullable NSSet *)blacklist;

/**
 * Creates a filterBlock based instance.
 * 
 * Rather than a known whitelist/blacklist, the filterBlock makes it possible to use app-specific criteria.
 * For example, using prefix matching, regular expressions, etc.
 * 
 * When creating your block, you must keep in mind 2 things:
 * 
 * 1.) YapDatabase extensions may invoke the filterBlock from background threads durind readWriteTransactions.
 *     Thus your filterBlock MUST be thread-safe.
 * 
 * 2.) The filterBlock is expected to be IMMUTABLE.
 *     That is, if the fitlerBlock is invoked with item X, and the filterBlock returns YES,
 *     then the filterBlock must always return YES for X.
 *     It should not "change its mind" about X.
 * 
 * If the filterBlock returns YES for a given item, that item is allowed.
 * If the filterBlock returns  NO for a given item, that item is disallowed.
**/
- (instancetype)initWithFilterBlock:(nullable YapWhitelistBlacklistFilterBlock)block;

/**
 * Inspects the whitelist or blacklist, or consults the filterBlock (depending on initialization),
 * and returns whether or not the item is allowed.
**/
- (BOOL)isAllowed:(id)item;

@end

NS_ASSUME_NONNULL_END
