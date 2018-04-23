//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol OWSCallMessageHandler;
@protocol NotificationsProtocol;

typedef id<OWSCallMessageHandler> _Nonnull (^CallMessageHandlerBlock)(void);
typedef id<NotificationsProtocol> _Nonnull (^NotificationsManagerBlock)(void);

// This is _NOT_ a singleton and will be instantiated each time that the SAE is used.
@interface AppSetup : NSObject

+ (void)setupEnvironment:(CallMessageHandlerBlock)callMessageHandlerBlock
    notificationsProtocolBlock:(NotificationsManagerBlock)notificationsManagerBlock
           migrationCompletion:(dispatch_block_t)migrationCompletion;

@end

NS_ASSUME_NONNULL_END
