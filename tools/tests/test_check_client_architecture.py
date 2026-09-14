"""Exercise architectural failures rather than mirroring the current directory tree."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_client_architecture import inspect_source


class ClientArchitectureTests(unittest.TestCase):
    def test_entry_rejects_gameplay_and_growth(self):
        self.assertTrue(inspect_source("scripts/main_hall.gd", "func _handle_hit():\n\tpass"))
        self.assertTrue(inspect_source("scripts/main_hall.gd", "\n" * 301))

    def test_reusable_component_cannot_reach_session_or_window(self):
        path = "scripts/client/ui/components/example.gd"
        self.assertTrue(inspect_source(path, "var player: CurrentPlayer"))
        self.assertTrue(inspect_source(path, 'const P = preload("res://scripts/client/ui/windows/inventory/inventory_panel.gd")'))

    def test_client_and_shared_dependencies_point_inward(self):
        forbidden = 'const Server = preload("res://scripts/server/authoritative_server.gd")'
        self.assertTrue(inspect_source("scripts/client/state/example.gd", forbidden))
        self.assertTrue(inspect_source("scripts/shared/example.gd", forbidden))
        self.assertFalse(inspect_source("scripts/client/state/example.gd", 'const P = preload("res://scripts/shared/player_panel_projector.gd")'))

    def test_hud_internals_and_service_locator_fail(self):
        path = "scripts/client/gameplay/map_travel_controller.gd"
        self.assertTrue(inspect_source(path, 'hud.hint_label.text = "status"'))
        self.assertTrue(inspect_source(path, "get_parent().session.start()"))
        self.assertFalse(inspect_source(path, '# hud.hint_label is private\nhud.show_status("status")'))


if __name__ == "__main__":
    unittest.main()
