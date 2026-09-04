// ============ 回放：数据模型 / 录制器 / 播放器（快照方案，引擎无侵入） ============
import { Game } from './Game';
import { GameMap } from './World';
import { BSPECS } from './Config';

const SNAP_DT: number = 0.5; // 采样间隔（秒）

// ---------------- 数据模型（纯数据，可 JSON 序列化） ----------------
export class BRec {
  bt: number = 0;   // 建筑类型
  tm: number = 0;   // 阵营
  x: number = 0;    // 左上格 x
  y: number = 0;    // 左上格 y
  hp: number = 0;
}

export class URec {
  ut: number = 0;   // 单位类型
  tm: number = 0;
  x: number = 0;
  y: number = 0;
  fx: number = 1;   // 朝向
  fy: number = 0;
  hp: number = 0;
  cg: number = 0;   // 载货
}

export class Snapshot {
  t: number = 0;    // 游戏时间（秒）
  pm: number = 0;   // 玩家资金
  em: number = 0;   // 敌方资金
  b: BRec[] = [];
  u: URec[] = [];
}

export class ReplayEvent {
  t: number = 0;
  kind: string = '';   // 'battle' | 'destroy' | 'wave'
  label: string = '';
}

export class MapHeader {
  terrain: number[] = [];
  ore: number[] = [];
}

export class ReplayMeta {
  id: number = 0;
  date: string = '';
  durSec: number = 0;
  winner: number = -1;
}

export class ReplayData {
  meta: ReplayMeta = new ReplayMeta();
  map: MapHeader = new MapHeader();
  snaps: Snapshot[] = [];
  events: ReplayEvent[] = [];
}

// ---------------- 工具函数 ----------------
export function round1(v: number): number {
  return Math.round(v * 10) / 10;
}

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

