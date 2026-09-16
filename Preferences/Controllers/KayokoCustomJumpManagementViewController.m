//
//  KayokoCustomJumpManagementViewController.m
//  Kayoko
//

#import "KayokoCustomJumpManagementViewController.h"
#import "KayokoCustomJump.h"
#import "KayokoCustomJumpStore.h"
#import "KayokoCustomJumpTableViewCell.h"
#import "KayokoCustomJumpEditorViewController.h"
#import "KayokoKeyboardAvoidanceCoordinator.h"
#import "KayokoTagPlaceholderView.h"

static NSString *const kKayokoCustomJumpCellReuseIdentifier = @"KayokoCustomJumpCell";
static CGFloat const kKayokoCustomJumpPlaceholderMinimumHeight = 96.0;

@interface KayokoCustomJumpManagementViewController () <UITableViewDataSource, UITableViewDelegate,
                                                        UISearchResultsUpdating, UISearchControllerDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) KayokoTagPlaceholderView *placeholderView;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, strong) NSMutableArray<KayokoCustomJump *> *jumps;
@property(nonatomic, strong) NSMutableArray<KayokoCustomJump *> *filteredJumps;
@property(nonatomic, strong) NSMutableSet<NSString *> *selectedJumpUUIDs;
@property(nonatomic, strong) KayokoCustomJumpStore *jumpStore;
@property(nonatomic, strong) NSBundle *localizationBundle;
@property(nonatomic, strong) KayokoKeyboardAvoidanceCoordinator *keyboardAvoidanceCoordinator;
@property(nonatomic, strong) UIBarButtonItem *toolbarFlexibleSpaceItem;
@property(nonatomic, strong) UIBarButtonItem *addToolbarItem;
@property(nonatomic, strong) UIBarButtonItem *selectToolbarItem;
@property(nonatomic, strong) UIBarButtonItem *deleteToolbarItem;
@property(nonatomic, assign, getter=isSearchInterfaceActive) BOOL searchInterfaceActive;
@property(nonatomic, assign) CGFloat keyboardBottomInset;
@property(nonatomic, assign, getter=isUpdatingPlaceholderLayout) BOOL updatingPlaceholderLayout;
- (UIBarButtonItem *)editDoneButton;
- (void)updateToolbarItems;
- (void)toggleSelectAll;
- (void)deleteSelectedJumps;
- (BOOL)allDisplayedJumpsSelected;
- (NSSet<NSString *> *)selectedDisplayedJumpUUIDs;
- (void)reloadTableForSearchStateChangeFromSearching:(BOOL)wasSearching;
- (void)syncDisplayedSelectionState;
@end

@implementation KayokoCustomJumpManagementViewController

+ (BOOL)isImageActionManagement {
    return NO;
}

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [view setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    [self setView:view];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _localizationBundle = [NSBundle bundleForClass:[self class]];
    _jumps = [[NSMutableArray alloc] init];
    _filteredJumps = [[NSMutableArray alloc] init];
    _selectedJumpUUIDs = [[NSMutableSet alloc] init];
    NSString *jumpsPath = [[self class] isImageActionManagement] ? [KayokoCustomJumpStore defaultImageActionsPath]
                                                                  : [KayokoCustomJumpStore defaultJumpsPath];
    _jumpStore = [[KayokoCustomJumpStore alloc] initWithJumpsPath:jumpsPath];

    [self setTitle:[self localizedStringForKey:[[self class] isImageActionManagement] ? @"Image Actions" : @"Custom Jumps"]];
    [self loadJumps];
    [self configureNavigationItem];
    [self configureSearchController];
    [self configureTableView];
    [self configurePlaceholderView];
    [self configureToolbarItems];
    [self updateToolbarItems];
    [self updatePlaceholderVisibility];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePlaceholderLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[self navigationController] setToolbarHidden:NO animated:animated];
    [[self keyboardAvoidanceCoordinator] startObserving];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[self keyboardAvoidanceCoordinator] stopObservingAndRestoreInsets];
    if ([self isMovingFromParentViewController] || [[self navigationController] isBeingDismissed]) {
        [[self navigationController] setToolbarHidden:YES animated:animated];
    }
}

