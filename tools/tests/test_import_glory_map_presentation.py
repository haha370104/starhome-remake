import unittest

from tools.import_glory_map_presentation import (
    scene_placement_key,
    transition_placement_keys,
)


class TransitionPlacementFilterTests(unittest.TestCase):
    def test_enabled_and_disabled_transports_are_dynamic_only(self) -> None:
        transitions = {
            "enabled": [
                {
                    "icon_ale": "../../map/mapimg/house/Area/as2.ale",
                    "icon_anchor": [1368, 948],
                },
                {
                    "icon_ale": "../../map/mapimg/house/Area/as2.ale",
                    "icon_anchor": [1368, 948],
                },
            ],
            "disabled_legacy": [
                {
                    "icon_ale": "../../map/mapimg/house/Area/as4.ale",
                    "icon_anchor": [624, 2232],
                }
            ],
        }
        keys = transition_placement_keys(transitions)
        self.assertEqual(len(keys), 2)
        self.assertIn(("map/mapimg/house/area/as2", 1368, 948), keys)
        self.assertIn(("map/mapimg/house/area/as4", 624, 2232), keys)

    def test_scene_key_requires_exact_asset_and_anchor(self) -> None:
        placement = {
            "source_ale": "../../map/mapimg/house/Area/as2.ale",
            "anchor": [1368, 948],
        }
        self.assertEqual(
            scene_placement_key(placement),
            ("map/mapimg/house/area/as2", 1368, 948),
        )
        self.assertIsNone(scene_placement_key({"source_ale": "missing.ale"}))


if __name__ == "__main__":
    unittest.main()
