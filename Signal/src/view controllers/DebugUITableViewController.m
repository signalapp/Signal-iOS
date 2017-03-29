//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUITableViewController.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSTableItem;
@class OWSTableSection;

@interface OWSTableContents : NSObject

@property (nonatomic) NSString *title;
@property (nonatomic) NSMutableArray<OWSTableSection *> *sections;

@end

#pragma mark -

@implementation OWSTableContents

-(instancetype)init {
    if (self = [super init]) {
        _sections = [NSMutableArray new];
    }
    return self;
}

- (void)addSection:(OWSTableSection *)section {
    OWSAssert(section);
    
    [_sections addObject:section];
}

@end

#pragma mark -

@interface OWSTableSection : NSObject

@property (nonatomic) NSString *title;
@property (nonatomic) NSMutableArray<OWSTableItem *> *items;

@end

#pragma mark -

@implementation OWSTableSection

+ (OWSTableSection *)sectionWithTitle:(NSString *)title
                                items:(NSArray *)items {
    OWSTableSection *section = [OWSTableSection new];
    section.title = title;
    section.items = [items mutableCopy];
    return section;
}

-(instancetype)init {
    if (self = [super init]) {
        _items = [NSMutableArray new];
    }
    return self;
}

- (void)addItem:(OWSTableItem *)item {
    OWSAssert(item);
    
    if (!_items) {
        _items = [NSMutableArray new];
    }
    
    [_items addObject:item];
}

@end

#pragma mark -

typedef NS_ENUM(NSInteger, OWSTableItemType) {
    OWSTableItemTypeAction,
};

typedef void (^OWSTableActionBlock)();

@interface OWSTableItem : NSObject

@property (nonatomic) OWSTableItemType itemType;
@property (nonatomic) NSString *title;
@property (nonatomic) OWSTableActionBlock actionBlock;

@end

#pragma mark -

@implementation OWSTableItem

+ (OWSTableItem *)actionWithTitle:(NSString *)title
                      actionBlock:(OWSTableActionBlock)actionBlock {
    OWSAssert(title.length > 0);
    
    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.actionBlock = actionBlock;
    item.title = title;
    return item;
}

@end

#pragma mark -

NSString * const kDebugUITableCellIdentifier = @"kDebugUITableCellIdentifier";

@interface DebugUITableViewController ()

@property (nonatomic) OWSTableContents *contents;

@end

@implementation DebugUITableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView
{
    [super loadView];
    
    OWSAssert(self.contents);

    self.title = self.contents.title;
    
    OWSAssert(self.tableView);
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kDebugUITableCellIdentifier];
}

- (OWSTableSection *)sectionForIndex:(NSInteger)sectionIndex
{
    OWSAssert(self.contents);
    OWSAssert(sectionIndex >= 0 && sectionIndex < (NSInteger) self.contents.sections.count);
    
    OWSTableSection *section = self.contents.sections[(NSUInteger) sectionIndex];
    return section;
}

- (OWSTableItem *)itemForIndexPath:(NSIndexPath *)indexPath
{
    OWSAssert(self.contents);
    OWSAssert(indexPath.section >= 0 && indexPath.section < (NSInteger) self.contents.sections.count);
    
    OWSTableSection *section = self.contents.sections[(NSUInteger) indexPath.section];
    OWSAssert(indexPath.item >= 0 && indexPath.item < (NSInteger) section.items.count);
    OWSTableItem *item = section.items[(NSUInteger) indexPath.item];
    
    return item;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    OWSAssert(self.contents);

    OWSAssert(self.contents.sections.count > 0);
    return (NSInteger) self.contents.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex {
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    OWSAssert(section.items.count > 0);
    return (NSInteger) section.items.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDebugUITableCellIdentifier];
    OWSAssert(cell);
    
    cell.textLabel.text = item.title;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.itemType == OWSTableItemTypeAction) {
        OWSAssert(item.actionBlock);
        item.actionBlock();
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Factory Methods

+ (void)presentDebugUIForThread:(TSThread *)thread
             fromViewController:(UIViewController *)fromViewController {
    OWSAssert(thread);
    OWSAssert(fromViewController);

    OWSTableContents *contents = [OWSTableContents new];
    contents.title = @"Debug: Conversation";
    
    [contents addSection:[OWSTableSection sectionWithTitle:@"Messages View"
                                                     items:@[
                                                             [OWSTableItem actionWithTitle:@"Send 10 messages (1/sec.)"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendTextMessage:10
                                                                                                                        thread:thread];
                                                                               }],
                                                             [OWSTableItem actionWithTitle:@"Send 100 messages (1/sec.)"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendTextMessage:100
                                                                                                                        thread:thread];
                                                                               }],
                                                             [OWSTableItem actionWithTitle:@"Send text/x-signal-plain"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendOversizeTextMessage:thread];
                                                                               }],
                                                             [OWSTableItem actionWithTitle:@"Send unknown/mimetype"
                                                                               actionBlock:^{
                                                                                   [DebugUITableViewController sendUnknownMimetypeAttachment:thread];
                                                                               }],
                                                             ]]];
    
    DebugUITableViewController *viewController = [DebugUITableViewController new];
    viewController.contents = contents;
    [viewController presentFromViewController:fromViewController];
}

+ (void)sendTextMessage:(int)counter
                 thread:(TSThread *)thread {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    if (counter < 1) {
        return;
    }
    [ThreadUtil sendMessageWithText:[@(counter) description]
                           inThread:thread
                      messageSender:messageSender];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) 1.f * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
                       [self sendTextMessage:counter - 1 thread:thread];
                   });
}

+ (void)sendOversizeTextMessage:(TSThread *)thread {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    NSString *message = @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse consequat, ligula et tincidunt mattis, nisl risus ultricies justo, vitae dictum augue risus vel ante. Suspendisse convallis bibendum lectus. Etiam molestie nisi ac orci sodales sollicitudin vitae eu quam. Morbi lacinia scelerisque risus. Quisque sagittis mauris enim, ac vestibulum dui commodo quis. Nullam at commodo nisl, ut pulvinar dui. Nunc tempus volutpat sagittis. Vestibulum eget maximus sem, sit amet tristique ex posuere.";
    SignalAttachment *attachment = [SignalAttachment oversizeTextAttachmentWithText:message];
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                            messageSender:messageSender];
}

+ (NSData*)createRandomNSDataOfSize:(size_t)size
{
    OWSAssert(size % 4 == 0);
    
    NSMutableData* data = [NSMutableData dataWithCapacity:size];
    for (size_t i = 0; i < size / 4; ++i)
    {
        u_int32_t randomBits = arc4random();
        [data appendBytes:(void *)&randomBits length:4];
    }
    return data;
}

+ (void)sendUnknownMimetypeAttachment:(TSThread *)thread {
    OWSMessageSender *messageSender = [Environment getCurrent].messageSender;
    SignalAttachment *attachment = [SignalAttachment genericAttachmentWithData:[self createRandomNSDataOfSize:256]
                                                                       dataUTI:SignalAttachment.kUnknownTestAttachmentUTI];
    [ThreadUtil sendMessageWithAttachment:attachment
                                 inThread:thread
                            messageSender:messageSender];
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)fromViewController {
    OWSAssert(fromViewController);
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:self];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                                                          target:self
                                                                                          action:@selector(donePressed:)];
    
    [fromViewController presentViewController:navigationController
                                     animated:YES
                                   completion:nil];
}

- (void)donePressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