- (void)loadJumps {
    NSError *error = nil;
    NSMutableArray<KayokoCustomJump *> *loadedJumps = [[self jumpStore] loadJumpsWithError:&error];
    if (!loadedJumps) {
        [self presentError:error];
        return;
    }
    [[self jumps] addObjectsFromArray:loadedJumps];
}

- (void)configureSearchController {
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    [_searchController setSearchResultsUpdater:self];
    [_searchController setDelegate:self];
    [_searchController setObscuresBackgroundDuringPresentation:NO];
    [_searchController setHidesNavigationBarDuringPresentation:NO];
    NSString *searchKey = [[self class] isImageActionManagement] ? @"Search Image Actions…" : @"Search Custom Jumps…";
    [[_searchController searchBar] setPlaceholder:[self localizedStringForKey:searchKey]];
    [self setDefinesPresentationContext:YES];
    [[self navigationItem] setSearchController:_searchController];
    [[self navigationItem] setHidesSearchBarWhenScrolling:YES];
}

- (void)configureTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setAllowsMultipleSelectionDuringEditing:YES];
    [_tableView setRowHeight:64.0];
    [_tableView registerClass:[KayokoCustomJumpTableViewCell class]
       forCellReuseIdentifier:kKayokoCustomJumpCellReuseIdentifier];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];

    _keyboardAvoidanceCoordinator = [[KayokoKeyboardAvoidanceCoordinator alloc] initWithView:[self view]
                                                                                     scrollView:_tableView];
    __weak typeof(self) weakSelf = self;
    [_keyboardAvoidanceCoordinator setKeyboardBottomInsetChangeHandler:^(CGFloat keyboardBottomInset) {
      [weakSelf setKeyboardBottomInset:keyboardBottomInset];
      [weakSelf updatePlaceholderLayout];
      [[weakSelf placeholderView] layoutIfNeeded];
    }];
}

- (void)configurePlaceholderView {
    NSString *emptyKey = [[self class] isImageActionManagement] ? @"No Image Actions" : @"No Custom Jumps";
    _placeholderView = [[KayokoTagPlaceholderView alloc] initWithMessage:[self localizedStringForKey:emptyKey]];
}

