// ============ 游戏引擎核心：主循环 / 经济 / 生产 / 战斗 / AI ============
import {
  Team, BType, UType, BSPECS, USPECS, MAP_W, MAP_H, Terrain,
  HARVEST_CAPACITY, HARVEST_RATE, UNLOAD_TIME, LOW_POWER_FACTOR,
  START_MONEY_PLAYER, START_MONEY_ENEMY
} from './Config';
import { GameMap, PathFinder, Vec2 } from './World';
import { Entity, Building, Unit, UState, Projectile, Fx } from './Entities';

// 生产队列条目
export class ProdItem {
  isBuilding: boolean;
  bt: number;
  ut: number;
  remain: number;
  total: number;

  constructor(isBuilding: boolean, bt: number, ut: number, total: number) {
    this.isBuilding = isBuilding;
    this.bt = bt;
    this.ut = ut;
    this.remain = total;
    this.total = total;
  }
}

export class PlayerState {
  team: number;
  money: number;
  buildQ: ProdItem | null = null; // 建筑建造（同时只能一个，RA2规则）
  pending: number = -1;           // 建造完成等待放置的建筑类型（仅玩家）
  infQ: ProdItem[] = [];          // 兵营生产队列
  vehQ: ProdItem[] = [];          // 战车工厂生产队列

  constructor(team: number, money: number) {
    this.team = team;
    this.money = money;
  }
}

// AI 建造顺序
const AI_ORDER: number[] = [BType.POWER, BType.BARRACKS, BType.REFINERY,
  BType.FACTORY, BType.TURRET, BType.POWER, BType.TURRET];

const FORM_OFF_X: number[] = [0, 1, 0, -1, 0, 1, -1, 1, -1, 2, 0, -2, 0, 2, 2, -2, -2];
const FORM_OFF_Y: number[] = [0, 0, 1, 0, -1, 1, 1, -1, -1, 0, 2, 0, -2, 1, -1, 1, -1];

export class Game {
  map: GameMap = new GameMap();
  units: Unit[] = [];
  buildings: Building[] = [];
  shots: Projectile[] = [];
  fxs: Fx[] = [];
  ps: PlayerState[] = [
    new PlayerState(Team.PLAYER, START_MONEY_PLAYER),
    new PlayerState(Team.ENEMY, START_MONEY_ENEMY)
  ];
  time: number = 0;
  winner: number = -1; // -1进行中
  private nextId: number = 1;
  private revealT: number = 0;
  // AI 状态
  private aiOrderIdx: number = 0;
  private aiTrainT: number = 3;
  private aiDefT: number = 2;
  private aiAttackT: number = 150;
  private aiWave: number = 0;
  private aiInfToggle: boolean = false;

  constructor() {
    this.map.generate();
    this.setupBase(Team.PLAYER, 5, 34);
    this.setupBase(Team.ENEMY, 33, 5);
    this.revealForPlayer();
  }

  // ---------------- 初始化 ----------------
  private setupBase(team: number, bx: number, by: number): void {
    this.addBuilding(team, BType.CONYARD, bx, by);
    if (team === Team.PLAYER) {
      this.addBuilding(team, BType.POWER, bx + 4, by);
      this.addBuilding(team, BType.REFINERY, bx, by + 4);
      this.spawnAt(team, UType.HARVESTER, bx + 4, by + 5);
      this.spawnAt(team, UType.RIFLE, bx + 5, by + 2);
      this.spawnAt(team, UType.RIFLE, bx + 5, by + 3);
      this.spawnAt(team, UType.TANK, bx + 6, by + 4);
    } else {
      this.addBuilding(team, BType.POWER, bx - 3, by);
      this.addBuilding(team, BType.REFINERY, bx, by + 4);
      this.spawnAt(team, UType.HARVESTER, bx - 2, by + 5);
      this.spawnAt(team, UType.RIFLE, bx - 2, by + 3);
      this.spawnAt(team, UType.RIFLE, bx - 1, by + 3);
      this.spawnAt(team, UType.TANK, bx - 3, by + 4);
    }
  }

