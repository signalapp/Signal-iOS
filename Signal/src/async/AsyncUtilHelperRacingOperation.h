#import <Foundation/Foundation.h>
#import "Future.h"
#import "CancelTokenSource.h"
#import "AsyncUtil.h"

@interface AsyncUtilHelperRacingOperation : NSObject

@property (readonly,nonatomic) Future* futureResult;
@property (readonly,nonatomic) CancelTokenSource* cancelSource;

+(AsyncUtilHelperRacingOperation*) racingOperationFromCancellableOperationStarter:(CancellableOperationStarter)cancellableOperationStarter
                                                                   untilCancelled:(id<CancelToken>)untilCancelledToken;

+(NSArray*) racingOperationsFromCancellableOperationStarters:(NSArray*)cancellableOperationStarters
                                              untilCancelled:(id<CancelToken>)untilCancelledToken;

+(Future*) asyncWinnerFromRacingOperations:(NSArray*)racingOperations;

-(void) cancelAndTerminate;

@end