- (void)configureToolbarItems {
    _toolbarFlexibleSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                target:nil
                                                                                action:nil];
    _addToolbarItem = [[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Add"]
                                                       style:UIBarButtonItemStylePlain
                                                      target:self
                                                      action:@selector(addJump)];
    _selectToolbarItem = [[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Select All"]
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(toggleSelectAll)];
    _deleteToolbarItem = [[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Delete"]
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(deleteSelectedJumps)];
    [_deleteToolbarItem setTintColor:[UIColor systemRedColor]];
}

- (void)configureNavigationItem {
    [[self navigationItem] setLargeTitleDisplayMode:UINavigationItemLargeTitleDisplayModeNever];
    [[self navigationItem] setRightBarButtonItem:[self editDoneButton]];
}

- (UIBarButtonItem *)editDoneButton {
    NSString *key = [self isEditing] ? @"Done" : @"Edit";
    UIBarButtonItemStyle style = [self isEditing] ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain;
    return [[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:key]
                                             style:style
                                            target:self
                                            action:@selector(toggleEditing)];
}

- (void)toggleEditing {
    [self setEditing:![self isEditing] animated:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    BOOL wasEditing = [self isEditing];
    if (editing && !wasEditing) {
        [[self tableView] setEditing:NO animated:NO];
    }

    [super setEditing:editing animated:animated];
    [[self tableView] setEditing:editing animated:animated];
    [[self navigationItem] setRightBarButtonItem:[self editDoneButton] animated:animated];
    if (!editing) {
        [[self selectedJumpUUIDs] removeAllObjects];
    }
    [self updateToolbarItems];
}

- (void)updateToolbarItems {
    NSArray<UIBarButtonItem *> *toolbarItems = nil;
    if (![self isEditing]) {
        toolbarItems = [self isSearching] ? @[] : @[ [self toolbarFlexibleSpaceItem], [self addToolbarItem] ];
    } else {
        NSString *title = [self allDisplayedJumpsSelected] ? [self localizedStringForKey:@"Deselect All"]
                                                           : [self localizedStringForKey:@"Select All"];
        [[self selectToolbarItem] setTitle:title];
        [[self selectToolbarItem] setEnabled:[[self displayedJumps] count] > 0];
        [[self deleteToolbarItem] setEnabled:[[self selectedDisplayedJumpUUIDs] count] > 0];
        toolbarItems = @[ [self selectToolbarItem], [self toolbarFlexibleSpaceItem], [self deleteToolbarItem] ];
    }

    if (![[self toolbarItems] isEqualToArray:toolbarItems]) {
        [self setToolbarItems:toolbarItems animated:YES];
    }
}

- (void)addJump {
    if ([self isSearching]) {
        [[[self searchController] searchBar] setText:@""];
        [[self searchController] setActive:NO];
        [[self tableView] reloadData];
    }

    // 添加 flow: the type is chosen first (URL Scheme, 打开应用, 快捷方式);
    // nothing touches the store here — the action joins the list only when
    // the editor's 完成 reports the finished entry, so backing out of the
    // editor never leaves a half-configured row behind.
    UIAlertController *chooser = [UIAlertController alertControllerWithTitle:[self localizedStringForKey:@"Choose Action Type"]
                                                                      message:nil
                                                               preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *type in @[ kKayokoCustomJumpTypeURLScheme, kKayokoCustomJumpTypeOpenApp, kKayokoCustomJumpTypeShortcut ]) {
        NSString *displayName = [type isEqualToString:kKayokoCustomJumpTypeURLScheme] ? [self localizedStringForKey:@"URL Scheme"]
            : [type isEqualToString:kKayokoCustomJumpTypeOpenApp]   ? [self localizedStringForKey:@"Open App"]
                                                                    : [self localizedStringForKey:@"Shortcut"];
        [chooser addAction:[UIAlertAction actionWithTitle:displayName
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(__unused UIAlertAction *action) {
                                                    [self presentEditorForNewJumpWithType:type];
                                                  }]];
    }
    [chooser addAction:[UIAlertAction actionWithTitle:[self localizedStringForKey:@"Cancel"]
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [self presentViewController:chooser animated:YES completion:nil];
}

- (void)presentEditorForNewJumpWithType:(NSString *)type {
    KayokoCustomJump *jump = [[KayokoCustomJump alloc] initWithUUID:[[NSUUID UUID] UUIDString]
                                                              title:@""
                                                               link:@""
                                                               icon:nil
                                                               type:type
                                                       shortcutType:nil];
    KayokoCustomJumpEditorViewController *editor =
        [[KayokoCustomJumpEditorViewController alloc] initWithJump:jump
                                                 localizationBundle:[self localizationBundle]
                                                     isImageAction:[[self class] isImageActionManagement]];
    __weak typeof(self) weakSelf = self;
    [editor setCompletionHandler:^(KayokoCustomJump *updatedJump) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      NSMutableArray<KayokoCustomJump *> *updatedJumps = [[strongSelf jumps] mutableCopy];
      [updatedJumps addObject:updatedJump];
      if (![strongSelf saveJumps:updatedJumps]) {
          return;
      }
      [[strongSelf jumps] addObject:updatedJump];
      [strongSelf updatePlaceholderVisibility];
      NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)([[strongSelf jumps] count] - 1) inSection:0];
      [[strongSelf tableView] insertRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
      [[strongSelf tableView] scrollToRowAtIndexPath:indexPath
                                    atScrollPosition:UITableViewScrollPositionMiddle
                                           animated:YES];
    }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:editor];
    [navigationController setModalPresentationStyle:UIModalPresentationPageSheet];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (BOOL)deleteJumpAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<KayokoCustomJump *> *displayedJumps = [self displayedJumps];
    NSUInteger displayedIndex = (NSUInteger)[indexPath row];
    if (displayedIndex >= [displayedJumps count]) {
        return NO;
    }

    KayokoCustomJump *deletedJump = displayedJumps[displayedIndex];
    NSUInteger actualIndex = [self indexOfJumpWithUUID:[deletedJump uuid] inJumps:[self jumps]];
    if (actualIndex == NSNotFound) {
        return NO;
    }

    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[self jumps] mutableCopy];
    [updatedJumps removeObjectAtIndex:actualIndex];
    if (![self saveJumps:updatedJumps]) {
        return NO;
    }

    [[self jumps] removeObjectAtIndex:actualIndex];
    [[self selectedJumpUUIDs] removeObject:[deletedJump uuid]];
    [self refreshFilteredJumps];
    [self updatePlaceholderVisibility];
    [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updateToolbarItems];
    return YES;
}

- (void)toggleSelectAll {
    NSArray<KayokoCustomJump *> *displayedJumps = [self displayedJumps];
    if ([displayedJumps count] == 0) {
        return;
    }

    BOOL shouldDeselect = [self allDisplayedJumpsSelected];
    for (NSUInteger index = 0; index < [displayedJumps count]; index++) {
        KayokoCustomJump *jump = displayedJumps[index];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        if (shouldDeselect) {
            [[self selectedJumpUUIDs] removeObject:[jump uuid]];
            [[self tableView] deselectRowAtIndexPath:indexPath animated:YES];
        } else {
            [[self selectedJumpUUIDs] addObject:[jump uuid]];
            [[self tableView] selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
        }
    }
    [self updateToolbarItems];
}

- (void)deleteSelectedJumps {
    NSSet<NSString *> *selectedUUIDs = [self selectedDisplayedJumpUUIDs];
    if ([selectedUUIDs count] == 0) {
        return;
    }

    NSArray<KayokoCustomJump *> *displayedJumpsBeforeDeletion = [[self displayedJumps] copy];
    NSMutableArray<NSIndexPath *> *deletedIndexPaths = [[NSMutableArray alloc] init];
    for (NSUInteger index = 0; index < [displayedJumpsBeforeDeletion count]; index++) {
        if ([selectedUUIDs containsObject:[displayedJumpsBeforeDeletion[index] uuid]]) {
            [deletedIndexPaths addObject:[NSIndexPath indexPathForRow:index inSection:0]];
        }
    }

    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[NSMutableArray alloc] init];
    for (KayokoCustomJump *jump in [self jumps]) {
        if (![selectedUUIDs containsObject:[jump uuid]]) {
            [updatedJumps addObject:jump];
        }
    }
    if (![self saveJumps:updatedJumps]) {
        return;
    }

    [self setJumps:updatedJumps];
    [[self selectedJumpUUIDs] minusSet:selectedUUIDs];
    [self refreshFilteredJumps];
    [self updatePlaceholderVisibility];
    if ([deletedIndexPaths count] > 0) {
        [[self tableView] deleteRowsAtIndexPaths:deletedIndexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self updateToolbarItems];
}

- (void)presentEditorForJump:(KayokoCustomJump *)jump {
    KayokoCustomJumpEditorViewController *editor =
        [[KayokoCustomJumpEditorViewController alloc] initWithJump:jump
                                                   localizationBundle:[self localizationBundle]
                                                       isImageAction:[[self class] isImageActionManagement]];
    __weak typeof(self) weakSelf = self;
    [editor setCompletionHandler:^(KayokoCustomJump *updatedJump) {
      [weakSelf updateJump:updatedJump];
    }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:editor];
    [navigationController setModalPresentationStyle:UIModalPresentationPageSheet];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)updateJump:(KayokoCustomJump *)updatedJump {
    NSUInteger index = [self indexOfJumpWithUUID:[updatedJump uuid] inJumps:[self jumps]];
    if (index == NSNotFound) {
        return;
    }

    NSArray<KayokoCustomJump *> *displayedJumpsBeforeUpdate = [[self displayedJumps] copy];
    NSUInteger visibleIndexBeforeUpdate = [self indexOfJumpWithUUID:[updatedJump uuid] inJumps:displayedJumpsBeforeUpdate];

    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[self jumps] mutableCopy];
    updatedJumps[index] = updatedJump;
    if (![self saveJumps:updatedJumps]) {
        return;
    }

    [self setJumps:updatedJumps];
    [self refreshFilteredJumps];
    [self updatePlaceholderVisibility];

    if (visibleIndexBeforeUpdate == NSNotFound) {
        return;
    }

    NSUInteger visibleIndexAfterUpdate = [self indexOfJumpWithUUID:[updatedJump uuid] inJumps:[self displayedJumps]];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:visibleIndexBeforeUpdate inSection:0];
    if (visibleIndexAfterUpdate == NSNotFound) {
        if ((NSInteger)[indexPath row] < [[self tableView] numberOfRowsInSection:0]) {
            [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        return;
    }

    NSIndexPath *updatedIndexPath = [NSIndexPath indexPathForRow:visibleIndexAfterUpdate inSection:0];
    KayokoCustomJumpTableViewCell *cell =
        (KayokoCustomJumpTableViewCell *)[[self tableView] cellForRowAtIndexPath:updatedIndexPath];
    if ([cell isKindOfClass:[KayokoCustomJumpTableViewCell class]]) {
        [cell configureWithJump:updatedJump editing:[self isEditing]];
    }
}

- (NSArray<KayokoCustomJump *> *)displayedJumps {
    return [self isFiltering] ? [self filteredJumps] : [self jumps];
}

- (BOOL)allDisplayedJumpsSelected {
    NSArray<KayokoCustomJump *> *displayedJumps = [self displayedJumps];
    if ([displayedJumps count] == 0) {
        return NO;
    }
    for (KayokoCustomJump *jump in displayedJumps) {
        if (![[self selectedJumpUUIDs] containsObject:[jump uuid]]) {
            return NO;
        }
    }
    return YES;
}

- (NSSet<NSString *> *)selectedDisplayedJumpUUIDs {
    NSMutableSet<NSString *> *selectedUUIDs = [[NSMutableSet alloc] init];
    for (KayokoCustomJump *jump in [self displayedJumps]) {
        if ([[self selectedJumpUUIDs] containsObject:[jump uuid]]) {
            [selectedUUIDs addObject:[jump uuid]];
        }
    }
    return [selectedUUIDs copy];
}

- (BOOL)isFiltering {
    return [[self normalizedSearchText] length] > 0;
}

- (BOOL)isSearching {
    return [self isSearchInterfaceActive] || [self isFiltering];
}

- (void)refreshFilteredJumps {
    [[self filteredJumps] removeAllObjects];
    NSString *searchText = [self normalizedSearchText];
    if ([searchText length] == 0) {
        return;
    }

    for (KayokoCustomJump *jump in [self jumps]) {
        BOOL matchesTitle = [[jump title] rangeOfString:searchText options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch]
                                                  .location != NSNotFound;
        BOOL matchesLink = [[jump link] rangeOfString:searchText options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch]
                                                 .location != NSNotFound;
        if (matchesTitle || matchesLink) {
            [[self filteredJumps] addObject:jump];
        }
    }
}

- (NSUInteger)indexOfJumpWithUUID:(NSString *)uuid inJumps:(NSArray<KayokoCustomJump *> *)jumps {
    for (NSUInteger index = 0; index < [jumps count]; index++) {
        if ([[jumps[index] uuid] isEqualToString:uuid]) {
            return index;
        }
    }
    return NSNotFound;
}

- (BOOL)saveJumps:(NSArray<KayokoCustomJump *> *)jumps {
    NSError *error = nil;
    if ([[self jumpStore] saveJumps:jumps error:&error]) {
        return YES;
    }
    [self presentError:error];
    return NO;
}

- (NSString *)normalizedSearchText {
    NSString *text = [[[[self searchController] searchBar] text]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return text ?: @"";
}

- (void)updatePlaceholderVisibility {
    BOOL noResults = [self isFiltering] && [[self jumps] count] > 0 && [[self filteredJumps] count] == 0;
    BOOL shouldShow = [[self jumps] count] == 0 || noResults;
    UIView *footerView = [[self tableView] tableFooterView];
    if (!shouldShow) {
        if (footerView == [self placeholderView]) {
            [[self tableView] setTableFooterView:nil];
        }
        return;
    }

    if (footerView != [self placeholderView]) {
        [[self tableView] setTableFooterView:[self placeholderView]];
    }
    NSString *emptyKey = noResults ? @"No Search Results"
                                   : ([[self class] isImageActionManagement] ? @"No Image Actions" : @"No Custom Jumps");
    [[self placeholderView] setMessage:[self localizedStringForKey:emptyKey]];
    [self updatePlaceholderLayout];
}

- (void)updatePlaceholderLayout {
    if ([self isUpdatingPlaceholderLayout] || [[self tableView] tableFooterView] != [self placeholderView]) {
        return;
    }

    CGFloat availableHeight = CGRectGetHeight([[self tableView] bounds]) -
                              MAX([[self tableView] adjustedContentInset].top - [[self tableView] contentInset].top, 0.0) -
                              MAX([[self tableView] adjustedContentInset].bottom - [[self tableView] contentInset].bottom, 0.0) -
                              [self keyboardBottomInset];
    CGRect targetFrame = CGRectMake(0.0, 0.0, CGRectGetWidth([[self tableView] bounds]),
                                    floor(MAX(availableHeight, kKayokoCustomJumpPlaceholderMinimumHeight)));
    if (CGRectEqualToRect([[self placeholderView] frame], targetFrame)) {
        return;
    }

    [self setUpdatingPlaceholderLayout:YES];
    [[self placeholderView] setFrame:targetFrame];
    [[self tableView] setTableFooterView:[self placeholderView]];
    [self setUpdatingPlaceholderLayout:NO];
}

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

- (void)presentError:(NSError *)error {
    NSString *titleKey = [[self class] isImageActionManagement] ? @"Image Actions" : @"Custom Jumps";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self localizedStringForKey:titleKey]
                                                                    message:[error localizedDescription]
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self localizedStringForKey:@"OK"]
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)[[self displayedJumps] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    KayokoCustomJumpTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kKayokoCustomJumpCellReuseIdentifier
                                                                            forIndexPath:indexPath];
    [cell configureWithJump:[self displayedJumps][(NSUInteger)[indexPath row]] editing:[self isEditing]];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [self isEditing] ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (editingStyle == UITableViewCellEditingStyleDelete && ![self isEditing]) {
        [self deleteJumpAtIndexPath:indexPath];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [self isEditing] && ![self isSearching];
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    if ([self isSearching] || [sourceIndexPath row] == [destinationIndexPath row]) {
        return;
    }

    NSUInteger sourceIndex = (NSUInteger)[sourceIndexPath row];
    NSUInteger destinationIndex = (NSUInteger)[destinationIndexPath row];
    if (sourceIndex >= [[self jumps] count] || destinationIndex >= [[self jumps] count]) {
        return;
    }

    NSMutableArray<KayokoCustomJump *> *updatedJumps = [[self jumps] mutableCopy];
    KayokoCustomJump *jump = updatedJumps[sourceIndex];
    [updatedJumps removeObjectAtIndex:sourceIndex];
    [updatedJumps insertObject:jump atIndex:destinationIndex];
    if (![self saveJumps:updatedJumps]) {
        [tableView moveRowAtIndexPath:destinationIndexPath toIndexPath:sourceIndexPath];
        return;
    }
    [self setJumps:updatedJumps];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    KayokoCustomJump *jump = [self displayedJumps][(NSUInteger)[indexPath row]];
    if ([self isEditing]) {
        [[self selectedJumpUUIDs] addObject:[jump uuid]];
        [self updateToolbarItems];
        return;
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self presentEditorForJump:jump];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self isEditing] || (NSUInteger)[indexPath row] >= [[self displayedJumps] count]) {
        return;
    }
    KayokoCustomJump *jump = [self displayedJumps][(NSUInteger)[indexPath row]];
    [[self selectedJumpUUIDs] removeObject:[jump uuid]];
    [self updateToolbarItems];
}

