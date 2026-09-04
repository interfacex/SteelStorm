import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'SteelStorm', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(0x0000, 'SteelStorm', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'SteelStorm', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      // 全屏 + 常亮，提升游戏沉浸感
      const win = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true);
      win.setWindowKeepScreenOn(true);
      // 隐藏状态栏/导航栏：去掉底部常驻手势条，避免它拦截贴边按钮的点击
      win.setWindowSystemBarEnable([]).catch((): void => {
      });
      // 记录系统安全区（手势条高度等）供页面避让
      this.updateInsets(win);
      try {
        win.on('avoidAreaChange', (): void => {
          this.updateInsets(win);
        });
      } catch (e) {
      }
    });
  }

  private updateInsets(win: window.Window): void {
    const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    AppStorage.setOrCreate<number>('navBottomPx', Math.max(nav.bottomRect.height, sys.bottomRect.height));
    AppStorage.setOrCreate<number>('navRightPx', Math.max(nav.rightRect.width, sys.rightRect.width));
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'SteelStorm', 'WindowStage onDestroy');
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
