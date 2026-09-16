"""Compile user-approved per-kill expectations into the existing domain DropTable format."""
import math


def apply_policy(grouped, ids, policy):
    """Tune one species, independently ranking each biological material family present."""
    biology = policy['biological_materials']
    for family in biology['families']:
        present = [(rank, ids[grade + family]) for rank, grade in enumerate(biology['grades'])
                   if ids[grade + family] in grouped]
        if not present:
            continue
        highest = max(rank for rank, _ in present)
        for rank, item_id in present:
            distance = highest - rank
            distribution = biology['distributions_by_grade_distance'][distance]
            expected = biology['highest_expected_quantity'] * biology['lower_grade_multiplier'] ** distance
            assert math.isclose(distribution['chance'] * (distribution['minimum_quantity'] + distribution['maximum_quantity']) / 2, expected)
            grouped[item_id].update(distribution)
    seen = set()
    for rule in policy['fixed_expectations']:
        for source_class in rule['source_classes']:
            assert source_class not in seen, source_class
            seen.add(source_class)
            item_id = ids[source_class]
            if item_id in grouped:
                # One item per successful roll makes the configured probability equal to E.
                grouped[item_id].update(minimum_quantity=1, maximum_quantity=1, chance=rule['expected_quantity'])
