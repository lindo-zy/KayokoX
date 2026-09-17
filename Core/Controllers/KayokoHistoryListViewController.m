//
//  KayokoHistoryListViewController.m
//  Kayoko
//

#import "KayokoHistoryListViewController.h"
#import "KayokoFavoritesTableView.h"
#import "KayokoHistoryItemActionHandler.h"
#import "KayokoHistoryListView.h"
#import "KayokoHistoryTableView.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPasteboardManager.h"
#import "KayokoSearchCriteria.h"
#import "KayokoSnapperIntegration.h"
#import "KayokoTableDataStore.h"
#import "KayokoTableViewCell.h"
#import "KayokoTableViewCellContent.h"
#import "KayokoTableViewCellContentProvider.h"

#import <objc/runtime.h>

static CGFloat const kKayokoGalleryMinimumRowHeight = 112;
static NSUInteger const kKayokoGalleryColumnCount = 2;
static const void *kKayokoGalleryItemDictionaryKey = &kKayokoGalleryItemDictionaryKey;

@interface KayokoGalleryRowCell : UITableViewCell
@property(nonatomic, copy) NSArray<KayokoTableViewCell *> *itemCells;
- (void)setGalleryItemCells:(NSArray<KayokoTableViewCell *> *)itemCells;
- (nullable KayokoTableViewCell *)itemCellAtColumn:(NSUInteger)column;
@end

@implementation KayokoGalleryRowCell

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        [self setSelectionStyle:UITableViewCellSelectionStyleNone];
    }
    return self;
}

- (void)setGalleryItemCells:(NSArray<KayokoTableViewCell *> *)itemCells {
    for (UIView *view in [self itemCells]) {
        [view removeFromSuperview];
    }
    _itemCells = [itemCells copy] ?: @[];

    UIView *previousView = nil;
    for (KayokoTableViewCell *itemCell in _itemCells) {
        [[self contentView] addSubview:itemCell];
        [itemCell setTranslatesAutoresizingMaskIntoConstraints:NO];
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [[itemCell topAnchor] constraintEqualToAnchor:[[self contentView] topAnchor] constant:5],
            [[itemCell bottomAnchor] constraintEqualToAnchor:[[self contentView] bottomAnchor] constant:-5]
        ]];
        if (previousView) {
            [constraints addObject:[[itemCell leadingAnchor] constraintEqualToAnchor:[previousView trailingAnchor]
                                                                            constant:8]];
            [constraints addObject:[[itemCell widthAnchor] constraintEqualToAnchor:[previousView widthAnchor]]];
        } else {
            [constraints addObject:[[itemCell leadingAnchor] constraintEqualToAnchor:[[self contentView] leadingAnchor]
                                                                            constant:8]];
            [constraints addObject:[[itemCell widthAnchor] constraintEqualToAnchor:[[self contentView] widthAnchor]
                                                                      multiplier:0.5
                                                                        constant:-12]];
        }
        [NSLayoutConstraint activateConstraints:constraints];
        previousView = itemCell;
    }
    if ([[self itemCells] count] == kKayokoGalleryColumnCount) {
        [[previousView trailingAnchor] constraintEqualToAnchor:[[self contentView] trailingAnchor] constant:-8].active = YES;
    }
}

- (nullable KayokoTableViewCell *)itemCellAtColumn:(NSUInteger)column {
    return column < [[self itemCells] count] ? [self itemCells][column] : nil;
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface KayokoHistoryListViewController () <UITableViewDelegate, UITableViewDataSource>

#pragma mark - Views

@property(nonatomic, strong, readwrite) KayokoHistoryListView *tableView;

#pragma mark - State

@property(nonatomic, copy, readwrite) NSString *historyKey;
@property(nonatomic, copy, readwrite) NSString *name;

#pragma mark - Data

@property(nonatomic, strong) KayokoTableDataStore *dataStore;
@property(nonatomic, strong) KayokoTableViewCellContentProvider *cellContentProvider;
@property(nonatomic, strong) KayokoHistoryItemActionHandler *actionHandler;
@property(nonatomic, copy, nullable) NSString *presentationHiddenItemContent;

- (KayokoTableViewCell *)newCellForItem:(KayokoPasteboardItem *)item addsPreviewGesture:(BOOL)addsPreviewGesture;
- (KayokoTableViewCell *)newGalleryCellForItem:(KayokoPasteboardItem *)item
                                     dictionary:(NSDictionary<NSString *, id> *)dictionary;
- (void)loadThumbnailForItem:(KayokoPasteboardItem *)item
                    intoCell:(KayokoTableViewCell *)cell
                  targetSize:(CGSize)targetSize;
- (void)refreshVisibleItemDetails;
- (nullable UIContextualAction *)snapperActionForItem:(KayokoPasteboardItem *)item;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoHistoryListViewController

#pragma mark - Lifecycle

- (instancetype)initWithName:(NSString *)name historyKey:(NSString *)historyKey {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _name = [name copy] ?: @"";
        _historyKey = [historyKey copy] ?: kKayokoHistoryKeyHistory;
        if ([_historyKey isEqualToString:kKayokoHistoryKeyFavorites]) {
            _tableView = [[KayokoFavoritesTableView alloc] initWithName:_name];
        } else {
            _tableView = [[KayokoHistoryTableView alloc] initWithName:_name];
        }
        _dataStore = [[KayokoTableDataStore alloc] init];
        _cellContentProvider = [[KayokoTableViewCellContentProvider alloc] init];
        _actionHandler = [[KayokoHistoryItemActionHandler alloc] init];
        [_tableView setName:_name];
        [_tableView setDelegate:self];
        [_tableView setDataSource:self];
    }
    return self;
}

- (void)loadView {
    [self setView:[self tableView]];
}

