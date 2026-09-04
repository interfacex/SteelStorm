// ============ 战史记录列表：展示最近对局，支持多选删除、点击进入回放 ============
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ReplayStore } from '../game/ReplayStore';
import { ReplayMeta, fmtDur } from '../game/Replay';
import { Team } from '../game/Config';

@Entry
@Component
struct History {
  @State metas: ReplayMeta[] = [];
  @State selecting: boolean = false;
  @State selected: number[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.metas = ReplayStore.list(ctx);
    this.selected = [];
  }

  private toggleSel(id: number): void {
    const next = this.selected.slice();
    const i = next.indexOf(id);
    if (i >= 0) {
      next.splice(i, 1);
    } else {
      next.push(id);
    }
    this.selected = next;
  }

  private deleteSelected(): void {
    if (this.selected.length === 0) {
      return;
    }
    AlertDialog.show({
      title: '删除记录',
      message: '确定删除所选 ' + this.selected.length + ' 条回放？',
      autoCancel: true,
      primaryButton: {
        value: '删除',
        fontColor: '#ff7a6e',
        action: () => {
          const ctx = getContext(this) as common.UIAbilityContext;
          ReplayStore.deleteMany(ctx, this.selected);
          this.selecting = false;
          this.reload();
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  @Builder
  recordItem(m: ReplayMeta) {
    Row() {
      if (this.selecting) {
        Text(this.selected.indexOf(m.id) >= 0 ? '☑' : '☐')
          .fontSize(20)
          .fontColor('#cfe2ff')
          .margin({ right: 10 })
      }
      Column() {
        Text(m.winner === Team.PLAYER ? '胜利' : '战败')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(m.winner === Team.PLAYER ? '#7fffb0' : '#ff7a6e')
        Text(m.date)
          .fontSize(12)
          .fontColor('#b9c4a0')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('时长 ' + fmtDur(m.durSec))
        .fontSize(12)
        .fontColor('#a7b585')
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#2a3324')
    .border({ width: 1, color: '#3a4530' })
    .onClick(() => {
      if (this.selecting) {
        this.toggleSel(m.id);
      } else {
        const params: Record<string, number> = { 'id': m.id };
        router.pushUrl({ url: 'pages/Replay', params: params });
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('返回')
          .fontSize(14)
          .fontColor('#cfe2ff')
          .padding(10)
          .onClick(() => {
            router.back();
          })
        Blank()
        Text('战史记录')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#f0e6bd')
        Blank()
        Text(this.selecting ? '完成' : '多选')
          .fontSize(14)
          .fontColor('#cfe2ff')
          .padding(10)
          .onClick(() => {
            this.selecting = !this.selecting;
            this.selected = [];
          })
      }
      .width('100%')
      .height(46)
      .backgroundColor('#2c2b20')
      .border({ width: { bottom: 1 }, color: { bottom: '#5a5340' } })

      if (this.metas.length === 0) {
        Column() {
          Text('暂无对局记录')
            .fontSize(14)
            .fontColor('#8a8064')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.metas, (m: ReplayMeta) => {
            ListItem() {
              this.recordItem(m)
            }
          }, (m: ReplayMeta) => 'r' + m.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .scrollBar(BarState.Off)
      }

      if (this.selecting) {
        Button('删除所选 (' + this.selected.length + ')')
          .width('90%')
          .height(42)
          .margin({ top: 6, bottom: 22 })
          .fontColor('#ffd6cc')
          .backgroundColor(this.selected.length > 0 ? '#5a2b26' : '#3a3a32')
          .enabled(this.selected.length > 0)
          .onClick(() => {
            this.deleteSelected();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1b1c14')
  }
}
