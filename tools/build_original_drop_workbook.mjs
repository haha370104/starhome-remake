// Run a copy in the bundled artifact runtime workspace, passing the game repository as argv[2].
import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const root = path.resolve(process.argv[2]);
const read = async p => JSON.parse(await fs.readFile(path.join(root, p), 'utf8'));
const runtime = await read('.godot/content-audit-runtime.json');
const source = (await read('data/gameplay/glory/glory_monsters_v1.json')).definitions;
const bindings = (await read('data/gameplay/original_drop_bindings_v1.json')).definitions;
const byRaw = new Map(bindings.map(b => [b.source_class, b]));
const fragment = byRaw.get('接合器升级碎片').item_definition_id;
const encounters = new Map((await read('data/gameplay/glory/glory_monster_encounters_v1.json')).encounters.map(e => [e.map_id, e]));
const starter = await read('data/gameplay/stage3/d04_encounters_v1.json');
encounters.set(starter.map_id, starter);
const active = new Set([...encounters.values()].filter(e => e.enabled).flatMap(e => e.spawn_groups.filter(g => (g.weight ?? 1) > 0).map(g => g.monster_id)));
const activeSources = new Map(bindings.map(b => [b.item_definition_id, new Set()]));
const actualRows = [], overview = [], rawRows = [];
for (const monster of source) {
  const drops = runtime.monsters[monster.id].drops ?? [];
  const current = new Map(drops.map(d => [d.item_definition_id, d]));
  const enabled = active.has(monster.id) ? '已投放' : '未投放';
  const excluded = monster.source_drop_candidates.filter(c => !current.has(byRaw.get(c.display_name).item_definition_id)).length;
  overview.push([monster.display_name, monster.id, enabled, monster.source_drop_candidates.length,
    new Set(monster.source_drop_candidates.map(c => c.display_name)).size, drops.length, excluded,
    !drops.length ? '原表无候选；未补造掉落' : excluded ? '已配齐；非爬虫碎片按要求排除' : !monster.source_drop_candidates.length ? '用户增加爬虫碎片' : '原版候选已配齐']);
  for (const drop of drops) {
    if (active.has(monster.id)) activeSources.get(drop.item_definition_id).add(monster.id);
    const isFragment = drop.item_definition_id === fragment;
    actualRows.push([monster.display_name, monster.id, enabled, runtime.items[drop.item_definition_id].display_name,
      drop.minimum_quantity, drop.maximum_quantity, drop.chance, null,
      isFragment ? '用户例外：0～3各25%；仅两种爬虫及变体' : '单项独立抽取；同名重复候选仅抽一次', drop.item_definition_id]);
  }
  for (const candidate of monster.source_drop_candidates) {
    const binding = byRaw.get(candidate.display_name);
    const drop = current.get(binding.item_definition_id);
    rawRows.push([monster.display_name, monster.id, candidate.display_name, candidate.minimum_quantity,
      candidate.maximum_quantity, candidate.raw_weight, binding.display_name,
      drop ? '已配置' : '用户例外：排除非爬虫碎片', `npc_catalog.csv / index=${monster.source_audit.index}`]);
  }
}
if (actualRows.length !== 1134 || rawRows.length !== 1291 || overview.length !== 119 || bindings.length !== 79) throw Error('Unexpected report coverage');
const recipeInputs = new Set(runtime.recipes.flatMap(r => r.materials.map(m => m.definition_id)));
const upgradeInputs = new Set((await read('data/gameplay/commerce/attachment_upgrade_costs_v1.json')).rules.flatMap(r => [...r.premium_materials, ...r.normal_materials].map(m => m.definition_id)));
const taskInputs = new Set(Object.values(runtime.tasks).filter(t => t.kind === 2).map(t => t.target_id));
for (const task of (await read('data/gameplay/quests/repeatable_tasks_v1.json')).tasks) {
  for (const m of task.requirements ?? []) taskInputs.add(runtime.item_aliases[m.definition_id] ?? m.definition_id);
}
const itemRows = bindings.map(b => {
  const item = runtime.items[b.item_definition_id];
  const uses = [];
  if (item.use_rule) uses.push('补给使用');
  if (upgradeInputs.has(b.item_definition_id)) uses.push('接合器强化');
  if (recipeInputs.has(b.item_definition_id)) uses.push('制造原料');
  if (taskInputs.has(b.item_definition_id)) uses.push('任务交付');
  return [b.display_name, activeSources.get(b.item_definition_id).size, b.source_class,
    uses.length ? uses.join('、') : '可掉落/拾取/保存；原版专属用途未开放',
    item.description, b.item_definition_id, `${b.source_file}:${b.source_line}`];
});
const wb = Workbook.create();
function sheet(name, title, notes, headers, rows, widths) {
  const s = wb.worksheets.add(name);
  s.showGridLines = false;
  s.tabColor = '#0D6576';
  const end = String.fromCharCode(64 + headers.length);
  const last = rows.length + 7;
  const all = s.getRange(`A1:${end}${last}`);
  all.format.font = {name: 'Microsoft YaHei', size: 11, color: '#253749'};
  all.format.verticalAlignment = 'center';
  all.format.rowHeight = 25;
  all.format.wrapText = true;
  widths.forEach((w, i) => s.getRange(`${String.fromCharCode(65+i)}1:${String.fromCharCode(65+i)}${last}`).format.columnWidthPx = w);
  s.mergeCells(`A1:${end}1`);
  s.getRange('A1').values = [[title]];
  s.getRange(`A1:${end}1`).format = {fill: '#163C50', font: {name:'Microsoft YaHei', size:20, bold:true, color:'#FFFFFF'}, rowHeight:40};
  notes.forEach((note, i) => {
    const r = i + 2;
    s.mergeCells(`A${r}:${end}${r}`);
    s.getRange(`A${r}`).values = [[note]];
    s.getRange(`A${r}:${end}${r}`).format.rowHeight = 27;
    s.getRange(`A${r}:${end}${r}`).format.fill = i === 0 ? '#E6F3F4' : '#F5F7F9';
  });
  s.getRange(`A7:${end}${last}`).values = [headers, ...rows];
  const table = s.tables.add(`A7:${end}${last}`, true, `DropReview${wb.worksheets.items.length}`);
  table.showFilterButton = true;
  s.getRange(`A7:${end}7`).format = {fill:'#0D6576',font:{name:'Microsoft YaHei',size:11,bold:true,color:'#FFFFFF'},rowHeight:32};
  s.freezePanes.freezeRows(7);
  return s;
}
const common = '2026-09-16 · 数据来自本轮初始化后的权威目录；同物种外观变体共享掉落。';
const overviewSheet = sheet('怪物总览', '原版怪物掉落 · 全量检查', [
  '119 种怪物  /  79 种物品  /  1,134 条实际掉落关系  /  当前启用 47 种怪物',
  '普通候选统一 25%；原表权重算法未知。每条独立抽取，可一次掉多种，也可能完全不掉。',
  '接合器碎片：仅机器爬虫、被遗忘的爬虫及变体，0～3 个等概率，期望 1.5；原表其他21条来源排除。',
  '先筛选怪物，再到「实际掉落」核对数量与概率；「原始候选」保留所有重复记录和原始权重。', common,
], ['怪物名称','物种 ID','当前刷新','原表记录','原表种类','已配种类','排除记录','检查说明'], overview,
  [210,200,95,90,90,90,90,305]);
