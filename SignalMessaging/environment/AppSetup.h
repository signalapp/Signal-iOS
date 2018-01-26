//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol OWSCallMessageHandler;
@protocol NotificationsProtocol;

typedef id<OWSCallMessageHandler> _Nonnull (^CallMessageHandlerBlock)(void);
typedef id<NotificationsProtocol> _Nonnull (^NotificationsManagerBlock)(void);

// This is _NOT_ a singleton and will be instantiated each time that the SAE is used.
@interface AppSetup : NSObject

+ (void)setupEnvironment:(CallMessageHandlerBlock)callMessageHandlerBlock
    notificationsProtocolBlock:(NotificationsManagerBlock)notificationsManagerBlock;

@end

NS_ASSUME_NONNULL_END
