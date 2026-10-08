"""Mutation tests for the roster guard; no assets, Godot or player saves needed."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from check_combat_roster import ROOT, check


class RosterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for path in ("data/enemies", "data/re_reference"):
            shutil.copytree(ROOT / path, self.root / path)
        for name in ("combat_roster", "enemy_attacks", "enemies", "boss_arenas"):
            shutil.copy(ROOT / f"data/{name}.json", self.root / f"data/{name}.json")

    def edit(self, name, mutate):
        path = self.root / f"data/{name}.json"
        data = json.loads(path.read_text())
        mutate(data)
        path.write_text(json.dumps(data))

    def rejects(self, text):
        errors, _ = check(self.root)
        self.assertTrue(any(text in e for e in errors), errors)

    def test_current_snapshot_reports_known_orphan(self):
        errors, warnings = check(self.root)
        self.assertEqual(errors, [])
        self.assertTrue(any("chaos_mobius_paru" in w for w in warnings))

    def test_new_resource_needs_coverage(self):
        path = self.root / "data/enemies/helion.tres"
        (path.parent / "new_enemy.tres").write_text(path.read_text().replace('id = "helion"', 'id = "new_enemy"'))
        self.rejects("uncovered resource: new_enemy")

    def test_new_attack_orphan_fails(self):
        self.edit("enemy_attacks", lambda d: d["enemies"].update(new_enemy={}))
        self.rejects("unexplained attack orphan: new_enemy")

    def test_removed_attack_fails(self):
        self.edit("enemy_attacks", lambda d: d["enemies"].pop("helion"))
        self.rejects("missing attack: helion")

    def test_changed_rig_fails(self):
        path = self.root / "data/enemies/helion.tres"
        path.write_text(path.read_text().replace('model_id = "lion"', 'model_id = "tank"'))
        self.rejects("resource drift: helion.model_id")

    def test_duplicate_crosswalk_fails(self):
        self.edit("combat_roster", lambda d: d["enemies"].append(d["enemies"][0]))
        self.rejects("duplicate crosswalk")

    def test_missing_ticket_fails(self):
        self.edit("combat_roster", lambda d: d["enemies"][0].pop("issue"))
        self.rejects("invalid family issue")

    def test_stale_orphan_exception_fails(self):
        self.edit("enemy_attacks", lambda d: d["enemies"].pop("chaos_mobius_paru"))
        self.rejects("stale attack exception")

    def test_new_source_model_fails(self):
        self.edit("re_reference/enemy_ids", lambda d: d["ids"].update({"69": "unknown_model"}))
        self.rejects("uncovered source slot: 69")

    def test_encounter_rig_drift_fails(self):
        self.edit("boss_arenas", lambda d: d["bosses"]["sinow_beat"].update(model_id="sinow_beat"))
        self.rejects("encounter drift: sinow_beat.model_id")

    def test_new_encounter_fails(self):
        self.edit("boss_arenas", lambda d: d["bosses"].update(new_boss={}))
        self.rejects("uncovered encounter: new_boss")

    def test_metadata_drift_fails(self):
        self.edit("enemies", lambda d: d[0].update(model_id="wrong"))
        self.rejects("unexplained metadata drift")

    def test_stale_metadata_exception_fails(self):
        self.edit("enemies", lambda d: next(x for x in d if x["id"] == "sinow_beat").update(model_id="sinow_beat"))
        self.rejects("stale metadata exception")


if __name__ == "__main__":
    unittest.main()
