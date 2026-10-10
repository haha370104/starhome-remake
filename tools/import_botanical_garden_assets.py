"""Rebuild garden icons from Glory raw ALE and verify their world-source duplicates."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from recovery.sprites.ale_sprite import AleFile


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "../starhome_lz_ry_full/raw"
SOURCES = {
    "young_coconut": ("coconut", "小椰子", "CHN_2005_06_28_18_08_50_508.ale"),
    "green_beans": ("bean", "生豆", "CHN_2005_06_28_18_08_04_500.ale"),
    "plant_cotton": ("cotton", "植物棉", "CHN_2005_06_28_18_08_15_502.ale"),
    "melon": ("melon", "面瓜", "CHN_2005_06_28_18_08_27_504.ale"),
    "sugar_melon": ("sugar_melon", "糖瓜", "CHN_2005_06_28_18_08_39_506.ale"),
}
WORLD_VARIANTS = {
    "cotton": ("CHN_2005_06_28_18_08_21_503.ale", "fruit_variant.png"),
    "melon": ("CHN_2005_06_28_18_08_33_505.ale", "fruit_variant.png"),
    "sugar_melon": ("CHN_2005_06_28_18_08_44_507.ale", "fruit.png"),
}


def main() -> None:
    definitions = {}
    evidence = []
    for item_id, (slug, name, filename) in SOURCES.items():
        logical_path = "pic3/stuff/" + filename
        source = RAW / logical_path
        world_logical_path = "map/mapimg/house/coffee01/" + filename
        world_source = RAW / world_logical_path
        source_sha256 = hashlib.sha256(source.read_bytes()).hexdigest()
        if hashlib.sha256(world_source.read_bytes()).hexdigest() != source_sha256:
            raise ValueError(f"garden world fruit differs from inventory fruit: {filename}")
        frame = AleFile(source).frames[0]
        bounds = frame.image.getbbox()
        if bounds is None:
            raise ValueError(f"empty source frame: {source}")
        image = frame.image.crop(bounds)
        target = ROOT / "assets/items/botanical" / slug / "icon.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
        resource = "res://" + target.relative_to(ROOT).as_posix()
        world_resource = resource
        world_size = list(image.size)
        world_origin = [frame.origin_x + bounds[0], frame.origin_y + bounds[1]]
        world_variants = {}
        variant_evidence = {}
        if slug in WORLD_VARIANTS:
            variant_filename, variant_output = WORLD_VARIANTS[slug]
            variant_logical_path = "map/mapimg/house/coffee01/" + variant_filename
            variant_source = RAW / variant_logical_path
            variant_frame = AleFile(variant_source).frames[0]
            variant_bounds = variant_frame.image.getbbox()
            if variant_bounds is None:
                raise ValueError(f"empty source frame: {variant_source}")
            variant_image = variant_frame.image.crop(variant_bounds)
            variant_target = target.with_name(variant_output)
            variant_image.save(variant_target)
            variant_resource = "res://" + variant_target.relative_to(ROOT).as_posix()
            variant_evidence = {
                "role": "default" if variant_output == "fruit.png" else "alternate",
                "source_logical_path": variant_logical_path,
                "source_sha256": hashlib.sha256(variant_source.read_bytes()).hexdigest(),
                "frame": 0,
                "alpha_bounds": list(variant_bounds),
                "output_path": variant_resource,
                "output_sha256": hashlib.sha256(variant_target.read_bytes()).hexdigest(),
            }
            if variant_output == "fruit.png":
                world_resource = variant_resource
                world_size = list(variant_image.size)
                world_origin = [variant_frame.origin_x + variant_bounds[0],
                                variant_frame.origin_y + variant_bounds[1]]
            else:
                world_variants["alternate"] = {
                    "texture": variant_resource,
                    "native_size": list(variant_image.size),
                    "origin": [variant_frame.origin_x + variant_bounds[0],
                               variant_frame.origin_y + variant_bounds[1]],
                }
        definitions[item_id] = {
            "display_name": name,
            "inventory": {"icon": resource, "native_size": list(image.size)},
            "world": {"texture": world_resource, "native_size": world_size,
                      "origin": world_origin, "variants": world_variants},
        }
        evidence.append({
            "item_definition_id": item_id,
            "source_release": "starhome_lz_ry",
            "source_logical_path": logical_path,
            "identical_world_copy_logical_path": world_logical_path,
            "source_sha256": source_sha256,
            "frame": 0,
            "alpha_bounds": list(bounds),
            "output_path": resource,
            "output_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "world_variant": variant_evidence,
        })
    presentation = ROOT / "data/presentation/botanical_garden_v1.json"
    presentation.write_text(json.dumps({"schema_version": 1, "definitions": definitions},
                                       ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    audit = ROOT / "data/source_evidence/glory/botanical_garden_assets_v1.json"
    audit.write_text(json.dumps({"schema_version": 1, "items": evidence},
                                ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BOTANICAL_GARDEN_IMPORT_OK items={len(definitions)}")


if __name__ == "__main__":
    main()
