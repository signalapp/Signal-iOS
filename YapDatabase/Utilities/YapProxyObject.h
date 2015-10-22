#import <Foundation/Foundation.h>

/**
 * YapProxyObject acts as a proxy for a real object in order to lazily load the object on demand.
 * 
 * Generally, a YapProxyObject will be passed via a block parameter.
 * The underlying object that the proxy represents may or may not be loaded in memory.
 * If not, the proxy is configured to automatically load the underlying object
 * (using the current transaction) on demand.
**/
@interface YapProxyObject : NSProxy
NS_ASSUME_NONNULL_BEGIN

- (instancetype)init;

@property (nonatomic, readonly) BOOL isRealObjectLoaded;

@property (nonatomic, readonly) id realObject;

NS_ASSUME_NONNULL_END
@end