  baseCenter(team: number): Vec2 {
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.team === team && b.btype === BType.CONYARD) {
        return new Vec2(b.cx(), b.cy());
      }
    }
    for (let i = 0; i < this.buildings.length; i++) {
      if (this.buildings[i].team === team) {
        return new Vec2(this.buildings[i].cx(), this.buildings[i].cy());
      }
    }
    return new Vec2(MAP_W / 2, MAP_H / 2);
  }

  private addBuilding(team: number, bt: number, tx: number, ty: number): Building {
    const b = new Building(this.nextId++, team, bt, tx, ty);
    const spec = b.spec();
    for (let y = ty; y < ty + spec.h; y++) {
      for (let x = tx; x < tx + spec.w; x++) {
        if (this.map.inBounds(x, y)) {
          const i = this.map.idx(x, y);
          this.map.occupied[i] = b.id;
          this.map.ore[i] = 0;
        }
      }
    }
    this.buildings.push(b);
    if (team === Team.PLAYER) {
      this.map.reveal(b.cx(), b.cy(), 8);
    }
    return b;
  }

  private spawnAt(team: number, ut: number, tx: number, ty: number): Unit | null {
    // 在(tx,ty)附近找空位
    for (let r = 0; r <= 5; r++) {
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) {
            continue;
          }
          const x = tx + dx;
          const y = ty + dy;
          if (this.map.isPassable(x, y)) {
            const u = new Unit(this.nextId++, team, ut, x + 0.5, y + 0.5);
            this.units.push(u);
            return u;
          }
        }
      }
    }
    return null;
  }

  // ---------------- 对外查询 ----------------
  power(team: number): Vec2 {
    let gen = 0;
    let use = 0;
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.team !== team) {
        continue;
      }
      const p = b.spec().power;
      if (p > 0) {
        gen += p;
      } else {
        use += -p;
      }
    }
    return new Vec2(gen, use);
  }

  private powerFactor(team: number): number {
    const p = this.power(team);
    return p.y <= p.x ? 1 : LOW_POWER_FACTOR;
  }

  private hasBuilding(team: number, bt: number): boolean {
    for (let i = 0; i < this.buildings.length; i++) {
      if (this.buildings[i].team === team && this.buildings[i].btype === bt && !this.buildings[i].isDead()) {
        return true;
      }
    }
    return false;
  }

  private countBuilding(team: number, bt: number): number {
    let c = 0;
    for (let i = 0; i < this.buildings.length; i++) {
      if (this.buildings[i].team === team && this.buildings[i].btype === bt) {
        c++;
      }
    }
    return c;
  }

  pickEntity(wx: number, wy: number): Entity | null {
    // 优先选己方单位，其次敌方单位，再次建筑
    let best: Entity | null = null;
    let bestD = 0.85;
    for (let pass = 0; pass < 2; pass++) {
      const wantTeam = pass === 0 ? Team.PLAYER : Team.ENEMY;
      for (let i = 0; i < this.units.length; i++) {
        const u = this.units[i];
        if (u.team !== wantTeam) {
          continue;
        }
        if (wantTeam === Team.ENEMY && !this.map.isExplored(Math.floor(u.x), Math.floor(u.y))) {
          continue;
        }
        const d = Math.hypot(u.x - wx, u.y - wy);
        if (d < bestD) {
          bestD = d;
          best = u;
        }
      }
      if (best != null) {
        return best;
      }
    }
    const tx = Math.floor(wx);
    const ty = Math.floor(wy);
    if (this.map.inBounds(tx, ty)) {
      const id = this.map.occupied[this.map.idx(tx, ty)];
      if (id > 0) {
        for (let i = 0; i < this.buildings.length; i++) {
          if (this.buildings[i].id === id) {
            const b = this.buildings[i];
            if (b.team === Team.ENEMY && !this.map.isExplored(tx, ty)) {
              return null;
            }
            return b;
          }
        }
      }
    }
    return null;
  }

  aliveIds(ids: number[]): number[] {
    const out: number[] = [];
    for (let i = 0; i < ids.length; i++) {
      const u = this.unitById(ids[i]);
      if (u != null && !u.isDead()) {
        out.push(ids[i]);
      }
    }
    return out;
  }

  // 当前 AI 进攻波次序号（供录制做波次事件标记）
  getWave(): number {
    return this.aiWave;
  }

  private unitById(id: number): Unit | null {
    for (let i = 0; i < this.units.length; i++) {
      if (this.units[i].id === id) {
        return this.units[i];
      }
    }
    return null;
  }

  // ---------------- 玩家/AI 指令 ----------------
  startBuild(team: number, bt: number): string {
    const p = this.ps[team];
    const spec = BSPECS[bt];
    if (p.buildQ != null || (team === Team.PLAYER && p.pending >= 0)) {
      return '建造队列繁忙';
    }
    for (let i = 0; i < spec.needs.length; i++) {
      if (!this.hasBuilding(team, spec.needs[i])) {
        return '需要先建造: ' + BSPECS[spec.needs[i]].name;
      }
    }
    if (p.money < spec.cost) {
      return '资金不足';
    }
    p.money -= spec.cost;
    p.buildQ = new ProdItem(true, bt, -1, spec.buildTime);
    return '';
  }

  trainUnit(team: number, ut: number): string {
    const p = this.ps[team];
    const spec = USPECS[ut];
    const needB = spec.vehicle ? BType.FACTORY : BType.BARRACKS;
    if (!this.hasBuilding(team, needB)) {
      return '需要先建造: ' + BSPECS[needB].name;
    }
    const q = spec.vehicle ? p.vehQ : p.infQ;
    if (q.length >= 4) {
      return '生产队列已满';
    }
    if (p.money < spec.cost) {
      return '资金不足';
    }
    p.money -= spec.cost;
    q.push(new ProdItem(false, -1, ut, spec.buildTime));
    return '';
  }

  canPlace(team: number, bt: number, tx: number, ty: number): boolean {
    const spec = BSPECS[bt];
    for (let y = ty; y < ty + spec.h; y++) {
      for (let x = tx; x < tx + spec.w; x++) {
        if (!this.map.inBounds(x, y)) {
          return false;
        }
        const i = this.map.idx(x, y);
        if (this.map.terrain[i] !== Terrain.GRASS || this.map.occupied[i] !== 0 || this.map.ore[i] > 0) {
          return false;
        }
        if (team === Team.PLAYER && this.map.explored[i] === 0) {
          return false;
        }
      }
    }
    // 必须靠近己方建筑
    const cx = tx + spec.w / 2;
    const cy = ty + spec.h / 2;
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.team === team && Math.max(Math.abs(b.cx() - cx), Math.abs(b.cy() - cy)) <= 8) {
        return true;
      }
    }
    return false;
  }

  tryPlacePending(tx: number, ty: number): string {
    const p = this.ps[Team.PLAYER];
    if (p.pending < 0) {
      return '';
    }
    if (!this.canPlace(Team.PLAYER, p.pending, tx, ty)) {
      return '此处无法放置：需地形空旷且靠近己方建筑';
    }
    const bt = p.pending;
    p.pending = -1;
    this.addBuilding(Team.PLAYER, bt, tx, ty);
    return '';
  }

  commandMove(ids: number[], tx: number, ty: number): void {
    let k = 0;
    for (let i = 0; i < ids.length; i++) {
      const u = this.unitById(ids[i]);
      if (u == null) {
        continue;
      }
      const ox = FORM_OFF_X[k % FORM_OFF_X.length];
      const oy = FORM_OFF_Y[k % FORM_OFF_Y.length];
      k++;
      u.target = null;
      u.auto = false;
      u.attackMove = false;
      u.hold = false;
      u.state = UState.MOVE;
      u.path = PathFinder.find(this.map, Math.floor(u.x), Math.floor(u.y), tx + ox, ty + oy);
    }
  }

  commandAttack(ids: number[], ent: Entity): void {
    for (let i = 0; i < ids.length; i++) {
      const u = this.unitById(ids[i]);
      if (u == null || !u.isCombat()) {
        continue;
      }
      u.target = ent;
      u.auto = false;
      u.attackMove = false;
      u.hold = false;
      u.state = UState.IDLE;
      u.path = [];
    }
  }

  stopUnits(ids: number[]): void {
    for (let i = 0; i < ids.length; i++) {
      const u = this.unitById(ids[i]);
      if (u == null) {
        continue;
      }
      u.path = [];
      u.target = null;
      u.auto = false;
      u.attackMove = false;
      if (u.isCombat()) {
        u.state = UState.IDLE;
        u.hold = true; // 静默待命：不再自动索敌，直到下达新指令
      }
    }
  }

  selectAllCombat(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.units.length; i++) {
      const u = this.units[i];
      if (u.team === Team.PLAYER && u.isCombat()) {
        out.push(u.id);
      }
    }
    return out;
  }

  // ---------------- 主循环 ----------------
  update(dt: number): void {
    if (this.winner >= 0) {
      this.updateFx(dt);
      return;
    }
    this.time += dt;
    this.updateProduction(Team.PLAYER, dt);
    this.updateProduction(Team.ENEMY, dt);
    for (let i = 0; i < this.units.length; i++) {
      this.updateUnit(this.units[i], dt);
    }
    this.updateTurrets(dt);
    this.updateShots(dt);
    this.updateFx(dt);
    this.aiUpdate(dt);
    this.cleanup();
    this.revealT -= dt;
    if (this.revealT <= 0) {
      this.revealT = 0.4;
      this.revealForPlayer();
    }
    this.checkWin();
  }

  private revealForPlayer(): void {
    for (let i = 0; i < this.units.length; i++) {
      const u = this.units[i];
      if (u.team === Team.PLAYER) {
        this.map.reveal(u.x, u.y, u.spec().sight);
      }
    }
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.team === Team.PLAYER) {
        this.map.reveal(b.cx(), b.cy(), 8);
      }
    }
  }

  private checkWin(): void {
    if (this.time < 3) {
      return;
    }
    let c0 = 0;
    let c1 = 0;
    for (let i = 0; i < this.buildings.length; i++) {
      if (this.buildings[i].team === Team.PLAYER) {
        c0++;
      } else {
        c1++;
      }
    }
    if (c1 === 0) {
      this.winner = Team.PLAYER;
    } else if (c0 === 0) {
      this.winner = Team.ENEMY;
    }
  }

  // ---------------- 生产系统 ----------------
  private updateProduction(team: number, dt: number): void {
    const p = this.ps[team];
    const factor = this.powerFactor(team);
    if (p.buildQ != null) {
      p.buildQ.remain -= dt * factor;
      if (p.buildQ.remain <= 0) {
        const bt = p.buildQ.bt;
        p.buildQ = null;
        if (team === Team.PLAYER) {
          p.pending = bt;
        } else {
          this.aiPlace(bt);
        }
      }
    }
    this.tickQueue(team, p.infQ, BType.BARRACKS, dt * factor);
    this.tickQueue(team, p.vehQ, BType.FACTORY, dt * factor);
  }

  private tickQueue(team: number, q: ProdItem[], producerType: number, step: number): void {
    if (q.length === 0) {
      return;
    }
    const head = q[0];
    head.remain -= step;
    if (head.remain > 0) {
      return;
    }
    q.shift();
    // 找生产建筑出兵
    let producer: Building | null = null;
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.team === team && b.btype === producerType && !b.isDead()) {
        producer = b;
        break;
      }
    }
    if (producer == null) {
      this.ps[team].money += USPECS[head.ut].cost; // 工厂没了，退款
      return;
    }
    const u = this.spawnAt(team, head.ut, producer.tx + 1, producer.ty + producer.spec().h);
    if (u != null) {
      // 出厂后向外集结两格，避免堵门
      u.path = PathFinder.find(this.map, Math.floor(u.x), Math.floor(u.y),
        Math.floor(u.x), Math.floor(u.y) + 2);
      u.state = UState.MOVE;
    }
  }

  // ---------------- 单位逻辑 ----------------
  private updateUnit(u: Unit, dt: number): void {
    if (u.cool > 0) {
      u.cool -= dt;
    }
    if (u.utype === UType.HARVESTER) {
      this.harvesterLogic(u, dt);
      return;
    }
    // 自动索敌
    u.scanT -= dt;
    if (u.scanT <= 0) {
      u.scanT = 0.35 + Math.random() * 0.25;
      const noTarget = u.target == null || u.target.isDead();
      if (noTarget && !u.hold && (u.state === UState.IDLE || u.attackMove)) {
        const t = this.nearestEnemy(u, u.spec().sight + 1);
        if (t != null) {
          u.target = t;
          u.auto = true;
          u.guardX = u.x;
          u.guardY = u.y;
        }
      }
    }
    // 目标处理
    let tgt = u.target;
    if (tgt != null && tgt.isDead()) {
      u.target = null;
      tgt = null;
      if (u.attackMove && u.destX >= 0) {
        u.path = PathFinder.find(this.map, Math.floor(u.x), Math.floor(u.y), u.destX, u.destY);
      }
    }
    if (tgt != null) {
      const d = this.distToEntity(u.x, u.y, tgt);
      if (d <= u.spec().range) {
        u.path = [];
        const tp = this.entityPos(tgt);
        u.fx = tp.x - u.x;
        u.fy = tp.y - u.y;
        if (u.cool <= 0) {
          u.cool = u.spec().cooldown;
          this.fire(u, tgt);
        }
        return;
      } else {
        // 警戒锁链：自动索敌（非玩家指令）的追击不超过锚点8格，防止被引去送死
        if (u.auto && !u.attackMove && Math.hypot(u.x - u.guardX, u.y - u.guardY) > 8) {
          u.target = null;
          u.auto = false;
          u.state = UState.MOVE;
          u.path = PathFinder.find(this.map, Math.floor(u.x), Math.floor(u.y),
            Math.floor(u.guardX), Math.floor(u.guardY));
        } else {
          u.repathT -= dt;
          if (u.path.length === 0 || u.repathT <= 0) {
            u.repathT = 1.2;
            const tp = this.entityPos(tgt);
            u.path = PathFinder.find(this.map, Math.floor(u.x), Math.floor(u.y),
              Math.floor(tp.x), Math.floor(tp.y));
          }
        }
      }
    }
    this.moveAlong(u, dt);
    if (u.path.length === 0 && u.state === UState.MOVE && u.target == null) {
      u.state = UState.IDLE;
    }
  }

  private harvesterLogic(u: Unit, dt: number): void {
    const map = this.map;
    if (u.state === UState.MOVE) {
      this.moveAlong(u, dt);
      if (u.path.length === 0) {
        u.state = UState.IDLE;
      }
      return;
    }
    if (u.state === UState.IDLE) {
      if (u.cargo >= HARVEST_CAPACITY) {
        this.goRefinery(u);
        return;
      }
      const tile = map.findNearestOre(u.x, u.y, 30);
      if (tile != null) {
        u.oreX = tile.x;
        u.oreY = tile.y;
        u.path = PathFinder.find(map, Math.floor(u.x), Math.floor(u.y), tile.x, tile.y);
        u.state = UState.TO_ORE;
      } else if (u.cargo > 0) {
        this.goRefinery(u);
      }
      return;
    }
    if (u.state === UState.TO_ORE) {
      this.moveAlong(u, dt);
      if (u.path.length === 0) {
        if (u.oreX >= 0 && Math.hypot(u.x - u.oreX - 0.5, u.y - u.oreY - 0.5) < 1.2 && map.oreAt(u.oreX, u.oreY) > 0) {
          u.state = UState.HARVEST;
          u.workT = 0;
        } else {
          u.state = UState.IDLE;
        }
      }
      return;
    }
    if (u.state === UState.HARVEST) {
      u.workT += dt;
      if (u.workT >= 0.25) {
        u.workT = 0;
        const got = map.takeOre(u.oreX, u.oreY, Math.floor(HARVEST_RATE * 0.25));
        u.cargo += got;
        if (u.cargo >= HARVEST_CAPACITY || got === 0) {
          if (u.cargo > 0) {
            this.goRefinery(u);
          } else {
            u.state = UState.IDLE;
          }
        }
      }
      return;
    }
    if (u.state === UState.TO_REF) {
      this.moveAlong(u, dt);
      if (u.path.length === 0) {
        const ref = this.nearestRefinery(u.team, u.x, u.y);
        if (ref != null && this.distToEntity(u.x, u.y, ref) < 1.8) {
          u.state = UState.UNLOAD;
          u.workT = 0;
        } else {
          u.state = UState.IDLE;
        }
      }
      return;
    }
    if (u.state === UState.UNLOAD) {
      u.workT += dt;
      if (u.workT >= UNLOAD_TIME) {
        this.ps[u.team].money += u.cargo;
        u.cargo = 0;
        u.state = UState.IDLE;
      }
      return;
    }
  }

  private goRefinery(u: Unit): void {
    const ref = this.nearestRefinery(u.team, u.x, u.y);
    if (ref == null) {
      u.state = UState.IDLE;
      return;
    }
    u.path = PathFinder.find(this.map, Math.floor(u.x), Math.floor(u.y),
      ref.tx + 1, ref.ty + ref.spec().h);
    u.state = UState.TO_REF;
  }

  private nearestRefinery(team: number, x: number, y: number): Building | null {
    let best: Building | null = null;
    let bestD = Number.POSITIVE_INFINITY;
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.team !== team || b.btype !== BType.REFINERY || b.isDead()) {
        continue;
      }
      const d = Math.hypot(b.cx() - x, b.cy() - y);
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
  }

  private moveAlong(u: Unit, dt: number): void {
    if (u.path.length === 0) {
      return;
    }
    const head = u.path[0];
    const hx = head.x + 0.5;
    const hy = head.y + 0.5;
    const dx = hx - u.x;
    const dy = hy - u.y;
    const d = Math.hypot(dx, dy);
    const step = u.spec().speed * dt;
    if (d <= step) {
      u.x = hx;
      u.y = hy;
      u.path.shift();
    } else {
      u.x += dx / d * step;
      u.y += dy / d * step;
      u.fx = dx;
      u.fy = dy;
    }
  }

  private entityPos(e: Entity): Vec2 {
    if (e instanceof Unit) {
      return new Vec2(e.x, e.y);
    }
    const b = e as Building;
    return new Vec2(b.cx(), b.cy());
  }

  private distToEntity(x: number, y: number, e: Entity): number {
    if (e instanceof Unit) {
      return Math.hypot(e.x - x, e.y - y);
    }
    const b = e as Building;
    const px = Math.max(b.tx, Math.min(b.tx + b.spec().w, x));
    const py = Math.max(b.ty, Math.min(b.ty + b.spec().h, y));
    return Math.hypot(px - x, py - y);
  }

  private nearestEnemy(u: Unit, r: number): Entity | null {
    const foe = u.team === Team.PLAYER ? Team.ENEMY : Team.PLAYER;
    let best: Entity | null = null;
    let bestD = r;
    for (let i = 0; i < this.units.length; i++) {
      const e = this.units[i];
      if (e.team !== foe || e.isDead()) {
        continue;
      }
      const d = Math.hypot(e.x - u.x, e.y - u.y);
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    if (best != null) {
      return best;
    }
    bestD = r;
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.team !== foe || b.isDead()) {
        continue;
      }
      const d = this.distToEntity(u.x, u.y, b);
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
  }

  private fire(u: Unit, tgt: Entity): void {
    const tp = this.entityPos(tgt);
    const rocket = u.utype === UType.ROCKET || u.utype === UType.HEAVY;
    this.shots.push(new Projectile(u.x, u.y, tgt, tp.x, tp.y, u.spec().damage, u.team, rocket));
  }

  // ---------------- 防御塔 ----------------
  private updateTurrets(dt: number): void {
    for (let i = 0; i < this.buildings.length; i++) {
      const b = this.buildings[i];
      if (b.btype !== BType.TURRET || b.isDead()) {
        continue;
      }
      const p = this.power(b.team);
      if (p.y > p.x) {
        continue; // 缺电停机
      }
      if (b.cool > 0) {
        b.cool -= dt;
        continue;
      }
      const foe = b.team === Team.PLAYER ? Team.ENEMY : Team.PLAYER;
      let best: Entity | null = null;
      let bestD = b.spec().range;
      for (let j = 0; j < this.units.length; j++) {
        const e = this.units[j];
        if (e.team !== foe || e.isDead()) {
          continue;
        }
        const d = Math.hypot(e.x - b.cx(), e.y - b.cy());
        if (d < bestD) {
          bestD = d;
          best = e;
        }
      }
      if (best != null) {
        b.cool = b.spec().cooldown;
        const tp = this.entityPos(best);
        this.shots.push(new Projectile(b.cx(), b.cy(), best, tp.x, tp.y, b.spec().damage, b.team, false));
      }
    }
  }

  // ---------------- 炮弹 ----------------
  private updateShots(dt: number): void {
    for (let i = 0; i < this.shots.length; i++) {
      const s = this.shots[i];
      if (!s.alive) {
        continue;
      }
      let tx = s.lastTx;
      let ty = s.lastTy;
      const tgt = s.target;
      if (tgt != null && !tgt.isDead()) {
        const tp = this.entityPos(tgt);
        tx = tp.x;
        ty = tp.y;
        s.lastTx = tx;
        s.lastTy = ty;
      }
      const dx = tx - s.x;
      const dy = ty - s.y;
      const d = Math.hypot(dx, dy);
      const step = s.speed * dt;
      if (d <= step) {
        s.alive = false;
        if (tgt != null && !tgt.isDead()) {
          tgt.hp -= s.damage;
          this.fxs.push(new Fx(tx, ty, 0.25, s.rocket ? 12 : 7));
        }
      } else {
        s.x += dx / d * step;
        s.y += dy / d * step;
      }
    }
  }

  private updateFx(dt: number): void {
    for (let i = 0; i < this.fxs.length; i++) {
      this.fxs[i].age += dt;
    }
    this.fxs = this.fxs.filter((f: Fx): boolean => f.age < f.dur);
  }

  // ---------------- 清理与死亡 ----------------
  private cleanup(): void {
    const deadUnits = this.units.filter((u: Unit): boolean => u.isDead());
    for (let i = 0; i < deadUnits.length; i++) {
      this.fxs.push(new Fx(deadUnits[i].x, deadUnits[i].y, 0.5, 16));
    }
    if (deadUnits.length > 0) {
      this.units = this.units.filter((u: Unit): boolean => !u.isDead());
    }
    const deadB = this.buildings.filter((b: Building): boolean => b.isDead());
    for (let i = 0; i < deadB.length; i++) {
      const b = deadB[i];
      const spec = b.spec();
      for (let y = b.ty; y < b.ty + spec.h; y++) {
        for (let x = b.tx; x < b.tx + spec.w; x++) {
          if (this.map.inBounds(x, y)) {
            this.map.occupied[this.map.idx(x, y)] = 0;
          }
        }
      }
      this.fxs.push(new Fx(b.cx(), b.cy(), 0.8, 26));
    }
    if (deadB.length > 0) {
      this.buildings = this.buildings.filter((b: Building): boolean => !b.isDead());
    }
    this.shots = this.shots.filter((s: Projectile): boolean => s.alive);
  }

  // ---------------- 敌方 AI ----------------
  private aiUpdate(dt: number): void {
    const ai = this.ps[Team.ENEMY];
    ai.money += 7 * dt; // 后勤补贴，保证AI持续施压

    // 建造
    if (ai.buildQ == null) {
      if (this.aiOrderIdx < AI_ORDER.length) {
        const bt = AI_ORDER[this.aiOrderIdx];
        if (ai.money >= BSPECS[bt].cost + 200) {
          const res = this.startBuild(Team.ENEMY, bt);
          if (res === '') {
            this.aiOrderIdx++;
          }
        }
      } else {
        // 后期维护：补电/补炮塔
        const p = this.power(Team.ENEMY);
        if (p.y > p.x && ai.money > 900) {
          this.startBuild(Team.ENEMY, BType.POWER);
        } else if (this.countBuilding(Team.ENEMY, BType.TURRET) < 3 && ai.money > 2600) {
          this.startBuild(Team.ENEMY, BType.TURRET);
        }
      }
    }

    // 训练
    this.aiTrainT -= dt;
    if (this.aiTrainT <= 0) {
      this.aiTrainT = 2.6;
      let harv = 0;
      for (let i = 0; i < this.units.length; i++) {
        if (this.units[i].team === Team.ENEMY && this.units[i].utype === UType.HARVESTER) {
          harv++;
        }
      }
      let aiCombat = 0;
      for (let i = 0; i < this.units.length; i++) {
        if (this.units[i].team === Team.ENEMY && this.units[i].isCombat()) {
          aiCombat++;
        }
      }
      if (harv < 2 && this.hasBuilding(Team.ENEMY, BType.FACTORY) && ai.money > 1700) {
        this.trainUnit(Team.ENEMY, UType.HARVESTER);
      } else if (aiCombat < 18) {
        if (this.hasBuilding(Team.ENEMY, BType.BARRACKS) && ai.infQ.length < 2 && ai.money > 700) {
          this.trainUnit(Team.ENEMY, this.aiInfToggle ? UType.ROCKET : UType.RIFLE);
          this.aiInfToggle = !this.aiInfToggle;
        }
        if (this.hasBuilding(Team.ENEMY, BType.FACTORY) && ai.vehQ.length < 2 && ai.money > 1900) {
          const ut = this.time > 280 && ai.money > 3600 ? UType.HEAVY : UType.TANK;
          this.trainUnit(Team.ENEMY, ut);
        }
      }
    }

    // 基地防御：玩家打上门时全员反击
    this.aiDefT -= dt;
    if (this.aiDefT <= 0) {
      this.aiDefT = 2.5;
      const base = this.baseCenter(Team.ENEMY);
      let intruder: Unit | null = null;
      let bestD = 12;
      for (let i = 0; i < this.units.length; i++) {
        const u = this.units[i];
        if (u.team !== Team.PLAYER) {
          continue;
        }
        const d = Math.hypot(u.x - base.x, u.y - base.y);
        if (d < bestD) {
          bestD = d;
          intruder = u;
        }
      }
      if (intruder != null) {
        for (let i = 0; i < this.units.length; i++) {
          const u = this.units[i];
          if (u.team === Team.ENEMY && u.isCombat() && (u.target == null || u.target.isDead())) {
            u.target = intruder;
          }
        }
      }
    }

    // 进攻波次
    this.aiAttackT -= dt;
    if (this.aiAttackT <= 0) {
      this.aiAttackT = 110;
      const squad: Unit[] = [];
      for (let i = 0; i < this.units.length; i++) {
        const u = this.units[i];
        if (u.team === Team.ENEMY && u.isCombat() && !u.attackMove) {
          squad.push(u);
        }
      }
      const need = Math.min(4 + this.aiWave, 10);
      if (squad.length >= need) {
        this.aiWave++;
        // 留2个守家，其余攻击玩家最近的建筑
        let tgt: Building | null = null;
        let bestD = Number.POSITIVE_INFINITY;
        const base = this.baseCenter(Team.ENEMY);
        for (let i = 0; i < this.buildings.length; i++) {
          const b = this.buildings[i];
          if (b.team !== Team.PLAYER) {
            continue;
          }
          const d = Math.hypot(b.cx() - base.x, b.cy() - base.y);
          if (d < bestD) {
            bestD = d;
            tgt = b;
          }
        }
        if (tgt != null) {
          const sendEnd = Math.min(squad.length, 2 + need);
          for (let i = 2; i < sendEnd; i++) {
            const u = squad[i];
            u.attackMove = true;
            u.destX = Math.floor(tgt.cx());
            u.destY = Math.floor(tgt.cy());
            u.target = null;
            u.path = PathFinder.find(this.map, Math.floor(u.x), Math.floor(u.y), u.destX, u.destY);
          }
        }
      }
    }
  }

  // AI 自动放置建筑：围绕建造厂螺旋找位，炮塔偏向玩家方向
  private aiPlace(bt: number): void {
    const base = this.baseCenter(Team.ENEMY);
    const pBase = this.baseCenter(Team.PLAYER);
    const bx = Math.floor(base.x);
    const by = Math.floor(base.y);
    let found = false;
    let bestX = 0;
    let bestY = 0;
    let bestScore = Number.POSITIVE_INFINITY;
    for (let r = 2; r <= 13; r++) {
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) {
            continue;
          }
          const tx = bx + dx;
          const ty = by + dy;
          if (!this.canPlace(Team.ENEMY, bt, tx, ty)) {
            continue;
          }
          let score = r;
          if (bt === BType.TURRET) {
            score = Math.hypot(tx - pBase.x, ty - pBase.y); // 炮塔偏向玩家方向
          }
          if (score < bestScore) {
            bestScore = score;
            bestX = tx;
            bestY = ty;
            found = true;
          }
        }
      }
      if (found && bt !== BType.TURRET) {
        break;
      }
    }
    if (found) {
      this.addBuilding(Team.ENEMY, bt, bestX, bestY);
    } else {
      this.ps[Team.ENEMY].money += BSPECS[bt].cost; // 放不下退款
    }
  }
}
