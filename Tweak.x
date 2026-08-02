#import <UIKit/UIKit.h>

// 递归清除所有子视图中的硬编码背景色与毛玻璃遮罩
static void cleanWidgetBackground(UIView *view) {
    if (!view) return;

    // 隐藏系统级与第三方毛玻璃层
    if ([view isKindOfClass:NSClassFromString(@"_UIVisualEffectView")] || 
        [view isKindOfClass:NSClassFromString(@"MTMaterialView")]) {
        view.hidden = YES;
        view.alpha = 0.0;
    }

    // 清除微博等第三方 App 在 View 内部硬编码的背景色
    if (view.backgroundColor && ![view.backgroundColor isEqual:[UIColor clearColor]]) {
        view.backgroundColor = [UIColor clearColor];
    }

    for (UIView *subview in view.subviews) {
        cleanWidgetBackground(subview);
    }
}

%hook SBHWidgetContainerView

- (void)layoutSubviews {
    %orig;

    // 隐藏系统外壳底板
    UIView *materialView = [self valueForKey:@"_materialView"];
    if (materialView) {
        materialView.hidden = YES;
    }

    // 清除组件内部自绘背景
    cleanWidgetBackground(self);
}

%end

// 修复负一屏丢失底板后触发的系统暗色模式错乱
%hook CHUISWidgetHostViewController

- (void)viewDidLoad {
    %orig;

    if ([self respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    }
}

%end