overviewSheet.getRange('C8:C126').conditionalFormats.add('containsText', {text:'未投放',format:{fill:'#FFF1D6',font:{color:'#855C16'}}});
const detail = sheet('实际掉落', '运行配置 · 每种物品一次独立抽取', [
  '1,134 条已生效配置；「未投放」表示怪物暂无刷新地图，配置保留但普通玩家当前不能从它身上获得。',
  '最低/最高数量是触发掉落后的区间；每击杀期望 = 掉率 ×（最低 + 最高）÷ 2。',
  '普通条目25%为临时复刻数值，后续可逐项调整；不以原始权重推算原服掉率。',
  '同怪同物品的重复候选合并，数量取原记录最小值至最大值；接合器碎片按用户例外。', common,
], ['怪物名称','物种 ID','当前刷新','掉落物品','最低数量','最高数量','单项掉率','每击杀期望','规则说明','物品定义 ID'], actualRows,
  [195,190,95,220,85,85,90,110,320,250]);
detail.getRange(`G8:G${actualRows.length+7}`).setNumberFormat('0%');
detail.getRange(`H8:H${actualRows.length+7}`).formulas = actualRows.map((_,i) => [`=G${i+8}*(E${i+8}+F${i+8})/2`]);
detail.getRange(`H8:H${actualRows.length+7}`).setNumberFormat('0.00');
detail.getRange(`I8:I${actualRows.length+7}`).conditionalFormats.add('containsText',{text:'用户例外',format:{fill:'#FFF1D6',font:{color:'#855C16'}}});
const itemSheet = sheet('物品索引', '79 种掉落物 · 名称与用途', [
  '全部物品已接入掉落、地面显示、拾取与背包存储；新增65项地面/背包图像，均来自荣耀版。',
  '「当前使用情况」仅列已经接入的功能；原版描述中提到的镶嵌、机甲改造等用途不代表本次同时实现。',
  '低级类胶、生物硅、四足甲壳、能量催化剂和能量包的历史重复ID已统一，旧存档和配方兼容。',
  '来源：荣耀版 FCC 对应类及图像；右侧保留类名、定义ID和源码位置，供追溯。', common,
], ['中文名称','已投放来源数','原表名称／类名','当前使用情况','物品描述','物品定义 ID','荣耀 FCC 来源'], itemRows,
  [225,115,225,330,530,250,255]);
