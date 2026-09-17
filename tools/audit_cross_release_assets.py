"""Audit recorded missing assets against both local release archives; never install candidates."""
from __future__ import annotations
import hashlib
import html
import json
from collections import Counter, defaultdict
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = ROOT.parent
DEST = OUTPUTS / 'cross_release_asset_review'
RELEASES = {'free': 'starhome_lz_fr', 'jz': 'starhome_jznp'}


def read(path):
    """Read an existing UTF-8 artifact."""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def normalize(value):
    """Normalize a source reference without inventing alternative filenames."""
    value = str(value).replace('\\', '/').strip().lower()
    while value.startswith('../') or value.startswith('./'):
        value = value.split('/', 1)[1]
    value = value.lstrip('/')
    while '//' in value:
        value = value.replace('//', '/')
    if value.startswith('mapimg/'):
        value = 'map/' + value
    return value


def gather():
    """Union current and historical missing records, retaining every use and source report."""
    rows = {}
    def add(ref, category, label, origin):
        key = normalize(ref)
        if not key or key.endswith('/'):
            return
        if '.' not in Path(key).name:
            key += '.ale'
        row = rows.setdefault(key, {'reference': key, 'source_reference': str(ref), 'uses': []})
        use = {'category': category, 'label': label, 'record': str(origin)}
        if use not in row['uses']:
            row['uses'].append(use)
    items = ROOT / 'data/gameplay/glory/glory_items_v1.json'
    for item in read(items)['definitions']:
        for mode, presentation in item.get('presentation', {}).items():
            if isinstance(presentation, dict) and 'missing' in presentation.get('asset_status', ''):
                add(presentation['ale_reference'], 'item', item['display_name'] + ' / ' + mode, items)
    weapons = ROOT / 'data/presentation/weapon_visual_bindings_v1.json'
    for row in read(weapons)['unavailable_source_assets']:
        add(row['source_reference'], 'projectile', row['definition_id'], weapons)
    for item_id, row in read(weapons)['weapons'].items():
        if row['projectile'].get('source_release', 'starhome_lz_ry') != 'starhome_lz_ry':
            add(row['projectile']['ale_reference'], 'projectile', item_id, weapons)
    for relative, category in [('starhome_lz_ry_maps_parsed/maps_missing_addimg.json', 'historical_map'), ('starhome_lz_ry_maps_missing_review/missing_scene_review.json', 'map')]:
        source = OUTPUTS / relative
        for scene in read(source)['maps']:
            for row in scene['missing_resources']:
                add(row['source_ale'], category, scene['map_name'] + ' / ' + scene['map_code'], source)
    recovery = OUTPUTS / 'starhome_lz_ry_full_parsed/official_lazy_cache/official_recovery_manifest.json'
    for row in read(recovery)['assets'].values():
        if row['status'] != 'recovered':
            add(row['logical_path'], 'official_recovery_failure', row['status'], recovery)
    maps = ROOT / 'data/content/known_maps_v1.json'
    for row in read(maps)['definitions']:
        if row.get('availability', {}).get('runtime') == 'unimplemented':
            for ref in row['source_scripts']:
                add(ref, 'map_package', row['display_name'], maps)
    # Hand-authored manifests may record extra missing dependencies outside the generated catalogs.
    for source in (ROOT / 'assets').rglob('*manifest.json'):
        data = read(source)
        def walk(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    if key in ('missing_dependencies', 'missing_assets', 'unavailable') and isinstance(child, list):
                        for item in child:
                            if isinstance(item, dict):
                                ref = item.get('source_ale', item.get('source_resource', item.get('source_path', '')))
                                if ref and ('.ale' in ref.lower() or '.png' in ref.lower()):
                                    add(ref, 'runtime_manifest', source.parent.name, source)
                    walk(child)
            elif isinstance(value, list):
                for child in value:
                    walk(child)
        walk(data)
    return rows


def raw_index(root):
    """Index physical source archives case-insensitively, preserving actual casing."""
    exact = {p.relative_to(root).as_posix().lower(): p for p in root.rglob('*') if p.is_file()}
    names = defaultdict(list)
    for key in exact:
        names[Path(key).name].append(key)
    return exact, names


def candidates(key, exact, names):
    """Prefer exact paths; label same-filename/role matches as unconfirmed candidates."""
    if key in exact:
        return [key], 'exact'
    possible = names.get(Path(key).name, [])
    # Preserve the role/subdirectory when only the release's pic-prefix moved.
    suffix = key.split('/', 1)[1] if key.startswith(('pic/', 'pic2/', 'pic3/')) else ''
    equivalents = [p for p in possible if suffix and p.split('/', 1)[-1] == suffix]
    if equivalents:
        return sorted(equivalents), 'version_prefix_candidate'
    role = next((part for part in ['bag', 'dlg', 'body'] if '/' + part + '/' in key), '')
    if role:
        possible = [p for p in possible if '/' + role + '/' in p]
    return sorted(possible), 'same_name_candidate' if possible else 'missing'


def frames_for(release, key):
    """Load source-decoded RGBA frames plus pivots for a content comparison."""
    folder = OUTPUTS / (release + '_full_parsed/ale_sprites') / key.removesuffix('.ale')
    if not (folder / 'frames.json').is_file():
        name = next(k for k, v in RELEASES.items() if v == release)
        folder = DEST / 'remote_cache' / name / 'ale_sprites' / key.removesuffix('.ale')
    metadata = read(folder / 'frames.json')
    pages = [Image.open(folder / p).convert('RGBA') for p in metadata['pages']]
    result = []
    for f in metadata['frames']:
        x, y, w, h = f['x'], f['y'], f['width'], f['height']
        result.append((pages[f['page']].crop((x, y, x+w, y+h)), (f['origin_x'], f['origin_y'])))
    return result


def signature(frames):
    """Hash every frame, its dimensions and pivot, not just a representative image."""
    digest = hashlib.sha256()
    for image, pivot in frames:
        digest.update(json.dumps([image.size, pivot]).encode())
        digest.update(image.tobytes())
    return digest.hexdigest()


def main():
    """Generate a machine audit and a review gallery without touching runtime assets."""
    DEST.mkdir(exist_ok=True)
    (DEST / 'previews').mkdir(exist_ok=True)
    indexes = {}
    for name, release in RELEASES.items():
        exact, names = raw_index(OUTPUTS / (release + '_full/raw'))
        remote, _ = raw_index(DEST / 'remote_cache' / name / 'raw')
        for key, path in remote.items():
            if key not in exact:
                exact[key] = path
                names[Path(key).name].append(key)
        indexes[name] = (exact, names)
    glory, _ = raw_index(OUTPUTS / 'starhome_lz_ry_full/raw')
    cache, _ = raw_index(OUTPUTS / 'starhome_lz_ry_full_parsed/official_lazy_cache/raw')
    records = gather()
    summaries = Counter()
    cards = []
    recoveries = {row['logical_id']+'.ale':row for row in read(ROOT/'data/content/recovered_sprite_runtime_index_v1.json')['sprites']}
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
    for number, (key, row) in enumerate(sorted(records.items()), 1):
        row['id'] = f'A{number:03d}'
        row['glory_now_available'] = key in glory or key in cache
        row['runtime_recovery'] = recoveries.get(key)
        row['releases'] = {}
        for name, (exact, names) in indexes.items():
            found, match = candidates(key, exact, names)
            row['releases'][name] = {'match': match, 'candidates': found}
        a, b = row['releases']['free']['candidates'], row['releases']['jz']['candidates']
        row['comparison'] = 'neither_found' if not a and not b else ('free_only' if not b else 'jz_only' if not a else 'multiple_candidates')
        images = {}
        if len(a) == len(b) == 1:
            pa, pb = indexes['free'][0][a[0]], indexes['jz'][0][b[0]]
            hashes = [hashlib.sha256(p.read_bytes()).hexdigest() for p in [pa, pb]]
            row['raw_sha256'] = hashes
            if hashes[0] == hashes[1]:
                row['comparison'] = 'identical_bytes'
            elif key.endswith('.ale'):
                try:
                    images = {name: frames_for(RELEASES[name], row['releases'][name]['candidates'][0]) for name in RELEASES}
                    row['decoded_sha256'] = [signature(images[name]) for name in RELEASES]
                    row['frame_counts'] = [len(images[name]) for name in RELEASES]
                    row['comparison'] = 'identical_frames' if len(set(row['decoded_sha256'])) == 1 else 'different_frames'
                except (FileNotFoundError, KeyError, ValueError) as error:
                    row['comparison'] = 'decode_unavailable'
                    row['error'] = str(error)
            else:
                row['comparison'] = 'different_binary'
        summaries[row['comparison']] += 1
        if row['comparison'] == 'different_frames' and not row['glory_now_available']:
            # Show first and the first differing frame, with both sides at the same scale.
            left, right = images['free'], images['jz']
            differing = next((i for i in range(min(len(left),len(right))) if left[i][1] != right[i][1] or left[i][0].size != right[i][0].size or left[i][0].tobytes() != right[i][0].tobytes()), 0)
            row['first_different_frame'] = differing
            canvas = Image.new('RGB', (960, 430), '#162735'); draw = ImageDraw.Draw(canvas)
            draw.text((20,10), row['id'] + ' / ' + Path(key).name, font=font, fill='white')
            for side, frames in enumerate([left, right]):
                draw.text((side*480+20,45), ('免费版' if side==0 else '新激战版') + f' · {len(frames)}帧', font=font, fill='#bfe3ff')
                for sample, index in enumerate([0, differing]):
                    image, pivot = frames[index]
                    pair = [left[index][0], right[index][0]]
                    scale = min(3.0, 440/max(im.width for im in pair), 145/max(im.height for im in pair))
                    resized = image.resize((max(1,round(image.width*scale)), max(1,round(image.height*scale))), Image.Resampling.NEAREST)
                    canvas.paste(resized,(side*480+240-resized.width//2,80+sample*170+(140-resized.height)//2),resized)
                    draw.text((side*480+15,222+sample*170),f'帧{index} / {image.width}×{image.height} / 原点{pivot}',font=font,fill='#b6c4d0')
            relative = 'previews/' + row['id'] + '.png'; canvas.save(DEST / relative); row['preview'] = relative
            cards.append(f'<article><h2>{row["id"]} · {html.escape(key)}</h2><p>{html.escape("；".join(u["label"] for u in row["uses"][:6]))}</p><img src="{relative}"><p>免费：{html.escape(a[0])}<br>激战：{html.escape(b[0])}</p></article>')
    report = {'date':'2026-09-17','scope':'All explicit missing references in item/projectile catalogs, historical/current scene audits, failed exact-path recovery records and known missing map packages. Not-declared references are not invented.', 'comparison':'All RGBA frames, dimensions, frame order and origins. Filename matches without exact paths remain unconfirmed candidates.', 'summary':dict(summaries),'total':len(records),'glory_already_available':sum(r['glory_now_available'] for r in records.values()),'records':list(records.values())}
    (DEST/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    page='<!doctype html><meta charset="utf-8"><title>缺失素材版本对照</title><style>body{background:#0e1b27;color:#e9f1f8;font:16px "Microsoft YaHei",sans-serif;max-width:1080px;margin:32px auto}article{padding:18px;background:#172c3d;margin:22px 0;border-radius:12px}img{width:100%;max-width:960px}h2{font-size:20px;overflow-wrap:anywhere}</style><h1>免费版 / 新激战版 差异对照</h1><p>全部帧及原点参与比较。下图保留历史差异，纳米护甲、帝王炮及帝王战车已按用户选择使用免费版。接入状态见下表。</p>'+''.join(cards)
    statuses = {'free_only':'仅免费版有候选','jz_only':'仅激战版有候选','identical_bytes':'两版逐字节相同','identical_frames':'两版全部帧相同','different_frames':'两版图像不同','neither_found':'两版未找到','multiple_candidates':'多重同名候选','decode_unavailable':'解码未完成','different_binary':'二进制不同'}
    current = sorted((r for r in records.values() if not r['glory_now_available']),key=lambda r:r['id'])
    restored = sum(bool(r['runtime_recovery']) for r in current)
    table = f'<h1>全部历史缺失引用的检索结果</h1><p>已接入 {restored} 项；未恢复 {len(current)-restored} 项。明确映射来源，不使用同名自动回退。</p><input id="search" placeholder="按名称、路径或结果筛选" style="width:90%;padding:12px"><table><tr><th>编号/名称</th><th>原引用</th><th>免费版</th><th>激战版</th><th>结果</th></tr>'
    for row in current:
        names = '；'.join(dict.fromkeys(u['label'] for u in row['uses']))
        values = [row['id']+' / '+names, row['reference']]
        for release in RELEASES:
            match = row['releases'][release]
            values.append(match['match']+' / '+'; '.join(match['candidates']))
        values.append(statuses[row['comparison']]+('；已接入 '+row['runtime_recovery']['source_release'] if row['runtime_recovery'] else '；未接入'))
        table += '<tr class="result">'+''.join('<td>'+html.escape(v)+'</td>' for v in values)+'</tr>'
    table += '</table><script>document.querySelector("#search").oninput=e=>document.querySelectorAll(".result").forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(e.target.value.toLowerCase()))</script>'
    page += '<style>td,th{padding:9px;border:1px solid #395368;vertical-align:top;overflow-wrap:anywhere}table{border-collapse:collapse;table-layout:fixed;width:100%;font-size:13px}th{background:#264256}</style>'+table
    (DEST/'index.html').write_text(page,encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='records'},ensure_ascii=False,indent=2))
    print('difference_previews',len(cards))


if __name__ == '__main__':
    main()
