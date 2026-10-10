"""Verify the scoped industrial materials against their local original client definitions."""

import hashlib
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import restore_industrial_material_icons as recovery
from audit_monster_asset_sources import apply_palette, decode_index_alpha, load_decoder
from recovery.fcc_workspace import RawFccWorkspace


EXPECTED_NAMES = set("铜 硅 石墨 银 金 铬 镍 锌 镭 硫 磷 钾 钛 钪 镁 钡 铜铁合金 硅铁合金 硅铜合金 银钢合金 银铜合金 金钢合金 金铜合金 镭铬合金 镍锌合金 锌钛合金 钡镁合金 锌钡合金 钛铬合金 钪镁合金 合成线 合成绒 合成丝 合成棉 合成纤维".split())


class IndustrialMaterialIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with RawFccWorkspace() as workspace:
            cls.source = workspace.text("cltobj/stuffclt2.fcc")
            words = workspace.text("great/code_string.fcc")
        cls.strings = dict(re.findall(r'^#define\s+(\w+)\s+"((?:\\.|[^"\\])*)"', words, re.M))
        industrial = [entry for path in recovery.CATALOG_PATHS for entry in json.loads((recovery.ROOT / path).read_text())["definitions"]]
        cls.materials = [entry for entry in industrial if entry.get("source_audit", {}).get("presentation_recovery") == recovery.RECOVERY_GROUP]
        cls.originals = {entry["id"]: entry for entry in json.loads((recovery.ROOT / "data/gameplay/glory/glory_items_v1.json").read_text())["definitions"]}

    def test_exact_scope(self):
        self.assertEqual(len(self.materials), 35)
        self.assertEqual({entry["display_name"] for entry in self.materials}, EXPECTED_NAMES)
        self.assertEqual(sum("icon" in entry["presentation"] for entry in self.materials), 23)
        self.assertEqual(sum("ale_reference" in entry["presentation"] for entry in self.materials), 12)

    def test_original_descriptions_and_asset_declarations(self):
        for entry in self.materials:
            with self.subTest(material=entry["display_name"]):
                match = re.search(r'^class\s+' + re.escape(entry["source_class"]) + r'\s*:.*?(?=^class |\Z)', self.source, re.M | re.S)
                self.assertIsNotNone(match)
                body = re.sub(r'//[^\n]*|/\*.*?\*/', '', match[0], flags=re.S)
                description_string = re.search(r'm_sDesc\s*=\s*(\w+)', body)[1]
                self.assertEqual(entry["description"], self.strings[description_string])
                self.assertEqual(entry["source_audit"]["description_string"], description_string)
                self.assertEqual(entry["source_audit"]["source_line"], self.source.count("\n", 0, match.start()) + 1)
                paths = re.findall(r'\$\+"../([^"\n]+\.(?:ale|act))"', body)
                self.assertEqual([source["source_path"] for source in entry["source_audit"]["sources"]], paths)

    def test_identity_and_stack_limits(self):
        for entry in self.materials:
            with self.subTest(material=entry["display_name"]):
                self.assertEqual(entry["kind"], "material")
                self.assertEqual(entry["max_stack"], 999 if entry["display_name"] in ["钾", "钡镁合金"] else 99)
                self.assertNotIn("workshop_unit_price", entry)
                self.assertNotIn("stats", entry)
                if entry["id"] in self.originals:
                    original = self.originals[entry["id"]]
                    self.assertTrue(entry["replaces_name_only"])
                    self.assertEqual(entry["source_class"], original["display_name"])
                    self.assertEqual(entry["evidence_roles"], original["evidence_roles"])
                    self.assertEqual(original["source_audit"]["status"], "name_only")

    def test_original_pixel_and_palette_fidelity(self):
        decoder = load_decoder()
        for entry in self.materials:
            with self.subTest(material=entry["display_name"]):
                evidence = entry["source_audit"]
                sources = [recovery.ROOT / "../starhome_lz_ry_full/raw" / source["source_path"] for source in evidence["sources"]]
                for source, recorded in zip(sources, evidence["sources"]):
                    self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), recorded["sha256"])
                sprite = decoder.AleFile(sources[0])
                self.assertEqual(len(sprite.frames), 1)
                image = (apply_palette(decode_index_alpha(sprite, sprite.frames[0]), recovery.load_act_colors(sources[1]))
                         if len(sources) == 2 else sprite.frames[0].image)
                self.assertEqual(list(image.size), evidence["original_icon_size"])
                self.assertIsNotNone(image.getchannel("A").getbbox())
                if "icon" in entry["presentation"]:
                    with Image.open(recovery.ROOT / entry["presentation"]["icon"].removeprefix("res://")) as restored:
                        self.assertEqual(restored.convert("RGBA").tobytes(), image.tobytes())
                else:
                    self.assertEqual(entry["presentation"]["ale_reference"], evidence["sources"][0]["source_path"].lower().removesuffix(".ale"))

    def test_palette_trailers_are_not_extra_colors(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "palette.act"
            palette = bytes(range(256)) * 3
            for suffix in [b"", b"\r\r\n", b"\x01\x00\xff\xff"]:
                path.write_bytes(palette + suffix)
                colors = recovery.load_act_colors(path)
                self.assertEqual(len(colors), 256)
                self.assertEqual(colors[-1], (*palette[-3:], 255))
            for payload in [palette[:-1], palette + b"bad", palette + b"extra"]:
                path.write_bytes(payload)
                with self.assertRaises(ValueError):
                    recovery.load_act_colors(path)

    def test_check_mode_does_not_write(self):
        with mock.patch.object(Path, "write_bytes") as write_bytes, mock.patch.object(Path, "mkdir") as mkdir:
            recovery.restore(check=True)
            write_bytes.assert_not_called()
            mkdir.assert_not_called()


if __name__ == "__main__":
    unittest.main()
