// ============ 回放播放页：Canvas 回放 + 播放/暂停/变速/进度拖动/事件标记 ============
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ReplayStore } from '../game/ReplayStore';
import { ReplayData, ReplayPlayer, buildReplayMap, fmtDur, ReplayEvent } from '../game/Replay';
import { GameMap } from '../game/World';
import { Renderer } from '../game/Renderer';
import { MAP_W, MAP_H } from '../game/Config';

const TICK_MS: number = 33;

@Entry
@Component
struct Replay {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private renderer: Renderer = new Renderer();
  private map: GameMap | null = null;
  private player: ReplayPlayer | null = null;
  private timer: number = -1;
  private lastT: number = 0;
  private uiAcc: number = 0;
  private viewW: number = 0;
  private viewH: number = 0;
  // 触控
  private touchX: number = 0;
  private touchY: number = 0;
  private downX: number = 0;
  private downY: number = 0;
  private dragging: boolean = false;

  @StorageProp('navBottomPx') navBottomPx: number = 0;
  @State loaded: boolean = false;
  @State playing: boolean = false;
  @State speed: number = 1;
  @State curT: number = 0;
  @State duration: number = 0;
  @State pm: number = 0;
  @State em: number = 0;
  @State events: ReplayEvent[] = [];
  @State stripW: number = 0;

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, number>;
    let id = 0;
    if (p != null) {
      id = p['id'];
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const d: ReplayData | null = ReplayStore.load(ctx, id);
    if (d == null) {
      this.loaded = false;
      return;
    }
    this.map = buildReplayMap(d.map);
    this.player = new ReplayPlayer(d.snaps);
    this.player.playing = true;
    this.duration = this.player.duration;
    this.events = d.events;
    this.playing = true;
    this.loaded = true;
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private bottomSafe(): number {
    return px2vp(this.navBottomPx) + 10;
  }

  private frame(): void {
    const player = this.player;
    const map = this.map;
    if (player == null || map == null) {
      return;
    }
    const now = Date.now();
    let dt = (now - this.lastT) / 1000;
    this.lastT = now;
    if (dt > 0.1) {
      dt = 0.1;
    }
    player.tick(dt);
    const snap = player.currentFrame();
    if (snap != null) {
      this.renderer.drawReplay(this.ctx, snap, map, this.viewW, this.viewH);
    }
    this.uiAcc += dt;
    if (this.uiAcc >= 0.15) {
      this.uiAcc = 0;
      this.curT = player.playT;
      if (snap != null) {
        this.pm = snap.pm;
        this.em = snap.em;
      }
      if (this.playing !== player.playing) {
        this.playing = player.playing;
      }
    }
  }

  private togglePlay(): void {
    const player = this.player;
    if (player == null) {
      return;
    }
    if (!this.playing) {
      if (player.playT >= player.duration) {
        player.seek(0);
      }
      player.playing = true;
      this.playing = true;
    } else {
      player.playing = false;
      this.playing = false;
    }
  }

  private cycleSpeed(): void {
    const player = this.player;
    if (player == null) {
      return;
    }
    this.speed = this.speed === 1 ? 2 : (this.speed === 2 ? 4 : 1);
    player.speed = this.speed;
  }

  private seekTo(t: number): void {
    const player = this.player;
    if (player == null) {
      return;
    }
    player.seek(t);
    this.curT = player.playT;
  }

  // ---- 触控：拖动平移 + 点击小地图跳转 ----
  private handleTouch(event: TouchEvent): void {
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
      if (!this.dragging && this.renderer.isMiniHit(px, py)) {
        const wx = this.renderer.miniToWorldX(px);
        const wy = this.renderer.miniToWorldY(py);
        this.renderer.centerOn(wx, wy, this.viewW, this.viewH);
      }
      this.dragging = false;
    }
  }

  private eventColor(kind: string): string {
    if (kind === 'battle') {
      return '#ffb454';
    }
    if (kind === 'destroy') {
      return '#ff6a5e';
    }
    return '#7fb4ff';
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('返回')
          .fontSize(14)
          .fontColor('#cfe2ff')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick(() => {
            router.back();
          })
        Text('回放')
          .fontSize(14)
          .fontColor('#f0e6bd')
          .fontWeight(FontWeight.Bold)
          .margin({ left: 6 })
        Blank()
        Text('我方 $' + this.pm)
          .fontSize(12)
          .fontColor('#7fffb0')
          .margin({ right: 12 })
        Text('敌方 $' + this.em)
          .fontSize(12)
          .fontColor('#ff8a7e')
          .margin({ right: 12 })
      }
      .width('100%')
      .height(34)
      .backgroundColor('rgba(20,22,14,0.82)')
      .border({ width: { bottom: 1 }, color: { bottom: '#5a5340' } })

      // 战场（中间区域，含数据缺失提示）
      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .backgroundColor('#05070a')
          .onReady(() => {
            this.viewW = this.ctx.width;
            this.viewH = this.ctx.height;
            this.renderer.centerOn(MAP_W / 2, MAP_H / 2, this.viewW, this.viewH);
            this.lastT = Date.now();
            if (this.timer < 0 && this.loaded) {
              this.timer = setInterval(() => {
                this.frame();
              }, TICK_MS);
            }
          })
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })
        if (!this.loaded) {
          Column() {
            Text('回放数据缺失或已损坏')
              .fontSize(15)
              .fontColor('#ff7a6e')
            Button('返回')
              .margin({ top: 16 })
              .backgroundColor('#2f4a63')
              .onClick(() => {
                router.back();
              })
          }
          .justifyContent(FlexAlign.Center)
        }
      }
      .layoutWeight(1)
      .width('100%')

      // 底部控制条
      Column() {
        // 事件标记条
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.events, (e: ReplayEvent) => {
            Column() {
              Column()
                .width(3)
                .height(12)
                .backgroundColor(this.eventColor(e.kind))
            }
            .width(12)
            .height(14)
            .justifyContent(FlexAlign.Center)
            .position({ x: this.duration > 0 ? (e.t / this.duration) * this.stripW - 6 : 0, y: 0 })
            .onClick(() => {
              this.seekTo(e.t);
            })
          }, (e: ReplayEvent, i: number) => 'e' + i + '_' + e.t)
        }
        .width('100%')
        .height(14)
        .onAreaChange((oldV: Area, newV: Area) => {
          const w = newV.width;
          this.stripW = typeof w === 'number' ? (w as number) : 0;
        })

        Slider({ value: this.curT, min: 0, max: this.duration > 0 ? this.duration : 1, step: 0.1 })
          .width('100%')
          .blockColor('#f0e6bd')
          .selectedColor('#caa83a')
          .trackColor('#3a3a32')
          .onChange((value: number) => {
            this.seekTo(value);
          })

        Row() {
          Button(this.playing ? '暂停' : '播放')
            .width(72)
            .height(34)
            .fontSize(13)
            .backgroundColor('#2f4a63')
            .fontColor('#dcebff')
            .onClick(() => {
              this.togglePlay();
            })
          Button(this.speed + 'x')
            .width(56)
            .height(34)
            .fontSize(13)
            .margin({ left: 10 })
            .backgroundColor('#3a4030')
            .fontColor('#eaf0d6')
            .onClick(() => {
              this.cycleSpeed();
            })
          Blank()
          Text(fmtDur(this.curT) + ' / ' + fmtDur(this.duration))
            .fontSize(12)
            .fontColor('#b9c4a0')
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: this.bottomSafe() })
      .backgroundColor('rgba(20,22,14,0.92)')
      .border({ width: { top: 1 }, color: { top: '#5a5340' } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#05070a')
  }
}
