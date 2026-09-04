// ============ 地图 / 矿区 / 战争迷雾 / A* 寻路 ============
import { MAP_W, MAP_H, Terrain, ORE_TILE_MAX } from './Config';

export class Vec2 {
  x: number;
  y: number;
  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

export class GameMap {
  terrain: Int8Array = new Int8Array(MAP_W * MAP_H);
  ore: Int32Array = new Int32Array(MAP_W * MAP_H);
  occupied: Int32Array = new Int32Array(MAP_W * MAP_H); // 建筑id+1，0=空
  explored: Int8Array = new Int8Array(MAP_W * MAP_H);   // 玩家已探索

  idx(x: number, y: number): number {
    return y * MAP_W + x;
  }

  inBounds(x: number, y: number): boolean {
    return x >= 0 && y >= 0 && x < MAP_W && y < MAP_H;
  }

  terrainAt(x: number, y: number): number {
    return this.terrain[this.idx(x, y)];
  }

  oreAt(x: number, y: number): number {
    return this.ore[this.idx(x, y)];
  }

  isExplored(x: number, y: number): boolean {
    return this.explored[this.idx(x, y)] !== 0;
  }

  isPassable(x: number, y: number): boolean {
    if (!this.inBounds(x, y)) {
      return false;
    }
    const i = this.idx(x, y);
    return this.terrain[i] === Terrain.GRASS && this.occupied[i] === 0;
  }

  takeOre(x: number, y: number, amount: number): number {
    const i = this.idx(x, y);
    const t = Math.min(this.ore[i], amount);
    this.ore[i] = this.ore[i] - t;
    return t;
  }

  reveal(cx: number, cy: number, r: number): void {
    const x0 = Math.max(0, Math.floor(cx - r));
    const x1 = Math.min(MAP_W - 1, Math.ceil(cx + r));
    const y0 = Math.max(0, Math.floor(cy - r));
    const y1 = Math.min(MAP_H - 1, Math.ceil(cy + r));
    const r2 = r * r;
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const dx = x + 0.5 - cx;
        const dy = y + 0.5 - cy;
        if (dx * dx + dy * dy <= r2) {
          this.explored[this.idx(x, y)] = 1;
        }
      }
    }
  }

  // 以(x,y)为中心螺旋外扩寻找最近的有矿且可通行的格子
  findNearestOre(x: number, y: number, maxR: number): Vec2 | null {
    const cx = Math.floor(x);
    const cy = Math.floor(y);
    for (let r = 0; r <= maxR; r++) {
      let best: Vec2 | null = null;
      let bestD = Number.POSITIVE_INFINITY;
      for (let dy = -r; dy <= r; dy++) {
        for (let dx = -r; dx <= r; dx++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) {
            continue; // 只扫描环
          }
          const tx = cx + dx;
          const ty = cy + dy;
          if (!this.inBounds(tx, ty)) {
            continue;
          }
          const i = this.idx(tx, ty);
          if (this.ore[i] > 0 && this.terrain[i] === Terrain.GRASS && this.occupied[i] === 0) {
            const d = dx * dx + dy * dy;
            if (d < bestD) {
              bestD = d;
              best = new Vec2(tx, ty);
            }
          }
        }
      }
      if (best != null) {
        return best;
      }
    }
    return null;
  }

  private blob(cx: number, cy: number, r: number, kind: number): void {
    for (let y = cy - r; y <= cy + r; y++) {
      for (let x = cx - r; x <= cx + r; x++) {
        if (!this.inBounds(x, y)) {
          continue;
        }
        const dx = x - cx;
        const dy = y - cy;
        if (dx * dx + dy * dy <= r * r + Math.random() * 2) {
          this.terrain[this.idx(x, y)] = kind;
        }
      }
    }
  }

  private oreBlob(cx: number, cy: number, r: number): void {
    for (let y = cy - r; y <= cy + r; y++) {
      for (let x = cx - r; x <= cx + r; x++) {
        if (!this.inBounds(x, y)) {
          continue;
        }
        const dx = x - cx;
        const dy = y - cy;
        if (dx * dx + dy * dy <= r * r + Math.random() * 1.5) {
          const i = this.idx(x, y);
          if (this.terrain[i] === Terrain.GRASS) {
            this.ore[i] = Math.floor(ORE_TILE_MAX * (0.6 + Math.random() * 0.4));
          }
        }
      }
    }
  }

  private nearProtected(x: number, y: number, pts: Vec2[], r: number): boolean {
    for (let i = 0; i < pts.length; i++) {
      const dx = x - pts[i].x;
      const dy = y - pts[i].y;
      if (dx * dx + dy * dy < r * r) {
        return true;
      }
    }
    return false;
  }

  generate(): void {
    this.terrain.fill(Terrain.GRASS);
    this.ore.fill(0);
    this.occupied.fill(0);
    this.explored.fill(0);

    // 基地保护区（玩家左下，敌军右上）
    const protectedPts: Vec2[] = [new Vec2(7, 36), new Vec2(36, 7)];

    // 随机岩石群
    for (let i = 0; i < 9; i++) {
      const x = 3 + Math.floor(Math.random() * (MAP_W - 6));
      const y = 3 + Math.floor(Math.random() * (MAP_H - 6));
      if (this.nearProtected(x, y, protectedPts, 10)) {
        continue;
      }
      this.blob(x, y, 1 + Math.floor(Math.random() * 2), Terrain.ROCK);
    }
    // 两片水域
    this.blob(22, 4, 2, Terrain.WATER);
    this.blob(22, 40, 2, Terrain.WATER);

    // 矿区：双方基地附近 + 中央富矿 + 两个争夺点
    this.oreBlob(13, 37, 3);
    this.oreBlob(8, 28, 2);
    this.oreBlob(30, 7, 3);
    this.oreBlob(36, 16, 2);
    this.oreBlob(22, 22, 4);
    this.oreBlob(36, 36, 3);
    this.oreBlob(8, 8, 3);
  }
}

