// ============ 全局数值配置（数据驱动，所有平衡性调整都在这里） ============

export const TILE_W: number = 52;     // 等距瓦片宽
export const TILE_H: number = 26;     // 等距瓦片高
export const TW2: number = TILE_W / 2;
export const TH2: number = TILE_H / 2;
export const MAP_W: number = 44;
export const MAP_H: number = 44;

export enum Team { PLAYER = 0, ENEMY = 1 }
export enum Terrain { GRASS = 0, ROCK = 1, WATER = 2 }

export enum BType { CONYARD = 0, POWER = 1, REFINERY = 2, BARRACKS = 3, FACTORY = 4, TURRET = 5 }
export enum UType { RIFLE = 0, ROCKET = 1, TANK = 2, HEAVY = 3, HARVESTER = 4 }

// ---------------- 建筑规格 ----------------
export class BSpec {
  type: BType;
  name: string;
  cost: number;
  hp: number;
  power: number;      // 正=发电，负=耗电
  w: number;
  h: number;
  buildTime: number;  // 秒
  needs: BType[];     // 前置建筑
  color: string;
  range: number;      // 防御建筑射程（瓦片）
  damage: number;
  cooldown: number;

  constructor(t: BType, name: string, cost: number, hp: number, power: number,
              w: number, h: number, bt: number, needs: BType[], color: string,
              range: number = 0, damage: number = 0, cooldown: number = 0) {
    this.type = t;
    this.name = name;
    this.cost = cost;
    this.hp = hp;
    this.power = power;
    this.w = w;
    this.h = h;
    this.buildTime = bt;
    this.needs = needs;
    this.color = color;
    this.range = range;
    this.damage = damage;
    this.cooldown = cooldown;
  }
}

// ---------------- 单位规格 ----------------
export class USpec {
  type: UType;
  name: string;
  cost: number;
  hp: number;
  speed: number;      // 瓦片/秒
  range: number;
  damage: number;
  cooldown: number;
  buildTime: number;
  sight: number;
  vehicle: boolean;   // true=战车工厂生产
  color: string;

  constructor(t: UType, name: string, cost: number, hp: number, speed: number,
              range: number, damage: number, cooldown: number, bt: number,
              sight: number, vehicle: boolean, color: string) {
    this.type = t;
    this.name = name;
    this.cost = cost;
    this.hp = hp;
    this.speed = speed;
    this.range = range;
    this.damage = damage;
    this.cooldown = cooldown;
    this.buildTime = bt;
    this.sight = sight;
    this.vehicle = vehicle;
    this.color = color;
  }
}

// 军用材质配色：两阵营共用材质色，阵营靠描边色(TEAM_COLOR)+角旗区分（红警式战场感）
export const BSPECS: BSpec[] = [
  new BSpec(BType.CONYARD, '建造厂', 3000, 1600, 20, 3, 3, 30, [], '#8d9199'),        // 钢铁灰
  new BSpec(BType.POWER, '发电厂', 600, 600, 100, 2, 2, 8, [], '#4a6076'),            // 工业石板蓝
  new BSpec(BType.REFINERY, '矿石精炼厂', 2000, 1000, -30, 3, 2, 15, [BType.POWER], '#9c7b3e'), // 锈迹卡其
  new BSpec(BType.BARRACKS, '兵营', 500, 700, -10, 2, 2, 8, [BType.POWER], '#6b7340'),         // 橄榄军绿
  new BSpec(BType.FACTORY, '战车工厂', 2000, 1200, -30, 3, 3, 18, [BType.REFINERY], '#5a636e'), // 枪铁灰
  new BSpec(BType.TURRET, '防御炮塔', 1000, 800, -40, 1, 1, 10, [BType.BARRACKS], '#8a8d86', 6, 40, 1.2) // 混凝土
];

export const USPECS: USpec[] = [
  new USpec(UType.RIFLE, '机枪兵', 200, 120, 1.7, 4, 9, 0.8, 4, 6, false, '#727a45'),    // 橄榄军装
  new USpec(UType.ROCKET, '火箭兵', 350, 100, 1.5, 5, 26, 1.8, 6, 6, false, '#7a6a38'),  // 沙黄军装
  new USpec(UType.TANK, '主战坦克', 900, 420, 2.2, 5, 36, 1.6, 9, 7, true, '#5e6772'),    // 枪铁
  new USpec(UType.HEAVY, '重型坦克', 1700, 820, 1.5, 5.5, 62, 2.2, 14, 7, true, '#6b6f5a'), // 重装橄榄钢
  new USpec(UType.HARVESTER, '采矿车', 1400, 650, 1.8, 0, 0, 0, 10, 6, true, '#9c7f3c')   // 工业土黄
];

// 玩家侧边栏可建造列表
export const BUILD_LIST: number[] = [BType.POWER, BType.REFINERY, BType.BARRACKS, BType.FACTORY, BType.TURRET];
export const UNIT_LIST: number[] = [UType.RIFLE, UType.ROCKET, UType.TANK, UType.HEAVY, UType.HARVESTER];

// 经济参数
export const ORE_TILE_MAX: number = 900;       // 单格矿储量（即资金）
export const HARVEST_CAPACITY: number = 700;   // 矿车载量
export const HARVEST_RATE: number = 170;       // 采集速度 资金/秒
export const UNLOAD_TIME: number = 1.0;        // 卸矿耗时
export const LOW_POWER_FACTOR: number = 0.45;  // 缺电时生产速度
export const START_MONEY_PLAYER: number = 8000;
export const START_MONEY_ENEMY: number = 8000;

export const TEAM_COLOR: string[] = ['#3aa0ff', '#e0524f'];
