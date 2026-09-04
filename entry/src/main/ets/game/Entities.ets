// ============ 游戏实体：建筑 / 单位 / 炮弹 / 特效 ============
import { BType, UType, BSpec, USpec, BSPECS, USPECS } from './Config';
import { Vec2 } from './World';

export class Entity {
  id: number;
  team: number;
  hp: number;
  maxHp: number;

  constructor(id: number, team: number, hp: number) {
    this.id = id;
    this.team = team;
    this.hp = hp;
    this.maxHp = hp;
  }

  isDead(): boolean {
    return this.hp <= 0;
  }
}

export class Building extends Entity {
  btype: number;
  tx: number;
  ty: number;
  cool: number = 0; // 防御塔开火冷却

  constructor(id: number, team: number, btype: number, tx: number, ty: number) {
    super(id, team, BSPECS[btype].hp);
    this.btype = btype;
    this.tx = tx;
    this.ty = ty;
  }

  spec(): BSpec {
    return BSPECS[this.btype];
  }

  cx(): number {
    return this.tx + this.spec().w / 2;
  }

  cy(): number {
    return this.ty + this.spec().h / 2;
  }
}

export enum UState {
  IDLE = 0,
  MOVE = 1,
  TO_ORE = 2,
  HARVEST = 3,
  TO_REF = 4,
  UNLOAD = 5
}

export class Unit extends Entity {
  utype: number;
  x: number;          // 世界坐标（瓦片为单位，中心制）
  y: number;
  fx: number = 1;     // 朝向
  fy: number = 0;
  path: Vec2[] = [];
  state: number = UState.IDLE;
  target: Entity | null = null;
  attackMove: boolean = false;
  destX: number = -1; // 攻击移动的最终目的地
  destY: number = -1;
  cool: number = 0;
  scanT: number = 0;
  repathT: number = 0;
  cargo: number = 0;      // 采矿车载货
  workT: number = 0;      // 采矿/卸货计时
  oreX: number = -1;
  oreY: number = -1;
  auto: boolean = false;   // 当前目标是否为自动索敌获得
  guardX: number = 0;      // 警戒锚点
  guardY: number = 0;
  hold: boolean = false;   // 静默待命：抑制自动索敌，直到收到新指令

  constructor(id: number, team: number, utype: number, x: number, y: number) {
    super(id, team, USPECS[utype].hp);
    this.utype = utype;
    this.x = x;
    this.y = y;
  }

  spec(): USpec {
    return USPECS[this.utype];
  }

  isCombat(): boolean {
    return this.utype !== UType.HARVESTER;
  }
}

export class Projectile {
  x: number;
  y: number;
  speed: number;
  damage: number;
  team: number;
  rocket: boolean;
  target: Entity | null;
  lastTx: number;
  lastTy: number;
  alive: boolean = true;

  constructor(x: number, y: number, target: Entity, tx: number, ty: number,
              damage: number, team: number, rocket: boolean) {
    this.x = x;
    this.y = y;
    this.target = target;
    this.lastTx = tx;
    this.lastTy = ty;
    this.damage = damage;
    this.team = team;
    this.rocket = rocket;
    this.speed = rocket ? 7 : 12;
  }
}

export class Fx {
  x: number;
  y: number;
  age: number = 0;
  dur: number;
  size: number;

  constructor(x: number, y: number, dur: number, size: number) {
    this.x = x;
    this.y = y;
    this.dur = dur;
    this.size = size;
  }
}
