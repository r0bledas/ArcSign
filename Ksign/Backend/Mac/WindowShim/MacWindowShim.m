//
//  MacWindowShim.m
//  ArcSign Window Mode, Aspect Ratio & Scale Shim for MacCatalyst Apps
//
//  Reads `ArcSignWindowMode` ("iphone" | "ipad" | "desktop") and `ArcSignWindowScale` (number)
//  from Info.plist and configures UIWindowScene.sizeRestrictions + NSWindow aspectRatio/frame.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *ASWindowMode(void) {
    id val = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ArcSignWindowMode"];
    return [val isKindOfClass:[NSString class]] ? (NSString *)val : @"iphone";
}

static CGFloat ASWindowScale(void) {
    id val = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ArcSignWindowScale"];
    if ([val respondsToSelector:@selector(doubleValue)]) {
        CGFloat s = (CGFloat)[val doubleValue];
        if (s >= 0.5 && s <= 2.0) return s;
    }
    return 1.0;
}

static void ASApplyToScene(id scene) {
    if (!scene) return;

    NSString *mode = ASWindowMode();
    CGFloat scale = ASWindowScale();

    CGSize targetSize;
    CGSize minSize;
    CGSize maxSize;
    BOOL lockAspect = NO;
    CGSize aspect = CGSizeZero;

    if ([mode isEqualToString:@"ipad"]) {
        targetSize = CGSizeMake(round(1024.0 * scale), round(768.0 * scale));
        minSize = CGSizeMake(640, 480);
        maxSize = CGSizeMake(2048, 1536);
        lockAspect = YES;
        aspect = CGSizeMake(4, 3);
    } else if ([mode isEqualToString:@"desktop"]) {
        targetSize = CGSizeMake(round(1100.0 * scale), round(760.0 * scale));
        minSize = CGSizeMake(420, 420);
        maxSize = CGSizeMake(3840, 2400);
    } else {
        // Default: iPhone Portrait (9:16)
        targetSize = CGSizeMake(round(430.0 * scale), round(932.0 * scale));
        minSize = CGSizeMake(320, 568);
        maxSize = CGSizeMake(860, 1864);
        lockAspect = YES;
        aspect = CGSizeMake(9, 19.5);
    }

    if ([scene respondsToSelector:@selector(sizeRestrictions)]) {
        id restrictions = ((id (*)(id, SEL))objc_msgSend)(scene, NSSelectorFromString(@"sizeRestrictions"));
        if (restrictions) {
            if ([restrictions respondsToSelector:@selector(setMinimumSize:)]) {
                ((void (*)(id, SEL, CGSize))objc_msgSend)(restrictions, NSSelectorFromString(@"setMinimumSize:"), minSize);
            }
            if ([restrictions respondsToSelector:@selector(setMaximumSize:)]) {
                ((void (*)(id, SEL, CGSize))objc_msgSend)(restrictions, NSSelectorFromString(@"setMaximumSize:"), maxSize);
            }
        }
    }

    // Clamp target height to main UIScreen bounds if available
    Class uiScreenCls = NSClassFromString(@"UIScreen");
    if (uiScreenCls) {
        id mainScreen = ((id (*)(id, SEL))objc_msgSend)(uiScreenCls, NSSelectorFromString(@"mainScreen"));
        if (mainScreen && [mainScreen respondsToSelector:@selector(bounds)]) {
            CGRect b = ((CGRect (*)(id, SEL))objc_msgSend)(mainScreen, NSSelectorFromString(@"bounds"));
            if (b.size.height > 200 && targetSize.height > b.size.height * 0.90) {
                CGFloat ratio = (b.size.height * 0.90) / targetSize.height;
                targetSize.height = round(targetSize.height * ratio);
                targetSize.width = round(targetSize.width * ratio);
            }
        }
    }

    // Configure underlying NSWindow aspectRatio / size / center via ObjC runtime
    Class nsAppCls = NSClassFromString(@"NSApplication");
    if (nsAppCls) {
        id sharedApp = ((id (*)(id, SEL))objc_msgSend)(nsAppCls, NSSelectorFromString(@"sharedApplication"));
        NSArray *windows = ((id (*)(id, SEL))objc_msgSend)(sharedApp, NSSelectorFromString(@"windows"));
        for (id nsWin in windows) {
            if (lockAspect && [nsWin respondsToSelector:@selector(setContentAspectRatio:)]) {
                ((void (*)(id, SEL, CGSize))objc_msgSend)(nsWin, NSSelectorFromString(@"setContentAspectRatio:"), aspect);
            }
            if ([nsWin respondsToSelector:@selector(setContentSize:)]) {
                ((void (*)(id, SEL, CGSize))objc_msgSend)(nsWin, NSSelectorFromString(@"setContentSize:"), targetSize);
            }
            if ([nsWin respondsToSelector:@selector(center)]) {
                ((void (*)(id, SEL))objc_msgSend)(nsWin, NSSelectorFromString(@"center"));
            }
        }
    }
}

__attribute__((constructor))
static void ASWindowShimInit(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:@"UISceneDidActivateNotification"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        id scene = note.object;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ASApplyToScene(scene);
        });
    }];
    [nc addObserverForName:@"UIWindowDidBecomeVisibleNotification"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        id win = note.object;
        if ([win respondsToSelector:@selector(windowScene)]) {
            id scene = ((id (*)(id, SEL))objc_msgSend)(win, NSSelectorFromString(@"windowScene"));
            ASApplyToScene(scene);
        }
    }];
}