#pragma mark - State

- (NSArray<NSDictionary<NSString *, id> *> *)items {
    return [[self dataStore] items];
}

- (NSArray<NSDictionary<NSString *, id> *> *)displayedItems {
    return [[self dataStore] displayedItems];
}

- (NSString *)searchText {
    return [[self dataStore] searchText];
}

- (KayokoSearchCriteria *)searchCriteria {
    return [[self dataStore] searchCriteria];
}

- (BOOL)isBrowsingSearchTokens {
    return [[self dataStore] isBrowsingSearchTokens];
}

- (BOOL)hasActiveSearch {
    return [[self dataStore] hasActiveSearch];
}

- (void)setPreviewLineCount:(NSUInteger)previewLineCount {
    [[self tableView] setPreviewLineCount:previewLineCount];
}

- (NSUInteger)previewLineCount {
    return [[self tableView] previewLineCount];
}

- (void)setPrivacyMode:(BOOL)privacyMode {
    [[self cellContentProvider] setPrivacyMode:privacyMode];
    [self reloadTableView];
}

- (BOOL)privacyMode {
    return [[self cellContentProvider] privacyMode];
}

- (void)setItemDetailsMode:(KayokoItemDetailsMode)itemDetailsMode {
    [[self tableView] setItemDetailsMode:itemDetailsMode];
}

- (KayokoItemDetailsMode)itemDetailsMode {
    return [[self tableView] itemDetailsMode];
}

- (void)setGalleryModeEnabled:(BOOL)galleryModeEnabled {
    if (_galleryModeEnabled == galleryModeEnabled) {
        return;
    }
    _galleryModeEnabled = galleryModeEnabled;
    KayokoHistoryListView *tableView = [self tableView];
    [tableView setSeparatorStyle:galleryModeEnabled ? UITableViewCellSeparatorStyleNone
                                               : UITableViewCellSeparatorStyleSingleLine];
    if (galleryModeEnabled) {
        [tableView setRowHeight:MAX(kKayokoGalleryMinimumRowHeight, floor(CGRectGetHeight([tableView bounds]) / 3.0))];
    } else {
        [tableView setPreviewLineCount:[tableView previewLineCount]];
    }
    [self reloadTableView];
}

- (void)refreshSearchPlaceholder {
    BOOL showsNoSearchResults = [self hasActiveSearch] && ![self isBrowsingSearchTokens] && [[self items] count] > 0 &&
                                [[self displayedItems] count] == 0;
    [[self tableView] setShowsNoSearchResultsPlaceholder:showsNoSearchResults];
}

- (void)reloadTableView {
    [[self tableView] reloadData];
    [self refreshSearchPlaceholder];
}

- (void)refreshVisibleItemDetails {
    if ([self isGalleryModeEnabled]) {
        NSArray<NSIndexPath *> *visibleRows = [[self tableView] indexPathsForVisibleRows];
        if ([visibleRows count] > 0) {
            [[self tableView] reloadRowsAtIndexPaths:visibleRows withRowAnimation:UITableViewRowAnimationNone];
        }
        return;
    }
    for (NSIndexPath *indexPath in [[self tableView] indexPathsForVisibleRows]) {
        KayokoPasteboardItem *item =
            [KayokoPasteboardItem itemFromDictionary:[self itemDictionaryAtIndexPath:indexPath]];
        if (!item) {
            continue;
        }
        KayokoTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                            previewLineCount:[self previewLineCount]
                                                                             itemDetailsMode:[self itemDetailsMode]
                                                                                  searchText:[self searchText]];
        KayokoTableViewCell *cell = (KayokoTableViewCell *)[[self tableView] cellForRowAtIndexPath:indexPath];
        [cell applyDetailContent:content];
    }
}

- (void)scrollToTopAnimated:(BOOL)animated {
    [[self tableView] scrollToTopAnimated:animated];
}

#pragma mark - Diffing

- (NSArray<NSIndexPath *> *)indexPathsFromRow:(NSUInteger)startRow count:(NSUInteger)count {
    NSMutableArray<NSIndexPath *> *indexPaths = [[NSMutableArray alloc] initWithCapacity:count];
    for (NSUInteger row = startRow; row < startRow + count; row++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:row inSection:0]];
    }
    return indexPaths;
}

- (BOOL)canUpdateFromItems:(NSArray<NSDictionary<NSString *, id> *> *)oldItems
                   toItems:(NSArray<NSDictionary<NSString *, id> *> *)newItems
      withTopInsertedCount:(NSUInteger *)insertedCount
        bottomRemovedCount:(NSUInteger *)removedCount {
    NSUInteger oldCount = [oldItems count];
    NSUInteger newCount = [newItems count];

    if (newCount == 0 || [oldItems isEqualToArray:newItems]) {
        return NO;
    }

    if (oldCount == 0) {
        if (insertedCount) {
            *insertedCount = newCount;
        }
        if (removedCount) {
            *removedCount = 0;
        }
        return YES;
    }

    NSUInteger candidateInsertedCount = [newItems indexOfObject:oldItems[0]];
    if (candidateInsertedCount == NSNotFound || candidateInsertedCount == 0) {
        return NO;
    }

    NSUInteger retainedCount = MIN(oldCount, newCount - candidateInsertedCount);
    if (retainedCount == 0 || candidateInsertedCount + retainedCount != newCount) {
        return NO;
    }

    for (NSUInteger index = 0; index < retainedCount; index++) {
        if (![newItems[candidateInsertedCount + index] isEqual:oldItems[index]]) {
            return NO;
        }
    }

    if (insertedCount) {
        *insertedCount = candidateInsertedCount;
    }
    if (removedCount) {
        *removedCount = oldCount - retainedCount;
    }
    return YES;
}

