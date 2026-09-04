// ============ 回放持久化：应用私有目录文件存储 + 元数据索引 ============
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReplayData, ReplayMeta } from './Replay';

const MAX_RECORDS: number = 20;

export class ReplayStore {
  private static dir(ctx: common.UIAbilityContext): string {
    return ctx.filesDir + '/replays';
  }

  private static repPath(ctx: common.UIAbilityContext, id: number): string {
    return ReplayStore.dir(ctx) + '/rep_' + id + '.json';
  }

  private static indexPath(ctx: common.UIAbilityContext): string {
    return ReplayStore.dir(ctx) + '/index.json';
  }

  private static ensureDir(ctx: common.UIAbilityContext): void {
    const d = ReplayStore.dir(ctx);
    try {
      fs.mkdirSync(d); // 已存在会抛异常，忽略即可
    } catch (e) {
    }
  }

  private static readText(path: string): string | null {
    try {
      const stat = fs.statSync(path); // 文件不存在会抛异常
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const dec = util.TextDecoder.create('utf-8');
      return dec.decodeToString(new Uint8Array(buf));
    } catch (e) {
      return null;
    }
  }

  private static writeText(path: string, text: string): boolean {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);
      return true;
    } catch (e) {
      hilog.error(0x0000, 'SteelStorm', 'writeText failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  private static unlink(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (e) {
    }
  }

  static list(ctx: common.UIAbilityContext): ReplayMeta[] {
    const txt = ReplayStore.readText(ReplayStore.indexPath(ctx));
    if (txt == null || txt.length === 0) {
      return [];
    }
    try {
      const arr = JSON.parse(txt) as ReplayMeta[];
      return arr != null ? arr : [];
    } catch (e) {
      return [];
    }
  }

  static load(ctx: common.UIAbilityContext, id: number): ReplayData | null {
    const txt = ReplayStore.readText(ReplayStore.repPath(ctx, id));
    if (txt == null) {
      return null;
    }
    try {
      return JSON.parse(txt) as ReplayData;
    } catch (e) {
      return null;
    }
  }

  static save(ctx: common.UIAbilityContext, data: ReplayData): void {
    ReplayStore.ensureDir(ctx);
    if (!ReplayStore.writeText(ReplayStore.repPath(ctx, data.meta.id), JSON.stringify(data))) {
      return;
    }
    const metas = ReplayStore.list(ctx);
    metas.unshift(data.meta);
    // 裁剪：超过上限，删最旧文件与条目
    while (metas.length > MAX_RECORDS) {
      const old = metas.pop();
      if (old != null) {
        ReplayStore.unlink(ReplayStore.repPath(ctx, old.id));
      }
    }
    ReplayStore.writeText(ReplayStore.indexPath(ctx), JSON.stringify(metas));
  }

  static deleteMany(ctx: common.UIAbilityContext, ids: number[]): void {
    const metas = ReplayStore.list(ctx);
    const kept: ReplayMeta[] = [];
    for (let i = 0; i < metas.length; i++) {
      if (ids.indexOf(metas[i].id) >= 0) {
        ReplayStore.unlink(ReplayStore.repPath(ctx, metas[i].id));
      } else {
        kept.push(metas[i]);
      }
    }
    ReplayStore.writeText(ReplayStore.indexPath(ctx), JSON.stringify(kept));
  }
}
