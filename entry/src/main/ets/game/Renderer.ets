// ============ 等距渲染器：地形 / 迷雾 / 建筑 / 单位 / 炮弹 / 特效 / 小地图 ============
import {
  TILE_W, TILE_H, TW2, TH2, MAP_W, MAP_H,
  Team, Terrain, BType, UType, BSPECS, TEAM_COLOR
} from './Config';
import { Game } from './Game';
import { GameMap } from './World';
import { Building, Unit, Projectile, Fx, UState } from './Entities';
import { Snapshot } from './Replay';

// 相机：屏幕偏移（像素）
export class Camera {
  ox: number = 0;
  oy: number = 0;
}

// 建筑放置预览
export class Ghost {
  active: boolean = false;
  bt: number = -1;
  tx: number = 0;
  ty: number = 0;
  ok: boolean = false;
}

// 渲染期间复用的可绘制对象（深度排序用）
class DrawItem {
  depth: number;
  isUnit: boolean;
  unit: Unit | null;
  building: Building | null;

  constructor(depth: number, unit: Unit | null, building: Building | null) {
    this.depth = depth;
    this.isUnit = unit != null;
    this.unit = unit;
    this.building = building;
  }
}

const MINI_X: number = 8;       // 小地图在画布内位置
const MINI_Y: number = 40;
const MINI_SIZE: number = 110;
const MINI_SCALE: number = MINI_SIZE / MAP_W;

export class Renderer {
  cam: Camera = new Camera();
  ghost: Ghost = new Ghost();

  // 世界(瓦片) -> 屏幕(像素)
  sx(wx: number, wy: number): number {
    return (wx - wy) * TW2 + this.cam.ox;
  }

  sy(wx: number, wy: number): number {
    return (wx + wy) * TH2 + this.cam.oy;
  }

  // 屏幕 -> 世界
  worldX(px: number, py: number): number {
    const dx = px - this.cam.ox;
    const dy = py - this.cam.oy;
    return (dx / TW2 + dy / TH2) / 2;
  }

  worldY(px: number, py: number): number {
    const dx = px - this.cam.ox;
    const dy = py - this.cam.oy;
    return (dy / TH2 - dx / TW2) / 2;
  }

  centerOn(wx: number, wy: number, viewW: number, viewH: number): void {
    this.cam.ox = viewW / 2 - (wx - wy) * TW2;
    this.cam.oy = viewH / 2 - (wx + wy) * TH2;
  }

  // 限制相机：保证视口中心落在地图范围内
  clampCam(viewW: number, viewH: number): void {
    const cx = this.worldX(viewW / 2, viewH / 2);
    const cy = this.worldY(viewW / 2, viewH / 2);
    const nx = Math.max(0, Math.min(MAP_W, cx));
    const ny = Math.max(0, Math.min(MAP_H, cy));
    if (nx !== cx || ny !== cy) {
      this.centerOn(nx, ny, viewW, viewH);
    }
  }

  isMiniHit(px: number, py: number): boolean {
    return px >= MINI_X && px <= MINI_X + MINI_SIZE && py >= MINI_Y && py <= MINI_Y + MINI_SIZE;
  }

  miniToWorldX(px: number): number {
    return (px - MINI_X) / MINI_SCALE;
  }

  miniToWorldY(py: number): number {
    return (py - MINI_Y) / MINI_SCALE;
  }

  // ---------------- 主渲染入口 ----------------
  draw(ctx: CanvasRenderingContext2D, g: Game, selIds: number[], viewW: number, viewH: number): void {
    ctx.fillStyle = '#05070a';
    ctx.fillRect(0, 0, viewW, viewH);
    this.drawTerrain(ctx, g.map, viewW, viewH, true);
    this.drawEntities(ctx, g.buildings, g.units, g.map, selIds, viewW, viewH, true);
    this.drawShots(ctx, g);
    this.drawFx(ctx, g);
    if (this.ghost.active) {
      this.drawGhost(ctx, g);
    }
    this.drawMinimap(ctx, g.buildings, g.units, g.map, viewW, viewH, true);
  }