- (NSUInteger)normalizedLimit:(NSUInteger)limit {
    return limit == 0 ? NSUIntegerMax : limit;
}

- (BOOL)shouldRestoreContentOffsetAfterTopInsertionFromOffset:(CGPoint)contentOffset {
    return ![self hasActiveSearch] && [[self tableView] isContentOffsetAtHiddenSearchHeaderBoundary:contentOffset];
}

- (BOOL)shouldRestoreContentOffsetAfterTopRowRemovalAtIndexPath:(NSIndexPath *)indexPath
                                                     fromOffset:(CGPoint)contentOffset {
    if ([indexPath row] != 0) {
        return NO;
    }

    return [[self tableView] isSearchHeaderExposedAtContentOffset:contentOffset] ||
           [[self tableView] isContentOffsetAtHiddenSearchHeaderBoundary:contentOffset];
}

- (BOOL)shouldRestoreContentOffsetAfterMovingRowToTopFromOffset:(CGPoint)contentOffset {
    return ![self hasActiveSearch] && ([[self tableView] isSearchHeaderExposedAtContentOffset:contentOffset] ||
                                       [[self tableView] isContentOffsetAtHiddenSearchHeaderBoundary:contentOffset]);
}

- (UITableViewRowAnimation)rowAnimationForTopInsertionFromContentOffset:(CGPoint)contentOffset {
    if ([[self tableView] isSearchHeaderExposedAtContentOffset:contentOffset]) {
        return UITableViewRowAnimationFade;
    }

    return UITableViewRowAnimationTop;
}

- (nullable NSDictionary<NSString *, id> *)itemDictionaryAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSDictionary<NSString *, id> *> *displayedItems = [self displayedItems];
    if ([indexPath row] >= [displayedItems count]) {
        return nil;
    }
    return displayedItems[[indexPath row]];
}

#pragma mark - Data Updates

- (void)setItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    [[self dataStore] setItems:items];
}

- (void)reloadDataWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    [self updateDataWithItems:items animatingTopInsertions:NO];
}

- (void)updateDataWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items
     animatingTopInsertions:(BOOL)animatingTopInsertions {
    NSArray<NSDictionary<NSString *, id> *> *oldItems = [self items] ?: @[];
    NSArray<NSDictionary<NSString *, id> *> *newItems = items ?: @[];
    NSUInteger expectedOldRowCount = [self isGalleryModeEnabled] ? ([oldItems count] + 1) / 2 : [oldItems count];
    if ([oldItems isEqualToArray:newItems] && [[self tableView] numberOfRowsInSection:0] == expectedOldRowCount) {
        [self refreshVisibleItemDetails];
        return;
    }

    NSUInteger insertedCount = 0;
    NSUInteger removedCount = 0;
    BOOL canAnimateTopInsertion = ![self isGalleryModeEnabled] && ![self hasActiveSearch] && animatingTopInsertions &&
                                  [[self tableView] numberOfRowsInSection:0] == [oldItems count] &&
                                  [self canUpdateFromItems:oldItems
                                                   toItems:newItems
                                      withTopInsertedCount:&insertedCount
                                        bottomRemovedCount:&removedCount];

    if (!canAnimateTopInsertion) {
        [self setItems:newItems];
        [self reloadTableView];
        return;
    }

    NSArray<NSIndexPath *> *insertedIndexPaths = [self indexPathsFromRow:0 count:insertedCount];
    NSArray<NSIndexPath *> *removedIndexPaths = [self indexPathsFromRow:[oldItems count] - removedCount
                                                                  count:removedCount];
    UITableViewRowAnimation insertionAnimation =
        [self rowAnimationForTopInsertionFromContentOffset:[[self tableView] contentOffset]];

    [[self tableView]
        performBatchUpdates:^{
          [self setItems:newItems];
          if ([insertedIndexPaths count] > 0) {
              [[self tableView] insertRowsAtIndexPaths:insertedIndexPaths withRowAnimation:insertionAnimation];
          }
          if ([removedIndexPaths count] > 0) {
              [[self tableView] deleteRowsAtIndexPaths:removedIndexPaths withRowAnimation:UITableViewRowAnimationFade];
          }
        }
        completion:^(__unused BOOL finished) {
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
        }];
}

#pragma mark - Search

- (void)applySearchText:(NSString *)searchText {
    [[self dataStore] applySearchText:searchText];
    [self reloadTableView];
}

- (void)beginApplyingSearchCriteria:(KayokoSearchCriteria *)searchCriteria {
    [[self dataStore] beginApplyingSearchCriteria:searchCriteria];
    [self refreshSearchPlaceholder];
}

- (void)applySearchCriteria:(KayokoSearchCriteria *)searchCriteria
              filteredItems:(NSArray<NSDictionary<NSString *, id> *> *)filteredItems {
    [[self dataStore] applySearchCriteria:searchCriteria filteredItems:filteredItems];
    [self reloadTableView];
}

- (void)showSearchTokensWithFullListForCriteria:(KayokoSearchCriteria *)searchCriteria {
    KayokoSearchCriteria *criteria = searchCriteria ?: [KayokoSearchCriteria emptyCriteria];
    BOOL alreadyBrowsingFullList =
        [self isBrowsingSearchTokens] && [[self searchCriteria] isEqualToCriteria:criteria] &&
        [[self displayedItems] count] == [[self items] count] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count];
    BOOL canFlipStateWithoutReload =
        !alreadyBrowsingFullList && ![self hasActiveSearch] &&
        [[self displayedItems] isEqualToArray:[self items] ?: @[]] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count];

    [[self dataStore] showSearchTokensWithFullListForCriteria:criteria];
    if (alreadyBrowsingFullList || canFlipStateWithoutReload) {
        [self refreshSearchPlaceholder];
        return;
    }
    [self reloadTableView];
}