// ---------------- A* 寻路（8方向，禁止切角，终点不可达时回退到最近可行格） ----------------
export class PathFinder {
  static find(map: GameMap, sx: number, sy: number, txIn: number, tyIn: number): Vec2[] {
    let tx = txIn;
    let ty = tyIn;
    if (!map.inBounds(tx, ty)) {
      tx = Math.max(0, Math.min(MAP_W - 1, tx));
      ty = Math.max(0, Math.min(MAP_H - 1, ty));
    }
    // 终点不可通行：环形搜索最近替代点
    if (!map.isPassable(tx, ty)) {
      let found = false;
      for (let r = 1; r <= 6 && !found; r++) {
        for (let dy = -r; dy <= r && !found; dy++) {
          for (let dx = -r; dx <= r && !found; dx++) {
            if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) {
              continue;
            }
            if (map.isPassable(tx + dx, ty + dy)) {
              tx = tx + dx;
              ty = ty + dy;
              found = true;
            }
          }
        }
      }
      if (!found) {
        return [];
      }
    }
    if (sx === tx && sy === ty) {
      return [];
    }

    const n = MAP_W * MAP_H;
    const g = new Float32Array(n);
    g.fill(1e9);
    const parent = new Int32Array(n);
    parent.fill(-1);
    const closed = new Uint8Array(n);
    const open: number[] = [];
    const f = new Float32Array(n);

    const si = sy * MAP_W + sx;
    const ti = ty * MAP_W + tx;
    g[si] = 0;
    f[si] = PathFinder.heur(sx, sy, tx, ty);
    open.push(si);

    const dxs: number[] = [1, -1, 0, 0, 1, 1, -1, -1];
    const dys: number[] = [0, 0, 1, -1, 1, -1, 1, -1];
    const costs: number[] = [1, 1, 1, 1, 1.414, 1.414, 1.414, 1.414];

    let expansions = 0;
    while (open.length > 0 && expansions < 6000) {
      // 取f最小
      let bi = 0;
      for (let i = 1; i < open.length; i++) {
        if (f[open[i]] < f[open[bi]]) {
          bi = i;
        }
      }
      const cur = open[bi];
      open[bi] = open[open.length - 1];
      open.pop();
      if (closed[cur] === 1) {
        continue;
      }
      closed[cur] = 1;
      expansions++;
      if (cur === ti) {
        break;
      }
      const cx = cur % MAP_W;
      const cy = Math.floor(cur / MAP_W);
      for (let k = 0; k < 8; k++) {
        const nx = cx + dxs[k];
        const ny = cy + dys[k];
        if (!map.isPassable(nx, ny)) {
          continue;
        }
        // 禁止切角
        if (k >= 4) {
          if (!map.isPassable(cx + dxs[k], cy) || !map.isPassable(cx, cy + dys[k])) {
            continue;
          }
        }
        const ni = ny * MAP_W + nx;
        if (closed[ni] === 1) {
          continue;
        }
        const ng = g[cur] + costs[k];
        if (ng < g[ni]) {
          g[ni] = ng;
          f[ni] = ng + PathFinder.heur(nx, ny, tx, ty);
          parent[ni] = cur;
          open.push(ni);
        }
      }
    }

    if (parent[ti] === -1 && ti !== si) {
      return [];
    }
    const path: Vec2[] = [];
    let cur2 = ti;
    while (cur2 !== si && cur2 !== -1) {
      path.push(new Vec2(cur2 % MAP_W, Math.floor(cur2 / MAP_W)));
      cur2 = parent[cur2];
    }
    path.reverse();
    return path;
  }

  private static heur(x: number, y: number, tx: number, ty: number): number {
    const dx = Math.abs(x - tx);
    const dy = Math.abs(y - ty);
    return Math.max(dx, dy) + 0.414 * Math.min(dx, dy);
  }
}
