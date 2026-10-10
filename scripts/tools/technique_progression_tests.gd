extends RefCounted

static func run(t: Node) -> void:
	seed(343)
	for cd in ClassRegistry.get_all_classes():
		var character := {"class_id": cd.id, "level": 100, "techniques": {"foie": 99, "rafoie": 1}}
		var cap := int(cd.technique_limits.get("foieBartaZonde", 0))
		t.assert_eq(TechniqueManager.get_technique_level(character, "foie"), cap, "%s saved level respects class cap" % cd.id)
		t.assert_eq(TechniqueManager.get_technique_level(character, "rafoie"), cap, "%s charged level follows upgraded base" % cd.id)
		t.assert_true(not TechniqueManager.class_can_learn(character, "foie", 0), "invalid disk capability rejected")
		character.techniques = {}
		t.assert_eq(TechniqueManager.can_learn(character, "foie", 1).allowed, cap > 0, "%s disk access matches class capability" % cd.id)
	var force := {"class_id": "fomar", "level": 100, "techniques": {}}
	for invalid in [-1, 0, 31]:
		t.assert_true(TechniqueManager.create_disk("foie", invalid).is_empty(), "invalid disk not minted")
		t.assert_true(not TechniqueManager.can_learn(force, "foie", invalid).allowed, "invalid level not learnable")
	for tech in ["rafoie", "gibarta", "grants", "megid", "reverser"]:
		t.assert_true(TechniqueManager.create_disk(tech, 1).is_empty(), "hidden advanced disk not minted")
		t.assert_true(not TechniqueManager.can_learn(force, tech, 1).allowed, "hidden disk not learned")
	for row in TechniqueManager.generate_shop_inventory(1):
		t.assert_true(TechniqueManager.is_disk_technique(row.technique_id), "shop only offers visible base techniques")
	for area in TechniqueManager.AREA_TECHNIQUE_POOLS:
		for draw in 10:
			var disk := TechniqueManager.generate_random_disk("normal", area, false, false)
			t.assert_true(TechniqueManager.is_disk_technique(disk.technique_id), "area drop is learnable base")
	force.techniques = {"foie": 5, "rafoie": 1, "gifoie": 2}
	t.assert_eq(TechniqueManager.get_technique_level(force, "rafoie"), 5, "old charged entry cannot shadow base upgrade")
	t.assert_eq(TechniqueManager.get_technique_level(force, "gifoie"), 2, "legacy non-charge entry preserved")
	t.assert_eq(TechniqueManager.get_technique_level({"class_id": "missing", "techniques": {"foie": 5}}, "foie"), 0, "unknown class fails closed")