- (BOOL)tableView:(UITableView *)tableView shouldBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return (NSUInteger)[indexPath row] < [[self displayedJumps] count];
}

- (void)tableView:(UITableView *)tableView didBeginMultipleSelectionInteractionAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if (![self isEditing]) {
        [self setEditing:YES animated:YES];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ([self isEditing]) {
        return nil;
    }
    UIContextualAction *deleteAction =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                title:[self localizedStringForKey:@"Delete"]
                                              handler:^(__kindof UIContextualAction *action,
                                                        __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
                                                (void)action;
                                                (void)sourceView;
                                                completionHandler([self deleteJumpAtIndexPath:indexPath]);
                                              }];
    [deleteAction setImage:[UIImage systemImageNamed:@"trash.fill"]];
    return [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self refreshFilteredJumps];
    [[self tableView] reloadData];
    [self updatePlaceholderVisibility];
    [self syncDisplayedSelectionState];
    [self updateToolbarItems];
}

- (void)willPresentSearchController:(UISearchController *)searchController {
    (void)searchController;
    BOOL wasSearching = [self isSearching];
    [self setSearchInterfaceActive:YES];
    [self reloadTableForSearchStateChangeFromSearching:wasSearching];
    [self updatePlaceholderVisibility];
    [self updateToolbarItems];
}