  // ---------------- 回放渲染：由快照重建临时实体，复用同一套绘制（上帝视角，无迷雾/特效） ----------------
  drawReplay(ctx: CanvasRenderingContext2D, snap: Snapshot, map: GameMap, viewW: number, viewH: number): void {
    ctx.fillStyle = '#05070a';
    ctx.fillRect(0, 0, viewW, viewH);
    this.drawTerrain(ctx, map, viewW, viewH, false);
    const buildings: Building[] = [];
    for (let i = 0; i < snap.b.length; i++) {
      const r = snap.b[i];
      const b = new Building(i + 1, r.tm, r.bt, r.x, r.y);
      b.hp = r.hp;
      buildings.push(b);
    }
    const units: Unit[] = [];
    for (let i = 0; i < snap.u.length; i++) {
      const r = snap.u[i];
      const u = new Unit(i + 1, r.tm, r.ut, r.x, r.y);
      u.hp = r.hp;
      u.fx = r.fx;
      u.fy = r.fy;
      u.cargo = r.cg;
      units.push(u);
    }
    this.drawEntities(ctx, buildings, units, map, [], viewW, viewH, false);
    this.drawMinimap(ctx, buildings, units, map, viewW, viewH, false);
  }

  // ---------------- 地形与迷雾（fog=false 时全图可见，用于回放上帝视角） ----------------
  private drawTerrain(ctx: CanvasRenderingContext2D, map: GameMap, viewW: number, viewH: number, fog: boolean): void {
    for (let y = 0; y < MAP_H; y++) {
      for (let x = 0; x < MAP_W; x++) {
        const px = this.sx(x + 0.5, y + 0.5);
        const py = this.sy(x + 0.5, y + 0.5);
        // 屏外剔除
        if (px < -TILE_W || px > viewW + TILE_W || py < -TILE_H * 2 || py > viewH + TILE_H * 2) {
          continue;
        }
        if (fog && !map.isExplored(x, y)) {
          this.diamond(ctx, px, py, '#05070a');
          continue;
        }
        const t = map.terrainAt(x, y);
        let color = '#3e5a36';
        if (t === Terrain.ROCK) {
          color = '#5a5752';
        } else if (t === Terrain.WATER) {
          color = '#26415e';
        }
        const checker = ((x + y) % 2 === 0);
        this.diamond(ctx, px, py, color, checker);
        const ore = map.oreAt(x, y);
        if (ore > 0) {
          // 矿石：金色小晶簇，密度随储量
          const ratio = ore / 900;
          ctx.fillStyle = '#caa13c';
          const n = 2 + Math.floor(ratio * 3);
          for (let k = 0; k < n; k++) {
            const a = (x * 7 + y * 13 + k * 5) % 10 / 10 * Math.PI * 2;
            const r = 3 + ((x * 3 + k * 7) % 5);
            ctx.beginPath();
            ctx.ellipse(px + Math.cos(a) * r * 1.6, py + Math.sin(a) * r * 0.8, 3, 1.8, 0, 0, Math.PI * 2);
            ctx.fill();
          }
        }
      }
    }
  }

  private diamond(ctx: CanvasRenderingContext2D, cx: number, cy: number, color: string, darker: boolean = false): void {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(cx, cy - TH2);
    ctx.lineTo(cx + TW2, cy);
    ctx.lineTo(cx, cy + TH2);
    ctx.lineTo(cx - TW2, cy);
    ctx.closePath();
    ctx.fill();
    if (darker) {
      ctx.fillStyle = 'rgba(0,0,0,0.06)';
      ctx.fill();
    }
  }

