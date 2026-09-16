//
//  KayokoAppInfo.m
//  Kayoko
//

#import "KayokoAppInfo.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Not in the SDK; loaded lazily from MobileCoreServices/CoreServices.
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *localizedName;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
// Two synchronous passes (system = 0, user = 1) matching the reference
// implementation; allInstalledApplications: can block while LaunchServices
// is cold.
- (void)enumerateApplicationsOfType:(NSUInteger)type block:(void (^)(LSApplicationProxy *proxy))block;
@end

@interface UIImage (KayokoAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSInteger)format;
@end

#pragma clang diagnostic pop

@implementation KayokoAppInfo

+ (void)ensureLaunchServicesLoaded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Settings on iOS 17 normally has LaunchServices loaded already;
        // iOS 16 does not. Keep both framework locations for compatibility.
        for (NSString *path in @[
            @"/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
            @"/System/Library/Frameworks/CoreServices.framework/CoreServices",
        ]) {
            if (dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL)) break;
        }
    });
}

+ (Class)appProxyClass {
    [self ensureLaunchServicesLoaded];
    return NSClassFromString(@"LSApplicationProxy");
}

+ (NSArray<LSApplicationProxy *> *)installedAppProxies {
    [self ensureLaunchServicesLoaded];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        return @[];
    }
    @try {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        if (!workspace) {
            return @[];
        }

        SEL enumerateSelector = @selector(enumerateApplicationsOfType:block:);
        if ([workspace respondsToSelector:enumerateSelector]) {
            Class proxyClass = [self appProxyClass];
            NSMutableArray *enumerated = [NSMutableArray array];
            BOOL threw = NO;
            @try {
                for (NSUInteger type = 0; type <= 1; type++) {
                    ((void (*)(id, SEL, NSUInteger, void (^)(LSApplicationProxy *)))objc_msgSend)(
                        workspace, enumerateSelector, type, ^(LSApplicationProxy *proxy) {
                            if (!proxyClass || [proxy isKindOfClass:proxyClass]) [enumerated addObject:proxy];
                        });
                }
            } @catch (NSException *exception) {
                NSLog(@"[Kayoko] app enumeration failed (%@)", exception);
                threw = YES;
            }
            if (!threw && [enumerated count] > 0) {
                return enumerated;
            }
        }
        return @[];
    } @catch (NSException *exception) {
        NSLog(@"[Kayoko] app enumeration failed (%@)", exception);
        return @[];
    }
}

+ (NSString *)bundleIDForProxy:(LSApplicationProxy *)proxy {
    NSString *bundleID = nil;
    @try {
        if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
            bundleID = [proxy applicationIdentifier];
        }
        if (![bundleID isKindOfClass:[NSString class]] || [bundleID length] == 0) {
            bundleID = [proxy respondsToSelector:@selector(bundleIdentifier)] ? [proxy bundleIdentifier] : nil;
        }
    } @catch (__unused NSException *exception) {
        bundleID = nil;
    }
    if ([bundleID isKindOfClass:[NSString class]] && [bundleID length] > 0) return bundleID;
    return nil;
}

+ (NSString *)localizedNameForProxy:(LSApplicationProxy *)proxy {
    NSString *name = nil;
    @try {
        if ([proxy respondsToSelector:@selector(localizedName)]) {
            name = [proxy localizedName];
        }
    } @catch (__unused NSException *exception) {
        name = nil;
    }
    return [name isKindOfClass:[NSString class]] && [name length] > 0 ? name : nil;
}

+ (NSArray<KayokoAppInfo *> *)installedApps {
    NSMutableArray<KayokoAppInfo *> *apps = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    Class proxyClass = [self appProxyClass];
    for (LSApplicationProxy *proxy in [self installedAppProxies]) {
        if (proxyClass && ![proxy isKindOfClass:proxyClass]) continue;
        if (![proxy respondsToSelector:@selector(applicationIdentifier)] &&
            ![proxy respondsToSelector:@selector(bundleIdentifier)]) {
            continue;
        }
        NSString *bundleID = [self bundleIDForProxy:proxy];
        NSString *name = [self localizedNameForProxy:proxy] ?: bundleID;
        if ([bundleID length] == 0 || [seen containsObject:bundleID]) continue;
        [seen addObject:bundleID];

        KayokoAppInfo *app = [[KayokoAppInfo alloc] init];
        app->_bundleID = [bundleID copy];
        app->_name = [name copy];
        [apps addObject:app];
    }
    [apps sortUsingComparator:^NSComparisonResult(KayokoAppInfo *left, KayokoAppInfo *right) {
      return [[left name] localizedStandardCompare:[right name]];
    }];
    return apps;
}

+ (nullable instancetype)appWithBundleID:(NSString *)bundleID {
    if ([self isValidBundleIdentifier:bundleID]) {
        for (KayokoAppInfo *app in [self installedApps]) {
            if ([[app bundleID] isEqualToString:bundleID]) {
                return app;
            }
        }
    }
    return nil;
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      cache = [[NSCache alloc] init];
      [cache setCountLimit:512];
    });
    if ([bundleID length] == 0) {
        return [UIImage systemImageNamed:@"app"];
    }
    UIImage *cached = [cache objectForKey:bundleID];
    if (cached) {
        return cached;
    }

    CGFloat side = 44.0;
    UIImage *base = nil;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:)]) {
        base = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2];
        if (!base) {
            base = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0];
        }
    }

    UIImage *icon = nil;
    if (base) {
        UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
        [format setScale:[[UIScreen mainScreen] scale]];
        [format setOpaque:NO];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                                                                   format:format];
        icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
          // Home-screen icons are square; round them like SpringBoard does.
          [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, side, side)
                                      cornerRadius:side * 0.225] addClip];
          [base drawInRect:CGRectMake(0.0, 0.0, side, side)];
        }];
    } else {
        icon = [UIImage systemImageNamed:@"app"];
    }
    if (icon) {
        [cache setObject:icon forKey:bundleID];
    }
    return icon;
}

+ (BOOL)isValidBundleIdentifier:(NSString *)value {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return NO;
    if ([value length] > 512) return NO;
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:
            @"^[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?(?:\\.[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?)+$"
                             options:0
                               error:nil];
    return [expression firstMatchInString:value options:0 range:NSMakeRange(0.0, [value length])] != nil;
}

@end