export function formatDate(ms: number): string {
  const d = new Date(ms);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
    + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

export function fmtDur(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return pad2(m) + ':' + pad2(s);
}

// 由回放头重建一张全开（无迷雾）地图，供回放渲染
export function buildReplayMap(header: MapHeader): GameMap {
  const m = new GameMap();
  const tn = Math.min(header.terrain.length, m.terrain.length);
  for (let i = 0; i < tn; i++) {
    m.terrain[i] = header.terrain[i];
  }
  const on = Math.min(header.ore.length, m.ore.length);
  for (let i = 0; i < on; i++) {
    m.ore[i] = header.ore[i];
  }
  m.explored.fill(1);
  return m;
}

// ---------------- 录制器 ----------------
export class Recorder {
  private header: MapHeader = new MapHeader();
  private snaps: Snapshot[] = [];
  private events: ReplayEvent[] = [];
  private acc: number = 0;
  private t: number = 0;
  private started: boolean = false;
  private lastWave: number = 0;
  private battleSeen: boolean = false;
  private prevBuildings: string[] = [];

  start(game: Game): void {
    this.header = new MapHeader();
    const m = game.map;
    const terr: number[] = [];
    const ore: number[] = [];
    for (let i = 0; i < m.terrain.length; i++) {
      terr.push(m.terrain[i]);
    }
    for (let i = 0; i < m.ore.length; i++) {
      ore.push(m.ore[i]);
    }
    this.header.terrain = terr;
    this.header.ore = ore;
    this.snaps = [];
    this.events = [];
    this.acc = SNAP_DT; // 让首帧尽早采样
    this.t = 0;
    this.started = true;
    this.lastWave = game.getWave();
    this.battleSeen = false;
    this.prevBuildings = [];
  }

  tick(game: Game, dt: number): void {
    if (!this.started || game.winner >= 0) {
      return;
    }
    this.t += dt;
    if (!this.battleSeen && game.shots.length > 0) {
      this.battleSeen = true;
      this.events.push(this.mkEvent(this.t, 'battle', '首次交战'));
    }
    const w = game.getWave();
    if (w > this.lastWave) {
      this.lastWave = w;
      this.events.push(this.mkEvent(this.t, 'wave', '敌军第' + w + '波进攻'));
    }
    this.acc += dt;
    if (this.acc >= SNAP_DT) {
      this.acc = 0;
      this.capture(game);
    }
  }

  private capture(game: Game): void {
    const snap = new Snapshot();
    snap.t = round1(this.t);
    snap.pm = Math.floor(game.ps[0].money);
    snap.em = Math.floor(game.ps[1].money);
    const sigs: string[] = [];
    for (let i = 0; i < game.buildings.length; i++) {
      const b = game.buildings[i];
      if (b.isDead()) {
        continue;
      }
      const rec = new BRec();
      rec.bt = b.btype;
      rec.tm = b.team;
      rec.x = b.tx;
      rec.y = b.ty;
      rec.hp = Math.round(b.hp);
      snap.b.push(rec);
      sigs.push(b.team + ':' + b.btype + ':' + b.tx + ':' + b.ty);
    }
    for (let i = 0; i < game.units.length; i++) {
      const u = game.units[i];
      if (u.isDead()) {
        continue;
      }
      const rec = new URec();
      rec.ut = u.utype;
      rec.tm = u.team;
      rec.x = round1(u.x);
      rec.y = round1(u.y);
      rec.fx = round1(u.fx);
      rec.fy = round1(u.fy);
      rec.hp = Math.round(u.hp);
      rec.cg = Math.round(u.cargo);
      snap.u.push(rec);
    }
    // 建筑被摧毁事件：上一采样帧有、这帧没有
    if (this.prevBuildings.length > 0) {
      for (let i = 0; i < this.prevBuildings.length; i++) {
        if (sigs.indexOf(this.prevBuildings[i]) < 0) {
          const parts = this.prevBuildings[i].split(':');
          const tm = parseInt(parts[0]);
          const bt = parseInt(parts[1]);
          const who = tm === 0 ? '我方' : '敌方';
          this.events.push(this.mkEvent(this.t, 'destroy', who + BSPECS[bt].name + '被摧毁'));
        }
      }
    }
    this.prevBuildings = sigs;
    this.snaps.push(snap);
  }

  private mkEvent(t: number, kind: string, label: string): ReplayEvent {
    const e = new ReplayEvent();
    e.t = round1(t);
    e.kind = kind;
    e.label = label;
    return e;
  }

  hasData(): boolean {
    return this.snaps.length > 0;
  }

  finalize(game: Game): ReplayData {
    this.capture(game); // 补结局帧
    const data = new ReplayData();
    const meta = new ReplayMeta();
    meta.id = Date.now();
    meta.date = formatDate(meta.id);
    meta.durSec = Math.floor(this.t);
    meta.winner = game.winner;
    data.meta = meta;
    data.map = this.header;
    data.snaps = this.snaps;
    data.events = this.events;
    this.started = false;
    return data;
  }
}

// ---------------- 播放器 ----------------
export class ReplayPlayer {
  private snaps: Snapshot[];
  playing: boolean = false;
  speed: number = 1;
  playT: number = 0;
  duration: number = 0;

  constructor(snaps: Snapshot[]) {
    this.snaps = snaps;
    this.duration = snaps.length > 0 ? snaps[snaps.length - 1].t : 0;
  }

  tick(dtReal: number): void {
    if (!this.playing) {
      return;
    }
    this.playT += dtReal * this.speed;
    if (this.playT >= this.duration) {
      this.playT = this.duration;
      this.playing = false;
    }
  }

  seek(t: number): void {
    this.playT = Math.max(0, Math.min(this.duration, t));
  }

  currentFrame(): Snapshot | null {
    const s = this.snaps;
    if (s.length === 0) {
      return null;
    }
    let lo = 0;
    let hi = s.length - 1;
    let ans = 0;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (s[mid].t <= this.playT) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return s[ans];
  }
}