  // ---------------- 实体（深度排序） ----------------
  private drawEntities(ctx: CanvasRenderingContext2D, buildings: Building[], units: Unit[], map: GameMap,
                       selIds: number[], viewW: number, viewH: number, fog: boolean): void {
    const items: DrawItem[] = [];
    for (let i = 0; i < buildings.length; i++) {
      const b = buildings[i];
      if (fog && b.team === Team.ENEMY && !map.isExplored(b.tx, b.ty)) {
        continue;
      }
      items.push(new DrawItem(b.cx() + b.cy(), null, b));
    }
    for (let i = 0; i < units.length; i++) {
      const u = units[i];
      if (fog && u.team === Team.ENEMY && !map.isExplored(Math.floor(u.x), Math.floor(u.y))) {
        continue;
      }
      items.push(new DrawItem(u.x + u.y, u, null));
    }
    items.sort((a: DrawItem, b: DrawItem): number => a.depth - b.depth);
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      if (it.isUnit && it.unit != null) {
        this.drawUnit(ctx, it.unit, selIds);
      } else if (it.building != null) {
        this.drawBuilding(ctx, it.building, viewW, viewH);
      }
    }
  }

  private shade(hex: string, f: number): string {
    // hex: #rrggbb，f<1 变暗 f>1 变亮
    const r = Math.min(255, Math.floor(parseInt(hex.substring(1, 3), 16) * f));
    const gg = Math.min(255, Math.floor(parseInt(hex.substring(3, 5), 16) * f));
    const b = Math.min(255, Math.floor(parseInt(hex.substring(5, 7), 16) * f));
    return 'rgb(' + r + ',' + gg + ',' + b + ')';
  }

  private drawBuilding(ctx: CanvasRenderingContext2D, b: Building, viewW: number, viewH: number): void {
    const spec = b.spec();
    const x0 = b.tx;
    const y0 = b.ty;
    const x1 = b.tx + spec.w;
    const y1 = b.ty + spec.h;
    const pTopX = this.sx(x0, y0);
    const pTopY = this.sy(x0, y0);
    if (pTopX < -200 || pTopX > viewW + 200 || pTopY < -200 || pTopY > viewH + 200) {
      return;
    }
    const pRX = this.sx(x1, y0);
    const pRY = this.sy(x1, y0);
    const pBX = this.sx(x1, y1);
    const pBY = this.sy(x1, y1);
    const pLX = this.sx(x0, y1);
    const pLY = this.sy(x0, y1);
    const hgt = b.btype === BType.TURRET ? 14 : (spec.w >= 3 ? 26 : 20); // 立体高度
    // 底座
    ctx.fillStyle = this.shade(spec.color, 0.45);
    ctx.beginPath();
    ctx.moveTo(pTopX, pTopY);
    ctx.lineTo(pRX, pRY);
    ctx.lineTo(pBX, pBY);
    ctx.lineTo(pLX, pLY);
    ctx.closePath();
    ctx.fill();
    // 左侧面
    ctx.fillStyle = this.shade(spec.color, 0.62);
    ctx.beginPath();
    ctx.moveTo(pLX, pLY - hgt);
    ctx.lineTo(pBX, pBY - hgt);
    ctx.lineTo(pBX, pBY);
    ctx.lineTo(pLX, pLY);
    ctx.closePath();
    ctx.fill();
    // 右侧面
    ctx.fillStyle = this.shade(spec.color, 0.8);
    ctx.beginPath();
    ctx.moveTo(pRX, pRY - hgt);
    ctx.lineTo(pBX, pBY - hgt);
    ctx.lineTo(pBX, pBY);
    ctx.lineTo(pRX, pRY);
    ctx.closePath();
    ctx.fill();
    // 顶面
    ctx.fillStyle = this.shade(spec.color, 1.05);
    ctx.beginPath();
    ctx.moveTo(pTopX, pTopY - hgt);
    ctx.lineTo(pRX, pRY - hgt);
    ctx.lineTo(pBX, pBY - hgt);
    ctx.lineTo(pLX, pLY - hgt);
    ctx.closePath();
    ctx.fill();
    // 队伍色描边
    ctx.strokeStyle = TEAM_COLOR[b.team];
    ctx.lineWidth = 1.5;
    ctx.stroke();
    const ccx = this.sx(b.cx(), b.cy());
    const ccy = this.sy(b.cx(), b.cy()) - hgt;
    const halfW = (pRX - pLX) / 2;
    const halfH = (pBY - pTopY) / 2;
    if (b.btype === BType.TURRET) {
      // 防御炮塔：混凝土碉堡上的沙袋环 + 旋转炮塔 + 炮管
      ctx.fillStyle = '#9a8b55';
      ctx.beginPath();
      ctx.ellipse(ccx, ccy + 4, 13, 6, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#3a3d39';
      ctx.beginPath();
      ctx.arc(ccx, ccy, 7, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = '#23241f';
      ctx.lineWidth = 1.4;
      ctx.stroke();
      ctx.strokeStyle = '#202020';
      ctx.lineWidth = 3.4;
      ctx.beginPath();
      ctx.moveTo(ccx, ccy);
      ctx.lineTo(ccx + 15, ccy - 5);
      ctx.stroke();
    } else {
      // 各建筑专属军事化屋顶细节 + 阵营角旗
      this.drawRoof(ctx, b, ccx, ccy, halfW, halfH);
      const fx = pTopX;
      const fy = pTopY - hgt;
      ctx.strokeStyle = '#d6d6cc';
      ctx.lineWidth = 1.3;
      ctx.beginPath();
      ctx.moveTo(fx, fy);
      ctx.lineTo(fx, fy - 13);
      ctx.stroke();
      ctx.fillStyle = TEAM_COLOR[b.team];
      ctx.beginPath();
      ctx.moveTo(fx, fy - 13);
      ctx.lineTo(fx + 9, fy - 10.5);
      ctx.lineTo(fx, fy - 8);
      ctx.closePath();
      ctx.fill();
    }
    // 血条（受损才显示）
    if (b.hp < b.maxHp) {
      this.hpBar(ctx, ccx, pTopY - hgt - 8, 36, b.hp / b.maxHp);
    }
  }

  // 竖直烟囱/筒仓
  private stack(ctx: CanvasRenderingContext2D, x: number, baseY: number, w: number, h: number, body: string, top: string): void {
    ctx.fillStyle = body;
    ctx.fillRect(x - w / 2, baseY - h, w, h);
    ctx.fillStyle = top;
    ctx.beginPath();
    ctx.ellipse(x, baseY - h, w / 2, w / 4, 0, 0, Math.PI * 2);
    ctx.fill();
  }

  // 蒸汽/烟雾
  private steam(ctx: CanvasRenderingContext2D, x: number, y: number): void {
    ctx.fillStyle = 'rgba(206,214,224,0.30)';
    ctx.beginPath();
    ctx.arc(x, y, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x + 3, y - 7, 5, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x - 1, y - 14, 3.4, 0, Math.PI * 2);
    ctx.fill();
  }

  // 建筑屋顶军事化细节（绘制在顶面中心 cx,cy；halfW/halfH 为顶面菱形半径）
  private drawRoof(ctx: CanvasRenderingContext2D, b: Building, cx: number, cy: number, halfW: number, halfH: number): void {
    const t = b.btype;
    const base = b.spec().color;
    if (t === BType.BARRACKS) {
      // 帐篷营房：脊线 + 棚布肋 + 营门
      ctx.strokeStyle = this.shade(base, 1.3);
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(cx, cy - halfH * 0.55);
      ctx.lineTo(cx, cy + halfH * 0.55);
      ctx.stroke();
      ctx.strokeStyle = this.shade(base, 0.65);
      ctx.lineWidth = 1;
      for (let i = -1; i <= 1; i++) {
        ctx.beginPath();
        ctx.moveTo(cx - halfW * 0.4, cy + i * halfH * 0.3);
        ctx.lineTo(cx + halfW * 0.4, cy + i * halfH * 0.3);
        ctx.stroke();
      }
      ctx.fillStyle = '#23301a';
      ctx.fillRect(cx - 4, cy + halfH * 0.2, 8, halfH * 0.5);
    } else if (t === BType.POWER) {
      // 发电厂：两座冷却塔 + 蒸汽 + 警戒黄条
      this.stack(ctx, cx - halfW * 0.3, cy + 2, 9, 11, '#33485f', '#5b7ba0');
      this.stack(ctx, cx + halfW * 0.32, cy + 5, 9, 11, '#33485f', '#5b7ba0');
      this.steam(ctx, cx - halfW * 0.3, cy - 12);
      this.steam(ctx, cx + halfW * 0.32, cy - 9);
      ctx.strokeStyle = '#caa83a';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(cx - halfW * 0.5, cy + halfH * 0.45);
      ctx.lineTo(cx + halfW * 0.5, cy + halfH * 0.15);
      ctx.stroke();
    } else if (t === BType.REFINERY) {
      // 矿石精炼厂：储料筒仓 + 烟囱 + 卸料口
      this.stack(ctx, cx - halfW * 0.35, cy, 14, 16, '#7d6531', '#b89248');
      this.stack(ctx, cx + halfW * 0.35, cy + 4, 6, 18, '#3a3326', '#5a5040');
      this.steam(ctx, cx + halfW * 0.35, cy - 17);
      ctx.fillStyle = '#2a2114';
      ctx.fillRect(cx - 5, cy + halfH * 0.35, 10, halfH * 0.4);
    } else if (t === BType.FACTORY) {
      // 战车工厂：双坡屋脊 + 天窗 + 齿轮徽 + 卷帘大门
      ctx.fillStyle = this.shade(base, 1.18);
      ctx.beginPath();
      ctx.moveTo(cx, cy - halfH * 0.6);
      ctx.lineTo(cx + halfW * 0.55, cy);
      ctx.lineTo(cx, cy + halfH * 0.6);
      ctx.lineTo(cx - halfW * 0.55, cy);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = '#8fb0c4';
      for (let i = -1; i <= 1; i++) {
        ctx.fillRect(cx - 3 + i * 9, cy - 3, 6, 6);
      }
      ctx.fillStyle = TEAM_COLOR[b.team];
      ctx.beginPath();
      ctx.arc(cx, cy + halfH * 0.06, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#26292e';
      ctx.fillRect(cx - 9, cy + halfH * 0.25, 18, halfH * 0.45);
    } else if (t === BType.CONYARD) {
      // 建造厂：停机坪斜纹 + 龙门吊 + 天线
      ctx.fillStyle = '#bfa23a';
      ctx.beginPath();
      ctx.moveTo(cx, cy - halfH * 0.45);
      ctx.lineTo(cx + halfW * 0.4, cy);
      ctx.lineTo(cx, cy + halfH * 0.45);
      ctx.lineTo(cx - halfW * 0.4, cy);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = '#1d1d1d';
      ctx.lineWidth = 2;
      for (let i = -1; i <= 1; i++) {
        ctx.beginPath();
        ctx.moveTo(cx - 10 + i * 8, cy - 6);
        ctx.lineTo(cx - 2 + i * 8, cy + 6);
        ctx.stroke();
      }
      ctx.strokeStyle = '#6a6f77';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.moveTo(cx - halfW * 0.5, cy + 4);
      ctx.lineTo(cx - halfW * 0.5, cy - 16);
      ctx.lineTo(cx + halfW * 0.1, cy - 10);
      ctx.stroke();
      ctx.strokeStyle = '#9aa3ab';
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.moveTo(cx + halfW * 0.4, cy - 2);
      ctx.lineTo(cx + halfW * 0.4, cy - 20);
      ctx.stroke();
      ctx.fillStyle = TEAM_COLOR[b.team];
      ctx.beginPath();
      ctx.arc(cx + halfW * 0.4, cy - 21, 2.2, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  private drawUnit(ctx: CanvasRenderingContext2D, u: Unit, selIds: number[]): void {
    const px = this.sx(u.x, u.y);
    const py = this.sy(u.x, u.y);
    const spec = u.spec();
    const tcol = TEAM_COLOR[u.team];
    let selected = false;
    for (let i = 0; i < selIds.length; i++) {
      if (selIds[i] === u.id) {
        selected = true;
        break;
      }
    }
    if (selected) {
      ctx.strokeStyle = '#7fffb0';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.ellipse(px, py + 2, 15, 8, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (spec.vehicle) {
      // 载具：朝向投影到等距空间的近似角
      const ang = Math.atan2(u.fy + u.fx, (u.fx - u.fy) * 2);
      ctx.fillStyle = 'rgba(0,0,0,0.22)';
      ctx.beginPath();
      ctx.ellipse(px, py + 6, 15, 6, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.save();
      ctx.translate(px, py - 4);
      ctx.rotate(ang);
      if (u.utype === UType.HARVESTER) {
        // 装甲采矿车：履带 + 车体 + 矿斗（载货指示）+ 驾驶舱
        ctx.fillStyle = '#23262a';
        ctx.fillRect(-12, -8, 24, 3.5);
        ctx.fillRect(-12, 4.5, 24, 3.5);
        ctx.fillStyle = this.shade(spec.color, 0.7);
        ctx.fillRect(-11, -5, 22, 10);
        ctx.fillStyle = '#5a4a22';
        ctx.fillRect(-8, -3.5, 13, 7);
        if (u.cargo > 0) {
          const w = 13 * Math.min(1, u.cargo / 700);
          ctx.fillStyle = '#e8c860';
          ctx.fillRect(-8, -3.5, w, 7);
        }
        ctx.fillStyle = this.shade(spec.color, 1.2);
        ctx.fillRect(6, -3, 5, 6);
        ctx.strokeStyle = tcol;
        ctx.lineWidth = 1.5;
        ctx.strokeRect(-11, -5, 22, 10);
      } else {
        // 坦克：履带(带齿) + 倾斜车体 + 旋转炮塔 + 炮管（重坦双管）
        const heavy: boolean = u.utype === UType.HEAVY;
        const len: number = heavy ? 13 : 11;
        ctx.fillStyle = '#202327';
        ctx.fillRect(-len, -8, len * 2, 3.6);
        ctx.fillRect(-len, 4.4, len * 2, 3.6);
        ctx.strokeStyle = '#0e0f11';
        ctx.lineWidth = 1;
        for (let i = -len + 2; i < len; i += 4) {
          ctx.beginPath();
          ctx.moveTo(i, -8);
          ctx.lineTo(i, -4.4);
          ctx.stroke();
          ctx.beginPath();
          ctx.moveTo(i, 4.4);
          ctx.lineTo(i, 8);
          ctx.stroke();
        }
        ctx.fillStyle = this.shade(spec.color, 0.78);
        ctx.beginPath();
        ctx.moveTo(-len + 1, -5);
        ctx.lineTo(len - 3, -5);
        ctx.lineTo(len, 0);
        ctx.lineTo(len - 3, 5);
        ctx.lineTo(-len + 1, 5);
        ctx.closePath();
        ctx.fill();
        ctx.fillStyle = spec.color;
        ctx.fillRect(-len + 2, -3.6, len * 2 - 6, 7.2);
        ctx.strokeStyle = tcol;
        ctx.lineWidth = 1.5;
        ctx.strokeRect(-len + 1, -5, len * 2 - 2, 10);
        ctx.fillStyle = this.shade(spec.color, 1.18);
        ctx.beginPath();
        ctx.arc(-1, 0, heavy ? 6 : 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#2a2d31';
        ctx.lineWidth = 1.2;
        ctx.stroke();
        ctx.strokeStyle = '#202020';
        if (heavy) {
          ctx.lineWidth = 2.4;
          ctx.beginPath();
          ctx.moveTo(0, -2);
          ctx.lineTo(16, -2);
          ctx.stroke();
          ctx.beginPath();
          ctx.moveTo(0, 2);
          ctx.lineTo(16, 2);
          ctx.stroke();
        } else {
          ctx.lineWidth = 2.6;
          ctx.beginPath();
          ctx.moveTo(0, 0);
          ctx.lineTo(15, 0);
          ctx.stroke();
        }
      }
      ctx.restore();
    } else {
      // 步兵：钢盔士兵 + 阵营臂章 + 武器
      ctx.fillStyle = 'rgba(0,0,0,0.22)';
      ctx.beginPath();
      ctx.ellipse(px, py + 3, 5.5, 2.6, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = spec.color;
      ctx.beginPath();
      ctx.moveTo(px - 3.5, py + 2);
      ctx.lineTo(px - 2.5, py - 4);
      ctx.lineTo(px + 2.5, py - 4);
      ctx.lineTo(px + 3.5, py + 2);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = tcol;
      ctx.fillRect(px - 3.2, py - 2.5, 6.4, 1.8);
      ctx.fillStyle = this.shade(spec.color, 1.25);
      ctx.beginPath();
      ctx.arc(px, py - 5, 3.2, Math.PI, 0);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = this.shade(spec.color, 0.55);
      ctx.fillRect(px - 3.4, py - 5.2, 6.8, 1.2);
      if (u.utype === UType.ROCKET) {
        ctx.strokeStyle = '#3a3a32';
        ctx.lineWidth = 2.6;
        ctx.beginPath();
        ctx.moveTo(px - 5, py - 3);
        ctx.lineTo(px + 6, py - 7);
        ctx.stroke();
        ctx.fillStyle = '#caa83a';
        ctx.beginPath();
        ctx.arc(px + 6, py - 7, 1.6, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.strokeStyle = '#2a2a26';
        ctx.lineWidth = 1.6;
        ctx.beginPath();
        ctx.moveTo(px + 1, py - 3);
        ctx.lineTo(px + 7, py - 5);
        ctx.stroke();
      }
    }
    // 血条
    if (u.hp < u.maxHp) {
      this.hpBar(ctx, px, py - 16, 24, u.hp / u.maxHp);
    }
  }

  private hpBar(ctx: CanvasRenderingContext2D, cx: number, y: number, w: number, ratio: number): void {
    ctx.fillStyle = 'rgba(0,0,0,0.7)';
    ctx.fillRect(cx - w / 2, y, w, 4);
    ctx.fillStyle = ratio > 0.5 ? '#56c25a' : (ratio > 0.25 ? '#d8b03c' : '#d8503c');
    ctx.fillRect(cx - w / 2 + 0.5, y + 0.5, (w - 1) * Math.max(0, ratio), 3);
  }

  // ---------------- 炮弹与特效 ----------------
  private drawShots(ctx: CanvasRenderingContext2D, g: Game): void {
    for (let i = 0; i < g.shots.length; i++) {
      const s = g.shots[i];
      const px = this.sx(s.x, s.y);
      const py = this.sy(s.x, s.y) - 6;
      if (s.rocket) {
        ctx.fillStyle = '#ffd070';
        ctx.beginPath();
        ctx.arc(px, py, 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = 'rgba(255,160,60,0.5)';
        ctx.beginPath();
        ctx.arc(px - 4, py + 2, 2, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.fillStyle = '#ffe9a0';
        ctx.fillRect(px - 1.5, py - 1.5, 3, 3);
      }
    }
  }

  private drawFx(ctx: CanvasRenderingContext2D, g: Game): void {
    for (let i = 0; i < g.fxs.length; i++) {
      const f = g.fxs[i];
      const t = f.age / f.dur;
      const px = this.sx(f.x, f.y);
      const py = this.sy(f.x, f.y) - 4;
      const r = f.size * (0.4 + t * 0.9);
      ctx.fillStyle = 'rgba(255,' + Math.floor(190 - t * 140) + ',40,' + (1 - t) * 0.85 + ')';
      ctx.beginPath();
      ctx.arc(px, py, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = 'rgba(60,60,60,' + (1 - t) * 0.4 + ')';
      ctx.beginPath();
      ctx.arc(px + 2, py - r * 0.6, r * 0.6, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // ---------------- 放置幽灵 ----------------
  private drawGhost(ctx: CanvasRenderingContext2D, g: Game): void {
    const spec = BSPECS[this.ghost.bt];
    const col = this.ghost.ok ? 'rgba(90,220,110,0.4)' : 'rgba(230,70,60,0.4)';
    const line = this.ghost.ok ? '#5adc6e' : '#e6463c';
    ctx.fillStyle = col;
    ctx.strokeStyle = line;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(this.sx(this.ghost.tx, this.ghost.ty), this.sy(this.ghost.tx, this.ghost.ty));
    ctx.lineTo(this.sx(this.ghost.tx + spec.w, this.ghost.ty), this.sy(this.ghost.tx + spec.w, this.ghost.ty));
    ctx.lineTo(this.sx(this.ghost.tx + spec.w, this.ghost.ty + spec.h), this.sy(this.ghost.tx + spec.w, this.ghost.ty + spec.h));
    ctx.lineTo(this.sx(this.ghost.tx, this.ghost.ty + spec.h), this.sy(this.ghost.tx, this.ghost.ty + spec.h));
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  }

  // ---------------- 小地图 ----------------
  private drawMinimap(ctx: CanvasRenderingContext2D, buildings: Building[], units: Unit[], map: GameMap,
                      viewW: number, viewH: number, fog: boolean): void {
    ctx.fillStyle = 'rgba(8,12,16,0.85)';
    ctx.fillRect(MINI_X - 2, MINI_Y - 2, MINI_SIZE + 4, MINI_SIZE + 4);
    ctx.fillStyle = '#1c2a1a';
    ctx.fillRect(MINI_X, MINI_Y, MINI_SIZE, MINI_SIZE);
    // 矿点
    ctx.fillStyle = '#9a7c2c';
    for (let y = 0; y < MAP_H; y += 2) {
      for (let x = 0; x < MAP_W; x += 2) {
        if ((!fog || map.isExplored(x, y)) && map.oreAt(x, y) > 0) {
          ctx.fillRect(MINI_X + x * MINI_SCALE, MINI_Y + y * MINI_SCALE, 2.4, 2.4);
        }
      }
    }
    // 未探索遮罩（粗粒度）
    if (fog) {
      ctx.fillStyle = 'rgba(0,0,0,0.75)';
      for (let y = 0; y < MAP_H; y += 2) {
        for (let x = 0; x < MAP_W; x += 2) {
          if (!map.isExplored(x, y)) {
            ctx.fillRect(MINI_X + x * MINI_SCALE, MINI_Y + y * MINI_SCALE, MINI_SCALE * 2, MINI_SCALE * 2);
          }
        }
      }
    }
    // 实体点
    for (let i = 0; i < buildings.length; i++) {
      const b = buildings[i];
      if (fog && b.team === Team.ENEMY && !map.isExplored(b.tx, b.ty)) {
        continue;
      }
      ctx.fillStyle = TEAM_COLOR[b.team];
      ctx.fillRect(MINI_X + b.tx * MINI_SCALE, MINI_Y + b.ty * MINI_SCALE, b.spec().w * MINI_SCALE, b.spec().h * MINI_SCALE);
    }
    for (let i = 0; i < units.length; i++) {
      const u = units[i];
      if (fog && u.team === Team.ENEMY && !map.isExplored(Math.floor(u.x), Math.floor(u.y))) {
        continue;
      }
      ctx.fillStyle = TEAM_COLOR[u.team];
      ctx.fillRect(MINI_X + u.x * MINI_SCALE - 1, MINI_Y + u.y * MINI_SCALE - 1, 2.4, 2.4);
    }
    // 视口框
    const cwx = this.worldX(viewW / 2, viewH / 2);
    const cwy = this.worldY(viewW / 2, viewH / 2);
    const vw = viewW / TILE_W;   // 视口在世界中的近似跨度
    const vh = viewH / TILE_H;
    ctx.strokeStyle = 'rgba(255,255,255,0.8)';
    ctx.lineWidth = 1;
    ctx.strokeRect(
      MINI_X + (cwx - vw / 2) * MINI_SCALE,
      MINI_Y + (cwy - vh / 2) * MINI_SCALE,
      vw * MINI_SCALE,
      vh * MINI_SCALE
    );
    ctx.strokeStyle = 'rgba(140,170,200,0.6)';
    ctx.strokeRect(MINI_X, MINI_Y, MINI_SIZE, MINI_SIZE);
  }
}
