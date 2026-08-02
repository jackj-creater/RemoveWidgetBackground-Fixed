#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 递归清除所有子视图中的硬编码背景色与毛玻璃遮罩
static void safeCleanWidgetBackground(UIView *view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    
    NSString *className = NSStringFromClass([view class]);
    
    // 隐藏系统级与第三方毛玻璃层
    if ([className containsString:@"VisualEffect"] || [className containsString:@"MTMaterialView"]) {
        view.hidden = YES;
        return;
    }
    
    // 清除微博等第三方 App 在 View 内部硬编码的背景色
    if (![className hasPrefix:@"_UI"]) {
        if (view.backgroundColor && ![view.backgroundColor isEqual:[UIColor clearColor]]) {
            view.backgroundColor = [UIColor clearColor];
        }
    }
    
    // 安全递归
    NSArray *subviews = [view.subviews copy];
    for (UIView *subview in subviews) {
        safeCleanWidgetBackground(subview);
    }
}

// ---------------- SBHWidgetContainerView Swizzling ----------------

static void (*orig_SBHWidgetContainerView_layoutSubviews)(id self, SEL _cmd);
static void custom_SBHWidgetContainerView_layoutSubviews(id self, SEL _cmd) {
    // 调用原方法
    if (orig_SBHWidgetContainerView_layoutSubviews) {
        orig_SBHWidgetContainerView_layoutSubviews(self, _cmd);
    }
    
    UIView *selfView = (UIView *)self;
    if (!selfView) return;
    
    // 安全获取 _materialView，防止 Exception 崩溃
    @try {
        Ivar ivar = class_getInstanceVariable([selfView class], "_materialView");
        if (ivar) {
            UIView *materialView = object_getIvar(selfView, ivar);
            if (materialView && [materialView isKindOfClass:[UIView class]]) {
                materialView.hidden = YES;
            }
        }
    } @catch (NSException *exception) {}
    
    // 清理微博等第三方 App 内部背景
    safeCleanWidgetBackground(selfView);
}

// ---------------- UIViewController Swizzling (修复暗色模式) ----------------

static void (*orig_UIViewController_viewDidLoad)(id self, SEL _cmd);
static void custom_UIViewController_viewDidLoad(id self, SEL _cmd) {
    if (orig_UIViewController_viewDidLoad) {
        orig_UIViewController_viewDidLoad(self, _cmd);
    }
    
    if ([NSStringFromClass([self class]) isEqualToString:@"CHUISWidgetHostViewController"]) {
        if ([self respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
            typedef void (*SetStyleFunc)(id, SEL, NSInteger);
            SetStyleFunc setStyle = (SetStyleFunc)[self methodForSelector:@selector(setOverrideUserInterfaceStyle:)];
            if (setStyle) {
                setStyle(self, @selector(setOverrideUserInterfaceStyle:), 0); // 0 = UIUserInterfaceStyleUnspecified
            }
        }
    }
}

// ---------------- 构造函数动态 Hook ----------------

__attribute__((constructor)) static void initTweak(void) {
    @autoreleasepool {
        // 1. Hook SBHWidgetContainerView 的 layoutSubviews
        Class sbhClass = NSClassFromString(@"SBHWidgetContainerView");
        if (sbhClass) {
            Method origMethod = class_getInstanceMethod(sbhClass, @selector(layoutSubviews));
            if (origMethod) {
                orig_SBHWidgetContainerView_layoutSubviews = (void (*)(id, SEL))method_getImplementation(origMethod);
                method_setImplementation(origMethod, (IMP)custom_SBHWidgetContainerView_layoutSubviews);
            }
        }
        
        // 2. Hook UIViewController 的 viewDidLoad
        Class vcClass = [UIViewController class];
        if (vcClass) {
            Method origMethod = class_getInstanceMethod(vcClass, @selector(viewDidLoad));
            if (origMethod) {
                orig_UIViewController_viewDidLoad = (void (*)(id, SEL))method_getImplementation(origMethod);
                method_setImplementation(origMethod, (IMP)custom_UIViewController_viewDidLoad);
            }
        }
    }
}