- (void)clearSearch {
    if (![self hasActiveSearch] && ![self isBrowsingSearchTokens] &&
        [[self displayedItems] isEqualToArray:[self items] ?: @[]] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count]) {
        [[self dataStore] clearSearch];
        [self refreshSearchPlaceholder];
        return;
    }
    [[self dataStore] clearSearch];
    [self reloadTableView];
}

#pragma mark - Item Mutations

- (void)clearItems {
    NSArray<NSDictionary<NSString *, id> *> *oldItems = [self items] ?: @[];
    if ([oldItems count] == 0) {
        return;
    }

    [self setItems:@[]];
    [self reloadTableView];
}

- (void)upsertItemDictionaryAtTop:(NSDictionary<NSString *, id> *)dictionary limit:(NSUInteger)limit {
    [self upsertItemDictionaryAtTop:dictionary limit:limit animating:YES];
}

- (void)upsertItemDictionaryAtTop:(NSDictionary<NSString *, id> *)dictionary
                            limit:(NSUInteger)limit
                        animating:(BOOL)animating {
    if (!dictionary || [dictionary[kKayokoItemKeyContent] length] == 0) {
        return;
    }

    NSArray<NSDictionary<NSString *, id> *> *oldItems = [self items] ?: @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *newItems = [oldItems mutableCopy];
    NSUInteger existingIndex = [[self dataStore] indexOfItemMatchingDictionary:dictionary inItems:newItems];
    NSUInteger normalizedLimit = [self normalizedLimit:limit];

    if (existingIndex != NSNotFound) {
        [newItems removeObjectAtIndex:existingIndex];
    }
    [newItems insertObject:dictionary atIndex:0];
    while ([newItems count] > normalizedLimit) {
        [newItems removeLastObject];
    }

    if ([self isGalleryModeEnabled]) {
        [self setItems:newItems];
        [self reloadTableView];
        return;
    }

    if ([oldItems isEqualToArray:newItems] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count]) {
        [self refreshVisibleItemDetails];
        return;
    }

    if (!animating) {
        [self updateDataWithItems:newItems animatingTopInsertions:NO];
        return;
    }

    if ([self hasActiveSearch] || [[self tableView] numberOfRowsInSection:0] != [oldItems count]) {
        [self updateDataWithItems:newItems animatingTopInsertions:YES];
        return;
    }

    if (existingIndex == 0) {
        [self setItems:newItems];
        [[self tableView] reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:0 inSection:0] ]
                                withRowAnimation:UITableViewRowAnimationNone];
        [self refreshVisibleItemDetails];
        [self refreshSearchPlaceholder];
        return;
    }

    if (existingIndex != NSNotFound && existingIndex < [oldItems count] && [newItems count] == [oldItems count]) {
        CGPoint contentOffsetBeforeMove = [[self tableView] contentOffset];
        BOOL restoresContentOffsetAfterMove =
            [self shouldRestoreContentOffsetAfterMovingRowToTopFromOffset:contentOffsetBeforeMove];

        [[self tableView]
            performBatchUpdates:^{
              [self setItems:newItems];
              [[self tableView] moveRowAtIndexPath:[NSIndexPath indexPathForRow:existingIndex inSection:0]
                                       toIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            }
            completion:^(__unused BOOL finished) {
              if (restoresContentOffsetAfterMove) {
                  [[self tableView] setContentOffset:contentOffsetBeforeMove animated:NO];
              }
              [self refreshVisibleItemDetails];
              [self refreshSearchPlaceholder];
            }];
        return;
    }

    NSUInteger removedCount = [oldItems count] + 1 > [newItems count] ? [oldItems count] + 1 - [newItems count] : 0;
    NSMutableArray<NSIndexPath *> *removedIndexPaths = [[NSMutableArray alloc] initWithCapacity:removedCount];
    for (NSUInteger row = [oldItems count] - removedCount; row < [oldItems count]; row++) {
        [removedIndexPaths addObject:[NSIndexPath indexPathForRow:row inSection:0]];
    }

    CGPoint contentOffsetBeforeInsertion = [[self tableView] contentOffset];
    BOOL restoresContentOffsetAfterInsertion =
        [self shouldRestoreContentOffsetAfterTopInsertionFromOffset:contentOffsetBeforeInsertion];
    UITableViewRowAnimation insertionAnimation =
        [self rowAnimationForTopInsertionFromContentOffset:contentOffsetBeforeInsertion];

    [[self tableView]
        performBatchUpdates:^{
          [self setItems:newItems];
          [[self tableView] insertRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:0 inSection:0] ]
                                  withRowAnimation:insertionAnimation];
          if ([removedIndexPaths count] > 0) {
              [[self tableView] deleteRowsAtIndexPaths:removedIndexPaths withRowAnimation:UITableViewRowAnimationFade];
          }
        }
        completion:^(__unused BOOL finished) {
          if (restoresContentOffsetAfterInsertion) {
              [[self tableView] setContentOffset:contentOffsetBeforeInsertion animated:NO];
          }
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
        }];
}

- (void)removeItemDictionary:(NSDictionary<NSString *, id> *)dictionary {
    NSArray<NSDictionary<NSString *, id> *> *displayedItems = [self displayedItems] ?: @[];
    NSUInteger displayedIndex = [[self dataStore] indexOfItemMatchingDictionary:dictionary inItems:displayedItems];
    if (displayedIndex == NSNotFound) {
        return;
    }

    [self removeItemAtIndexPath:[NSIndexPath indexPathForRow:displayedIndex inSection:0] completion:nil];
}

