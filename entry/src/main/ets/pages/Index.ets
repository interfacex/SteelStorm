// ============ 主页面：Canvas 战场 + 触控交互 + RA2式侧边栏 ============
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Recorder } from '../game/Replay';
import { ReplayStore } from '../game/ReplayStore';
import {
  Team, BType, BSPECS, USPECS, BUILD_LIST, UNIT_LIST, TEAM_COLOR
} from '../game/Config';
import { Game } from '../game/Game';
import { Renderer } from '../game/Renderer';
import { Entity, Unit } from '../game/Entities';
import { Vec2 } from '../game/World';

const TICK_MS: number = 33;

@Entry
@Component
struct Index {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private game: Game = new Game();
  private renderer: Renderer = new Renderer();
  private recorder: Recorder = new Recorder();
  private savedThisGame: boolean = false;
  private selIds: number[] = [];
  private timer: number = -1;
  private lastT: number = 0;
  private uiT: number = 0;
  // 触控状态
  private touchX: number = 0;
  private touchY: number = 0;
  private downX: number = 0;
  private downY: number = 0;
  private dragging: boolean = false;
  private viewW: number = 0;
  private viewH: number = 0;
  // UI 状态（低频同步，避免每帧刷新组件树）
  @State money: number = 0;
  @State powerGen: number = 0;
  @State powerUse: number = 0;
  @State buildInfo: string = '';
  @State selCount: number = 0;
  @State placingName: string = '';
  @State overText: string = '';
  @State tab: number = 0; // 0=建筑 1=部队
  @State infQLen: number = 0;
  @State vehQLen: number = 0;
  // 系统安全区（px，由 EntryAbility 写入 AppStorage）：避免底部手势条吞掉按钮点击
  @StorageProp('navBottomPx') navBottomPx: number = 0;
  @StorageProp('navRightPx') navRightPx: number = 0;

  // 底部按钮的安全内边距：取系统手势条高度，并保底 22vp，确保按钮不贴屏幕边缘
  private bottomSafe(): number {
    return px2vp(this.navBottomPx) + 22;
  }

  private rightSafe(): number {
    return px2vp(this.navRightPx);
  }

