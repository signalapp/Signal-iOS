#import <Foundation/Foundation.h>

@class Future;
@class FutureSource;
@protocol Terminable;

/**
 *
 * CancelToken is used to cancel registered operations and terminate registered objects.
 *
 * A cancellable method should take a cancel token as an argument.
 * The method may initially check isAlreadyCancelled to see if it can quickly finish.
 * The method should use whenCancelled to register a callback to be run when the token is cancelled.
 * When the callback runs, the method should release all resources and stop any dependent operations.
 * If the method has a result of type Future, cancelling should transition the Future from incomplete to failed (with the cancel token as a value).
 *
 * A cancellable object works the same way: take a cancel token in the constructor, register for termination.
 *
 * Idioms:
 *   unlessCancelled:cancelToken  //operation will complete normally unless the token is cancelled BEFORE completion
 *    untilCancelled:cancelToken  //object or effect will last until the token is cancelled
 *
 */

@protocol CancelToken <NSObject>

-(void) whenCancelled:(void(^)())callback;
-(void) whenCancelledTryCancel:(FutureSource*)futureSource;
-(void) whenCancelledTerminate:(id<Terminable>)terminable;
-(bool) isAlreadyCancelled;
-(Future*) asCancelledFuture;

@end