itemSheet.getRange(`A8:G${itemRows.length+7}`).format.rowHeight = 72;
const rawSheet = sheet('原始候选', '原始证据 · 1,291 条候选逐条保留', [
  '来源：starhome_lz_ry_full_parsed/catalogs_utf8/npc_catalog.csv / produce_obj；已与原始CSV逐行核对。',
  '保留重复条目、原始数量和 raw_weight；原始权重为0也按候选接入，不能据此断言不掉落。',
  '21条非爬虫碎片按用户要求排除；被遗忘的爬虫额外配置1条碎片规则，见「实际掉落」。',
  '本页是客户端证据，不是原服掉率；实际25%临时策略与爬虫例外见运行配置页。', common,
], ['怪物名称','物种 ID','原表物品表达式','原最小','原最大','原始权重','实际中文名称','配置结果','原表位置'], rawRows,
  [195,190,240,85,85,95,225,260,225]);
rawSheet.getRange(`H8:H${rawRows.length+7}`).conditionalFormats.add('containsText',{text:'用户例外',format:{fill:'#FFF1D6',font:{color:'#855C16'}}});
wb.recalculate();
const out = path.join(root, 'docs/audits/original_monster_drops.xlsx');
await (await SpreadsheetFile.exportXlsx(wb)).save(out);
await fs.rename(out + '.inspect.ndjson', path.join(root, '.godot/drop-workbook-export.inspect.ndjson'));
console.log(await wb.inspect({kind:'workbook,sheet,table',maxChars:2500,tableMaxRows:2,tableMaxCols:4}));
for (const s of [overviewSheet, detail, itemSheet, rawSheet]) {
  console.log(await wb.inspect({kind:'region',sheetId:s.name,range:'A7:H11',maxChars:1400,tableMaxRows:5,tableMaxCols:8}));
  const preview = await wb.render({sheetName:s.name,range:s===itemSheet?'A7:E12':s===overviewSheet?'A1:H15':s===detail?'A7:I17':'A7:H15',scale:1,format:'png'});
  await fs.writeFile(path.join(root,`.godot/drop-review-${s.name}.png`),new Uint8Array(await preview.arrayBuffer()));
}
console.log(`DROP_WORKBOOK_OK ${out}`);