- (void)removeItemAtIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL success))completion {
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    if (!dictionary || [indexPath row] >= [[self displayedItems] count]) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if ([self isGalleryModeEnabled]) {
        [[self dataStore] removeDisplayedItemAtIndex:[indexPath row]];
        [self reloadTableView];
        if (completion) {
            completion(YES);
        }
        return;
    }

    CGPoint contentOffsetBeforeRemoval = [[self tableView] contentOffset];
    BOOL restoresContentOffsetAfterRemoval =
        [self shouldRestoreContentOffsetAfterTopRowRemovalAtIndexPath:indexPath fromOffset:contentOffsetBeforeRemoval];

    [[self tableView] prepareHiddenHeaderInsetsForRemovingRowAtIndexPath:indexPath];

    [[self tableView]
        performBatchUpdates:^{
          [[self dataStore] removeDisplayedItemAtIndex:[indexPath row]];
          [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        completion:^(__unused BOOL finished) {
          if (restoresContentOffsetAfterRemoval) {
              [[self tableView] setContentOffset:contentOffsetBeforeRemoval animated:NO];
          }
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
          if (completion) {
              completion(YES);
          }
        }];
}

- (void)updateNote:(NSString *)note
            tagUUID:(NSString *)tagUUID
            forItem:(KayokoPasteboardItem *)item
         completion:(void (^)(void))completion {
    if (!item) {
        if (completion) {
            completion();
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    if ([self isGalleryModeEnabled]) {
        NSUInteger displayedIndex = NSNotFound;
        [[self dataStore] updateNote:note
                             tagUUID:tagUUID
              forItemMatchingDictionary:dictionary
                     displayedItemIndex:&displayedIndex];
        [self reloadTableView];
        if (completion) {
            completion();
        }
        return;
    }
    __block KayokoTableDataStoreDisplayedItemUpdate update = KayokoTableDataStoreDisplayedItemUpdateNotFound;
    __block NSUInteger displayedIndex = NSNotFound;

    [[self tableView]
        performBatchUpdates:^{
          update = [[self dataStore] updateNote:note
                                        tagUUID:tagUUID
                         forItemMatchingDictionary:dictionary
                                displayedItemIndex:&displayedIndex];
          if (displayedIndex == NSNotFound) {
              return;
          }

          NSIndexPath *indexPath = [NSIndexPath indexPathForRow:displayedIndex inSection:0];
          if (update == KayokoTableDataStoreDisplayedItemUpdateRemove) {
              [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
          } else if (update == KayokoTableDataStoreDisplayedItemUpdateReload) {
              [[self tableView] reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
          }
        }
        completion:^(__unused BOOL finished) {
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
          if (completion) {
              completion();
          }
        }];
}

- (void)replaceContent:(NSString *)content
               forItem:(KayokoPasteboardItem *)item
            completion:(void (^)(void))completion {
    [self replaceContent:content
forItemMatchingDictionary:[item dictionaryRepresentation]
              completion:completion];
}

- (void)replaceContent:(NSString *)content
forItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
            completion:(void (^)(void))completion {
    if (!dictionary || [content length] == 0) {
        if (completion) {
            completion();
        }
        return;
    }
    if ([self isGalleryModeEnabled]) {
        NSUInteger displayedIndex = NSNotFound;
        [[self dataStore] replaceContent:content
              forItemMatchingDictionary:dictionary
                     displayedItemIndex:&displayedIndex];
        [self reloadTableView];
        if (completion) {
            completion();
        }
        return;
    }
    __block KayokoTableDataStoreDisplayedItemUpdate update = KayokoTableDataStoreDisplayedItemUpdateNotFound;
    __block NSUInteger displayedIndex = NSNotFound;

    [[self tableView]
        performBatchUpdates:^{
          update = [[self dataStore] replaceContent:content
                           forItemMatchingDictionary:dictionary
                                  displayedItemIndex:&displayedIndex];
          if (displayedIndex == NSNotFound) {
              return;
          }

          NSIndexPath *indexPath = [NSIndexPath indexPathForRow:displayedIndex inSection:0];
          if (update == KayokoTableDataStoreDisplayedItemUpdateRemove) {
              [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
          } else if (update == KayokoTableDataStoreDisplayedItemUpdateReload) {
              [[self tableView] reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
          }
        }
        completion:^(__unused BOOL finished) {
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
          if (completion) {
              completion();
          }
        }];
}

- (nullable KayokoTableViewCell *)visibleCellForItem:(KayokoPasteboardItem *)item {
    if (!item) {
        return nil;
    }

    NSUInteger displayedIndex = [[self dataStore] indexOfItemMatchingDictionary:[item dictionaryRepresentation]
                                                                        inItems:[self displayedItems]];
    if (displayedIndex == NSNotFound) {
        return nil;
    }
    if ([self isGalleryModeEnabled]) {
        NSIndexPath *rowIndexPath = [NSIndexPath indexPathForRow:displayedIndex / kKayokoGalleryColumnCount inSection:0];
        KayokoGalleryRowCell *rowCell = (KayokoGalleryRowCell *)[[self tableView] cellForRowAtIndexPath:rowIndexPath];
        return [rowCell itemCellAtColumn:displayedIndex % kKayokoGalleryColumnCount];
    }
    return (KayokoTableViewCell *)[[self tableView]
        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:displayedIndex inSection:0]];
}

- (KayokoTableViewCell *)presentationCellForItem:(KayokoPasteboardItem *)item {
    return [self newCellForItem:item addsPreviewGesture:NO];
}

- (void)setCellPresentationHidden:(BOOL)hidden forItem:(KayokoPasteboardItem *)item {
    NSString *content = [item content];
    if ([content length] == 0) {
        return;
    }

    if (hidden) {
        [self setPresentationHiddenItemContent:content];
    } else if ([[self presentationHiddenItemContent] isEqualToString:content]) {
        [self setPresentationHiddenItemContent:nil];
    } else {
        return;
    }

    KayokoHistoryListView *tableView = [self tableView];
    NSString *hiddenContent = [self presentationHiddenItemContent];
    if ([self isGalleryModeEnabled]) {
        for (NSIndexPath *rowIndexPath in [tableView indexPathsForVisibleRows]) {
            KayokoGalleryRowCell *rowCell = (KayokoGalleryRowCell *)[tableView cellForRowAtIndexPath:rowIndexPath];
            for (KayokoTableViewCell *itemCell in [rowCell itemCells]) {
                NSDictionary *dictionary = objc_getAssociatedObject(itemCell, kKayokoGalleryItemDictionaryKey);
                BOOL hidesCell = [hiddenContent length] > 0 &&
                                 [dictionary[kKayokoItemKeyContent] isEqualToString:hiddenContent];
                [itemCell setHidden:hidesCell];
            }
        }
        return;
    }
    for (NSIndexPath *indexPath in [tableView indexPathsForVisibleRows]) {
        NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
        BOOL hidesCell =
            [hiddenContent length] > 0 && [dictionary[kKayokoItemKeyContent] isEqualToString:hiddenContent];
        [[tableView cellForRowAtIndexPath:indexPath] setHidden:hidesCell];
    }
}

- (nullable KayokoTableViewCell *)scrollItemToVisible:(KayokoPasteboardItem *)item {
    if (!item) {
        return nil;
    }

    NSUInteger displayedIndex = [[self dataStore] indexOfItemMatchingDictionary:[item dictionaryRepresentation]
                                                                        inItems:[self displayedItems]];
    if (displayedIndex == NSNotFound) {
        return nil;
    }

    NSUInteger tableRow = [self isGalleryModeEnabled] ? displayedIndex / kKayokoGalleryColumnCount : displayedIndex;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:tableRow inSection:0];
    KayokoHistoryListView *tableView = [self tableView];
    [tableView layoutIfNeeded];
    KayokoTableViewCell *visibleCell = [self visibleCellForItem:item];
    if (visibleCell) {
        return visibleCell;
    }

    [tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [tableView layoutIfNeeded];
    return [self visibleCellForItem:item];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView != [self tableView]) {
        return 0;
    }
    NSUInteger itemCount = [[self displayedItems] count];
    return [self isGalleryModeEnabled] ? (itemCount + kKayokoGalleryColumnCount - 1) / kKayokoGalleryColumnCount
                                       : itemCount;
}

- (KayokoTableViewCell *)newCellForItem:(KayokoPasteboardItem *)item addsPreviewGesture:(BOOL)addsPreviewGesture {
    KayokoTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                        previewLineCount:[self previewLineCount]
                                                                         itemDetailsMode:[self itemDetailsMode]
                                                                              searchText:[self searchText]];

    KayokoTableViewCell *cell =
        [[KayokoTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           content:content
                                   reuseIdentifier:[KayokoTableViewCell reuseIdentifierForContent:content]];
    [self loadThumbnailForItem:item intoCell:cell targetSize:[KayokoTableViewCell contentImageThumbnailSize]];

    if (addsPreviewGesture) {
        UILongPressGestureRecognizer *gesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(handleLongPressGestureRecognizer:)];
        [cell addGestureRecognizer:gesture];
    }
    return cell;
}

- (KayokoTableViewCell *)newGalleryCellForItem:(KayokoPasteboardItem *)item
                                     dictionary:(NSDictionary<NSString *, id> *)dictionary {
    KayokoTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                        previewLineCount:3
                                                                         itemDetailsMode:[self itemDetailsMode]
                                                                              searchText:[self searchText]];
    KayokoTableViewCell *cell = [[KayokoTableViewCell alloc]
        initWithGalleryContent:content
               reuseIdentifier:[KayokoTableViewCell galleryReuseIdentifierForContent:content]];
    objc_setAssociatedObject(cell, kKayokoGalleryItemDictionaryKey, dictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITapGestureRecognizer *tapGesture =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleGalleryTapGestureRecognizer:)];
    [cell addGestureRecognizer:tapGesture];
    UILongPressGestureRecognizer *longPressGesture =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGestureRecognizer:)];
    [tapGesture requireGestureRecognizerToFail:longPressGesture];
    [cell addGestureRecognizer:longPressGesture];
    [self loadThumbnailForItem:item
                      intoCell:cell
                    targetSize:[KayokoTableViewCell galleryContentImageThumbnailSize]];
    return cell;
}

- (void)loadThumbnailForItem:(KayokoPasteboardItem *)item
                    intoCell:(KayokoTableViewCell *)cell
                  targetSize:(CGSize)targetSize {
    NSString *imageName = [[item imageName] copy];
    if ([imageName length] == 0) {
        return;
    }

    __weak KayokoTableViewCell *weakCell = cell;
    [[self cellContentProvider] loadThumbnailForItem:item
                                          targetSize:targetSize
                                          completion:^(UIImage *_Nullable image) {
                                            [weakCell setContentImage:image forImageName:imageName];
                                          }];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        static NSString *const reuseIdentifier = @"KayokoGalleryRowCell";
        KayokoGalleryRowCell *rowCell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
        if (!rowCell) {
            rowCell = [[KayokoGalleryRowCell alloc] initWithReuseIdentifier:reuseIdentifier];
        }
        NSMutableArray<KayokoTableViewCell *> *itemCells = [[NSMutableArray alloc] initWithCapacity:2];
        NSUInteger firstItemIndex = [indexPath row] * kKayokoGalleryColumnCount;
        for (NSUInteger column = 0; column < kKayokoGalleryColumnCount; column++) {
            NSUInteger itemIndex = firstItemIndex + column;
            if (itemIndex >= [[self displayedItems] count]) {
                break;
            }
            NSDictionary<NSString *, id> *dictionary = [self displayedItems][itemIndex];
            KayokoPasteboardItem *item = [KayokoPasteboardItem itemFromDictionary:dictionary];
            KayokoTableViewCell *itemCell = [self newGalleryCellForItem:item dictionary:dictionary];
            [itemCell setHidden:[[self presentationHiddenItemContent] isEqualToString:[item content]]];
            [itemCells addObject:itemCell];
        }
        [rowCell setGalleryItemCells:itemCells];
        return rowCell;
    }
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    KayokoPasteboardItem *item = [KayokoPasteboardItem itemFromDictionary:dictionary];
    KayokoTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                        previewLineCount:[self previewLineCount]
                                                                         itemDetailsMode:[self itemDetailsMode]
                                                                              searchText:[self searchText]];
    NSString *reuseIdentifier = [KayokoTableViewCell reuseIdentifierForContent:content];
    KayokoTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell) {
        [cell applyContent:content];
    } else {
        cell = [[KayokoTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                  content:content
                                          reuseIdentifier:reuseIdentifier];
        UILongPressGestureRecognizer *gesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(handleLongPressGestureRecognizer:)];
        [cell addGestureRecognizer:gesture];
    }
    [self loadThumbnailForItem:item intoCell:cell targetSize:[KayokoTableViewCell contentImageThumbnailSize]];
    [cell setHidden:[[self presentationHiddenItemContent] isEqualToString:[item content]]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView
      willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ([self isGalleryModeEnabled]) {
        return;
    }
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    NSString *hiddenContent = [self presentationHiddenItemContent];
    BOOL hidesCell = [hiddenContent length] > 0 && [dictionary[kKayokoItemKeyContent] isEqualToString:hiddenContent];
    [cell setHidden:hidesCell];
}