  private exitGame(): void {
    AlertDialog.show({
      title: '退出游戏',
      message: '确定要退出《钢铁风暴》吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '退出',
        fontColor: '#ff7a6e',
        action: () => {
          const ctx = getContext(this) as common.UIAbilityContext;
          ctx.terminateSelf();
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
    }
  }

  private startLoop(): void {
    this.lastT = Date.now();
    this.timer = setInterval(() => {
      const now = Date.now();
      let dt = (now - this.lastT) / 1000;
      this.lastT = now;
      if (dt > 0.1) {
        dt = 0.1;
      }
      this.game.update(dt);
      this.recorder.tick(this.game, dt);
      this.syncGhost();
      this.renderer.draw(this.ctx, this.game, this.selIds, this.viewW, this.viewH);
      this.uiT += dt;
      if (this.uiT >= 0.2) {
        this.uiT = 0;
        this.uiSync();
      }
    }, TICK_MS);
  }

  private uiSync(): void {
    const p = this.game.ps[Team.PLAYER];
    this.money = Math.floor(p.money);
    const pw = this.game.power(Team.PLAYER);
    this.powerGen = pw.x;
    this.powerUse = pw.y;
    if (p.buildQ != null) {
      const item = p.buildQ;
      const pct = Math.floor((1 - item.remain / item.total) * 100);
      this.buildInfo = BSPECS[item.bt].name + ' ' + pct + '%';
    } else {
      this.buildInfo = '';
    }
    this.placingName = p.pending >= 0 ? BSPECS[p.pending].name : '';
    this.selIds = this.game.aliveIds(this.selIds);
    this.selCount = this.selIds.length;
    this.infQLen = p.infQ.length;
    this.vehQLen = p.vehQ.length;
    if (this.game.winner >= 0 && this.overText === '') {
      this.overText = this.game.winner === Team.PLAYER ? '胜利！敌方基地已被摧毁' : '战败：基地全毁';
    }
    // 对局结束：落盘回放（仅一次）
    if (this.game.winner >= 0 && !this.savedThisGame) {
      this.savedThisGame = true;
      if (this.recorder.hasData()) {
        const data = this.recorder.finalize(this.game);
        ReplayStore.save(getContext(this) as common.UIAbilityContext, data);
      }
    }
  }

  private syncGhost(): void {
    const p = this.game.ps[Team.PLAYER];
    if (p.pending >= 0) {
      this.renderer.ghost.active = true;
      this.renderer.ghost.bt = p.pending;
      const spec = BSPECS[p.pending];
      const wx = this.renderer.worldX(this.touchX, this.touchY);
      const wy = this.renderer.worldY(this.touchX, this.touchY);
      this.renderer.ghost.tx = Math.floor(wx - spec.w / 2);
      this.renderer.ghost.ty = Math.floor(wy - spec.h / 2);
      this.renderer.ghost.ok = this.game.canPlace(Team.PLAYER, p.pending, this.renderer.ghost.tx, this.renderer.ghost.ty);
    } else {
      this.renderer.ghost.active = false;
    }
  }

  private toast(msg: string): void {
    if (msg !== '') {
      promptAction.showToast({ message: msg, duration: 1500 });
    }
  }

  // ---------------- 触控 ----------------
  private onCanvasTouch(event: TouchEvent): void {
    if (event.touches.length === 0 && event.changedTouches.length === 0) {
      return;
    }
    const t = event.type === TouchType.Up ? event.changedTouches[0] : event.touches[0];
    const px = t.x;
    const py = t.y;
    if (event.type === TouchType.Down) {
      this.downX = px;
      this.downY = py;
      this.touchX = px;
      this.touchY = py;
      this.dragging = false;
    } else if (event.type === TouchType.Move) {
      if (!this.dragging && Math.hypot(px - this.downX, py - this.downY) > 12) {
        this.dragging = true;
      }
      if (this.dragging) {
        this.renderer.cam.ox += px - this.touchX;
        this.renderer.cam.oy += py - this.touchY;
        this.renderer.clampCam(this.viewW, this.viewH);
      }
      this.touchX = px;
      this.touchY = py;
    } else if (event.type === TouchType.Up) {
      if (!this.dragging) {
        this.handleTap(px, py);
      }
      this.dragging = false;
    }
  }

  private handleTap(px: number, py: number): void {
    if (this.overText !== '') {
      return;
    }
    // 1) 小地图跳转
    if (this.renderer.isMiniHit(px, py)) {
      const wx = this.renderer.miniToWorldX(px);
      const wy = this.renderer.miniToWorldY(py);
      this.renderer.centerOn(wx, wy, this.viewW, this.viewH);
      return;
    }
    const wx = this.renderer.worldX(px, py);
    const wy = this.renderer.worldY(px, py);
    // 2) 放置模式
    const p = this.game.ps[Team.PLAYER];
    if (p.pending >= 0) {
      const spec = BSPECS[p.pending];
      const tx = Math.floor(wx - spec.w / 2);
      const ty = Math.floor(wy - spec.h / 2);
      this.toast(this.game.tryPlacePending(tx, ty));
      return;
    }
    // 3) 选取 / 命令
    const ent: Entity | null = this.game.pickEntity(wx, wy);
    if (ent != null && ent.team === Team.PLAYER && ent instanceof Unit) {
      this.selIds = [ent.id];
      this.selCount = 1;
      return;
    }
    if (this.selIds.length > 0) {
      if (ent != null && ent.team === Team.ENEMY) {
        this.game.commandAttack(this.selIds, ent);
        return;
      }
      const tx = Math.floor(wx);
      const ty = Math.floor(wy);
      if (this.game.map.inBounds(tx, ty)) {
        this.game.commandMove(this.selIds, tx, ty);
      }
      return;
    }
  }

  private restart(): void {
    this.game = new Game();
    this.selIds = [];
    this.selCount = 0;
    this.overText = '';
    const c: Vec2 = this.game.baseCenter(Team.PLAYER);
    this.renderer.centerOn(c.x, c.y, this.viewW, this.viewH);
    this.recorder.start(this.game);
    this.savedThisGame = false;
    this.uiSync();
  }

  // ---------------- 侧边栏按钮 ----------------
  @Builder
  panelButton(label: string, sub: string, action: () => void) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor('#eaf0d6')
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
      Text(sub)
        .fontSize(10)
        .fontColor('#a7b585')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 6, bottom: 6, left: 8, right: 8 })
    .borderRadius(5)
    .backgroundColor('#33392a')
    .border({
      width: { top: 1, left: 1, right: 1, bottom: 2 },
      color: { top: '#5b6243', left: '#474d33', right: '#1d2014', bottom: '#13150b' }
    })
    .onClick(action)
  }

  build() {
    Row() {
      // ---------- 战场 ----------
      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.viewW = this.ctx.width;
            this.viewH = this.ctx.height;
            const c: Vec2 = this.game.baseCenter(Team.PLAYER);
            this.renderer.centerOn(c.x, c.y, this.viewW, this.viewH);
            this.recorder.start(this.game);
            this.savedThisGame = false;
            if (this.timer < 0) {
              this.startLoop();
            }
          })
          .onTouch((event: TouchEvent) => {
            this.onCanvasTouch(event);
          })
        // 顶栏
        Row() {
          Text('资金 ' + this.money)
            .fontSize(13)
            .fontColor('#ffd970')
            .margin({ left: 10 })
          Text('电力 ' + this.powerUse + '/' + this.powerGen)
            .fontSize(13)
            .fontColor(this.powerUse > this.powerGen ? '#ff6a5e' : '#7fd0ff')
            .margin({ left: 14 })
          if (this.buildInfo !== '') {
            Text('建造中: ' + this.buildInfo)
              .fontSize(12)
              .fontColor('#aef0b0')
              .margin({ left: 14 })
          }
          if (this.placingName !== '') {
            Text('点击地图放置: ' + this.placingName)
              .fontSize(12)
              .fontColor('#ffd970')
              .margin({ left: 14 })
          }
          Blank()
          if (this.selCount > 0) {
            Text('已选 ' + this.selCount)
              .fontSize(12)
              .fontColor('#9fe8b0')
              .margin({ right: 10 })
          }
          Text('记录')
            .fontSize(12)
            .fontColor('#dCEBFF')
            .backgroundColor('#2f4a63')
            .borderRadius(4)
            .padding({ left: 11, right: 11, top: 3, bottom: 3 })
            .margin({ right: 8 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/History' });
            })
          Text('退出')
            .fontSize(12)
            .fontColor('#ffd6cc')
            .backgroundColor('#5a2b26')
            .borderRadius(4)
            .padding({ left: 11, right: 11, top: 3, bottom: 3 })
            .margin({ right: 10 + this.rightSafe() })
            .onClick(() => {
              this.exitGame();
            })
        }
        .width('100%')
        .height(32)
        .backgroundColor('rgba(20,22,14,0.82)')
        .border({ width: { bottom: 1 }, color: { bottom: '#5a5340' } })
        // 结束遮罩
        if (this.overText !== '') {
          Column() {
            Text(this.overText)
              .fontSize(24)
              .fontColor(this.game.winner === Team.PLAYER ? '#7fffb0' : '#ff7a6e')
              .fontWeight(FontWeight.Bold)
            Row({ space: 14 }) {
              Button('再来一局')
                .backgroundColor('#2a6fd0')
                .onClick(() => {
                  this.restart();
                })
              Button('退出游戏')
                .backgroundColor('#5a2b26')
                .fontColor('#ffd6cc')
                .onClick(() => {
                  this.exitGame();
                })
            }
            .margin({ top: 20 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0,0,0,0.55)')
        }
      }
      .layoutWeight(1)
      .height('100%')

      // ---------- 侧边栏 ----------
      Column() {
        Text('指 挥 部')
          .width('100%')
          .height(26)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#d8c98c')
          .textAlign(TextAlign.Center)
          .backgroundColor('#2c2b20')
        Row() {
          Text('建筑')
            .fontSize(13)
            .fontColor(this.tab === 0 ? '#f2e8bf' : '#8a8064')
            .fontWeight(this.tab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.tab === 0 ? '#3c3a2c' : '#1b1c14')
            .onClick(() => {
              this.tab = 0;
            })
          Text('部队')
            .fontSize(13)
            .fontColor(this.tab === 1 ? '#f2e8bf' : '#8a8064')
            .fontWeight(this.tab === 1 ? FontWeight.Bold : FontWeight.Normal)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.tab === 1 ? '#3c3a2c' : '#1b1c14')
            .onClick(() => {
              this.tab = 1;
            })
        }
        .width('100%')

        Scroll() {
          Column({ space: 6 }) {
            if (this.tab === 0) {
              ForEach(BUILD_LIST, (bt: number) => {
                this.panelButton(
                  BSPECS[bt].name,
                  '$' + BSPECS[bt].cost + '  电' + (BSPECS[bt].power > 0 ? '+' : '') + BSPECS[bt].power,
                  () => {
                    this.toast(this.game.startBuild(Team.PLAYER, bt));
                    this.uiSync();
                  })
              }, (bt: number) => 'b' + bt)
            } else {
              ForEach(UNIT_LIST, (ut: number) => {
                this.panelButton(
                  USPECS[ut].name,
                  '$' + USPECS[ut].cost + (USPECS[ut].vehicle ? '  车厂' : '  兵营'),
                  () => {
                    this.toast(this.game.trainUnit(Team.PLAYER, ut));
                    this.uiSync();
                  })
              }, (ut: number) => 'u' + ut)
              Text('兵营队列 ' + this.infQLen + '/4   车厂队列 ' + this.vehQLen + '/4')
                .fontSize(10)
                .fontColor('#8fa0b0')
                .margin({ top: 2 })
            }
          }
          .width('100%')
          .padding(8)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Column({ space: 6 }) {
          Button('全选部队')
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor('#dcebff')
            .backgroundColor('#2f4a63')
            .border({
              width: { top: 1, left: 1, right: 1, bottom: 2 },
              color: { top: '#4f7196', left: '#3c5a78', right: '#16314a', bottom: '#0f2638' }
            })
            .onClick(() => {
              this.selIds = this.game.selectAllCombat();
              this.selCount = this.selIds.length;
              if (this.selCount === 0) {
                this.toast('没有可用的作战单位');
              }
            })
          Button('停止 / 取消选择')
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor('#f3dca2')
            .backgroundColor('#5a4326')
            .border({
              width: { top: 1, left: 1, right: 1, bottom: 2 },
              color: { top: '#8a6b3c', left: '#6e5530', right: '#2c2012', bottom: '#1c1408' }
            })
            .onClick(() => {
              this.game.stopUnits(this.selIds);
              this.selIds = [];
              this.selCount = 0;
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: this.bottomSafe() })
      }
      .width(132 + this.rightSafe())
      .height('100%')
      .padding({ right: this.rightSafe() })
      .backgroundColor('#23241c')
      .border({ width: { left: 2 }, color: { left: '#5a5340' } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0F14')
  }
}
