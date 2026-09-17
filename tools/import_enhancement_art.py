"""Cut generated sprite sheets into inventory-sized PNGs without repainting them."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def icon(source, cell, output):
    cropped = source.crop(cell)
    bounds = cropped.getchannel('A').point(lambda value: 255 if value >= 128 else 0).getbbox()
    if bounds is None:
        raise ValueError(f'Empty generated cell: {output}')
    cropped = cropped.crop(bounds)
    # Technical export only: preserve generated silhouette and alpha; no painted variants.
    cropped.thumbnail((34, 34), Image.Resampling.NEAREST)
    target = Image.new('RGBA', (36, 36))
    target.paste(cropped, ((36-cropped.width)//2, (36-cropped.height)//2))
    target.save(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_directory', type=Path)
    args = parser.parse_args()
    for manifest, gems in [('manifest.json', False), ('gems.json', True)]:
        for row in json.loads((args.source_directory / manifest).read_text(encoding='utf8')):
            source_path = Path(row['path'])
            source = Image.open(source_path).convert('RGBA')
            family = 'gems' if gems else ('prefix' if row['id'] in ['tiger', 'turtle', 'dragon', 'phoenix'] else 'trait')
            directory = ROOT / 'assets/items/enhancement' / family / row['id']
            directory.mkdir(parents=True, exist_ok=True)
            count = 1 if gems else 6
            exports = []
            for i in range(count):
                name = 'icon.png' if gems else f'quality_{i+1}.png'
                cell = (round(i*source.width/count), 0, round((i+1)*source.width/count), source.height)
                icon(source, cell, directory / name)
                exports.append({'file': name, 'source_cell': cell,
                                'sha256': hashlib.sha256((directory / name).read_bytes()).hexdigest()})
            provenance = {'source_release': 'remake_generated', 'generator': 'builtin_image_gen',
                          'prompt': row['prompt'], 'original_sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
                          'original_dimensions': source.size, 'native_size': [36, 36],
                          'export': 'alpha bounds crop, nearest-neighbor downscale, transparent padding',
                          'levels': '1-15 share attribute art; level is shown by the UI' if gems else 'six individually generated quality states',
                          'files': exports}
            (directory / 'manifest.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
    print('Exported 54 affix quality icons and 11 attribute gem icons')


if __name__ == '__main__':
    main()