- (void)tableView:(UITableView *)tableView
    didEndDisplayingCell:(UITableViewCell *)cell
       forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    [cell setHidden:NO];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        return;
    }
    [[tableView cellForRowAtIndexPath:indexPath] setSelected:NO animated:YES];

    KayokoPasteboardItem *item = [KayokoPasteboardItem itemFromDictionary:[self itemDictionaryAtIndexPath:indexPath]];
    [self activateItem:item];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)indexPath;
    if (![self isGalleryModeEnabled]) {
        return [tableView rowHeight];
    }
    return MAX(kKayokoGalleryMinimumRowHeight, floor(CGRectGetHeight([tableView bounds]) / 3.0));
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    (void)velocity;
    if (scrollView != [self tableView] || [self hasActiveSearch]) {
        return;
    }

    [[self tableView] adjustTargetContentOffsetForSearchBarSnap:targetContentOffset];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        return nil;
    }
    NSMutableArray<UIContextualAction *> *actions = [[NSMutableArray alloc] init];
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    KayokoPasteboardItem *item = [KayokoPasteboardItem itemFromDictionary:dictionary];

    UIContextualAction *moveAction = [self moveActionForItem:item dictionary:dictionary indexPath:indexPath];
    if (moveAction) {
        [actions addObject:moveAction];
    }

    UIContextualAction *noteAction = [self noteActionForItem:item indexPath:indexPath];
    if (noteAction) {
        [actions addObject:noteAction];
    }

    UIContextualAction *saveAction = [self saveActionForItem:item];
    if (saveAction) {
        [actions addObject:saveAction];
    }

    UIContextualAction *linkAction = [self linkActionForItem:item];
    if (linkAction) {
        [actions addObject:linkAction];
    }

    return [UISwipeActionsConfiguration configurationWithActions:actions];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        return nil;
    }
    KayokoPasteboardItem *item = [KayokoPasteboardItem itemFromDictionary:[self itemDictionaryAtIndexPath:indexPath]];

    NSMutableArray<UIContextualAction *> *actions = [[NSMutableArray alloc] init];
    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@""
                          handler:^(__unused UIContextualAction *action, __unused __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            [[self actionHandler]
                                deleteItem:item
                                historyKey:[self historyKey]
                                completion:^(BOOL success) {
                                  if (!success) {
                                      completionHandler(NO);
                                      return;
                                  }
                                  [self removeItemAtIndexPath:indexPath
                                                   completion:^(BOOL removed) {
                                                     if (removed) {
                                                         [[self delegate]
                                                             historyListViewControllerDidChangeContentState:self];
                                                     }
                                                     completionHandler(removed);
                                                   }];
                                }];
                          }];
    [deleteAction setImage:[UIImage systemImageNamed:@"trash.fill"]];
    [deleteAction setBackgroundColor:[UIColor systemRedColor]];
    [actions addObject:deleteAction];

    UIContextualAction *snapperAction = [self snapperActionForItem:item];
    if (snapperAction) {
        [actions addObject:snapperAction];
    }
    return [UISwipeActionsConfiguration configurationWithActions:actions];
}