- (void)didDismissSearchController:(UISearchController *)searchController {
    (void)searchController;
    BOOL wasSearching = [self isSearching];
    [self setSearchInterfaceActive:NO];
    [self reloadTableForSearchStateChangeFromSearching:wasSearching];
    [self updatePlaceholderVisibility];
    [self updateToolbarItems];
}

- (void)reloadTableForSearchStateChangeFromSearching:(BOOL)wasSearching {
    if (![self isEditing] || wasSearching == [self isSearching]) {
        return;
    }

    [[self tableView] reloadData];
    [self syncDisplayedSelectionState];
}

- (void)syncDisplayedSelectionState {
    if (![self isEditing]) {
        return;
    }

    NSArray<KayokoCustomJump *> *displayedJumps = [self displayedJumps];
    NSSet<NSIndexPath *> *selectedIndexPaths =
        [NSSet setWithArray:[[self tableView] indexPathsForSelectedRows] ?: @[]];
    for (NSUInteger index = 0; index < [displayedJumps count]; index++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
        BOOL shouldSelect = [[self selectedJumpUUIDs] containsObject:[displayedJumps[index] uuid]];
        BOOL isSelected = [selectedIndexPaths containsObject:indexPath];
        if (shouldSelect == isSelected) {
            continue;
        }

        if (shouldSelect) {
            [[self tableView] selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        } else {
            [[self tableView] deselectRowAtIndexPath:indexPath animated:NO];
        }
    }
}

@end
