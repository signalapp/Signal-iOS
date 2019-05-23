//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
// 

#import <SignalServiceKit/SignalServiceKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(LokiAddressMessage)
@interface LKAddressMessage : TSOutgoingMessage

- (instancetype)initInThread:(nullable TSThread *)thread
                                   address:(NSString *)address
                                      port:(uint)port;

@property (nonatomic, readonly) NSString *address;
@property (nonatomic, readonly) uint port;

@end

NS_ASSUME_NONNULL_END
