"""Protect source identity and full-frame comparison used by the cross-release audit."""
import unittest
from PIL import Image
from tools.audit_cross_release_assets import normalize, candidates, signature


class CrossReleaseAuditTests(unittest.TestCase):
    def test_paths_preserve_world_branch_and_normalize_source_separators(self):
        self.assertEqual(normalize('../../map/media//house/tree.ale'),'map/media/house/tree.ale')
        self.assertEqual(normalize('NFT_BT/map/yzzl/yzzl.fcc.cab'),'nft_bt/map/yzzl/yzzl.fcc.cab')
        self.assertNotEqual(normalize('NFT_BT/map/a.fcc'),normalize('NFT_SK/map/a.fcc'))

    def test_candidate_keeps_equipment_role_over_unrelated_same_name_effect(self):
        key='pic2/equip/armor/frontarmor8.ale'
        names={'frontarmor8.ale':['pic3/effect/frontarmor8.ale','pic3/equip/armor/frontarmor8.ale','pic3/equip/body/frontarmor8.ale']}
        found,match=candidates(key,{},names)
        self.assertEqual(found,['pic3/equip/armor/frontarmor8.ale'])
        self.assertEqual(match,'version_prefix_candidate')
        self.assertEqual(candidates(key,{key:True},names),([key],'exact'))

    def test_comparison_detects_later_frames_pivots_and_dimensions(self):
        a=Image.new('RGBA',(2,2),(10,20,30,255))
        b=Image.new('RGBA',(2,2),(11,20,30,255))
        original=[(a,(0,0)),(a,(0,0))]
        for changed in [[(a,(0,0)),(b,(0,0))],[(a,(0,0)),(a,(1,0))],[(a,(0,0)),(a.resize((1,4)),(0,0))]]:
            self.assertNotEqual(signature(original),signature(changed))
        self.assertEqual(signature(original),signature([(a.copy(),(0,0)),(a.copy(),(0,0))]))


if __name__=='__main__':unittest.main()