#pragma mark - Swipe Actions

- (nullable UIContextualAction *)snapperActionForItem:(KayokoPasteboardItem *)item {
    NSString *text = [[item content] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!item || ([[item imageName] length] == 0 && [text length] == 0) || ![KayokoSnapperIntegration isAvailable]) {
        return nil;
    }

    UIContextualAction *snapperAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:@""
                          handler:^(__unused UIContextualAction *action, __unused __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            completionHandler([KayokoSnapperIntegration floatPasteboardItem:item]);
                          }];
    [snapperAction setImage:[UIImage systemImageNamed:@"pin.fill"]];
    [snapperAction setBackgroundColor:[UIColor systemGreenColor]];
    return snapperAction;
}

- (UIContextualAction *)moveActionForItem:(KayokoPasteboardItem *)item
                               dictionary:(NSDictionary<NSString *, id> *)dictionary
                                indexPath:(NSIndexPath *)indexPath {
    NSString *sourceHistoryKey = [self historyKey];
    BOOL sourceIsFavorites = [sourceHistoryKey isEqualToString:kKayokoHistoryKeyFavorites];
    NSString *destinationHistoryKey = sourceIsFavorites ? kKayokoHistoryKeyHistory : kKayokoHistoryKeyFavorites;
    NSString *imageName = sourceIsFavorites ? @"heart.slash.fill" : @"heart.fill";

    UIContextualAction *moveAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@""
                          handler:^(__unused UIContextualAction *action, __unused __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            [[self actionHandler]
                                             moveItem:item
                                     sourceHistoryKey:sourceHistoryKey
                                destinationHistoryKey:destinationHistoryKey
                                           completion:^(BOOL success) {
                                             if (!success) {
                                                 completionHandler(NO);
                                                 return;
                                             }
                                             [[self delegate] historyListViewController:self
                                                                  didMoveItemDictionary:dictionary
                                                                     fromHistoryWithKey:sourceHistoryKey
                                                                       toHistoryWithKey:destinationHistoryKey];
                                             [self removeItemAtIndexPath:indexPath
                                                              completion:^(BOOL removed) {
                                                                if (removed) {
                                                                    [[self delegate]
                                                                        historyListViewControllerDidChangeContentState:
                                                                            self];
                                                                }
                                                                completionHandler(removed);
                                                              }];
                                           }];
                          }];
    [moveAction setImage:[UIImage systemImageNamed:imageName]];
    [moveAction setBackgroundColor:[UIColor systemPinkColor]];
    return moveAction;
}

- (UIContextualAction *)noteActionForItem:(KayokoPasteboardItem *)item indexPath:(NSIndexPath *)indexPath {
    UIContextualAction *noteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:@""
                          handler:^(__unused UIContextualAction *action, __unused __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            KayokoTableViewCell *sourceCell =
                                (KayokoTableViewCell *)[[self tableView] cellForRowAtIndexPath:indexPath];
                            KayokoTableViewCell *presentationCell = [self newCellForItem:item addsPreviewGesture:NO];
                            completionHandler(YES);
                            dispatch_async(dispatch_get_main_queue(), ^{
                              [[self delegate] historyListViewController:self
                                               didRequestEditNoteForItem:item
                                                        presentationCell:presentationCell
                                                              sourceCell:sourceCell];
                            });
                          }];
    [noteAction setImage:[UIImage systemImageNamed:@"note.text"]];
    [noteAction setBackgroundColor:[UIColor systemOrangeColor]];
    return noteAction;
}

- (UIContextualAction *)saveActionForItem:(KayokoPasteboardItem *)item {
    if (![self automaticallyPaste] && [[item imageName] length] == 0) {
        return nil;
    }

    BOOL savesImage = [[item imageName] length] > 0;
    UIContextualAction *saveAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:@""
                          handler:^(__unused UIContextualAction *action, __unused __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            if (savesImage) {
                                [[self actionHandler] saveImageForItem:item completion:completionHandler];
                            } else {
                                [[self actionHandler] copyItem:item completion:completionHandler];
                            }
                          }];
    [saveAction setImage:[UIImage systemImageNamed:savesImage ? @"square.and.arrow.down.fill" : @"doc.on.doc.fill"]];
    [saveAction setBackgroundColor:[UIColor systemBlueColor]];
    return saveAction;
}

- (UIContextualAction *)linkActionForItem:(KayokoPasteboardItem *)item {
    if (![item hasLink]) {
        return nil;
    }

    UIContextualAction *linkAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:@""
                          handler:^(__unused UIContextualAction *action, __unused __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            [[self actionHandler] openLinkForItem:item completion:completionHandler];
                          }];
    [linkAction setImage:[UIImage systemImageNamed:@"safari"]];
    [linkAction setBackgroundColor:[UIColor systemGreenColor]];
    return linkAction;
}

#pragma mark - Gestures

- (void)activateItem:(KayokoPasteboardItem *)item {
    if (!item) {
        return;
    }
    [[self actionHandler] activateItem:item
                            historyKey:[self historyKey]
                            completion:^(BOOL success) {
                              if (success) {
                                  if ([self automaticallyPaste]) {
                                      [[self delegate] historyListViewControllerDidRequestHideAfterDirectPaste:self];
                                  } else {
                                      [[self delegate] historyListViewControllerDidRequestHide:self];
                                  }
                              }
                            }];
}

- (void)handleGalleryTapGestureRecognizer:(UITapGestureRecognizer *)recognizer {
    if ([recognizer state] != UIGestureRecognizerStateEnded) {
        return;
    }
    NSDictionary *dictionary = objc_getAssociatedObject([recognizer view], kKayokoGalleryItemDictionaryKey);
    [self activateItem:[KayokoPasteboardItem itemFromDictionary:dictionary]];
}

- (void)handleLongPressGestureRecognizer:(UILongPressGestureRecognizer *)recognizer {
    if ([recognizer state] != UIGestureRecognizerStateBegan) {
        return;
    }

    NSDictionary *dictionary = objc_getAssociatedObject([recognizer view], kKayokoGalleryItemDictionaryKey);
    if (!dictionary) {
        NSIndexPath *indexPath = [[self tableView] indexPathForCell:(UITableViewCell *)[recognizer view]];
        dictionary = [self itemDictionaryAtIndexPath:indexPath];
    }
    KayokoPasteboardItem *item = [KayokoPasteboardItem itemFromDictionary:dictionary];
    if (item) {
        [[self delegate] historyListViewController:self didRequestPreviewForItem:item];
    }
}

@end
