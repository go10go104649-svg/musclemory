import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from motion_checks import validate_resisted_pull


class ResistedPullTest(unittest.TestCase):
    def samples(self, offset):
        result = []
        # Full outward and return path, including the duplicate loop endpoint.
        for phase in [0, .25, .5, .75, 1, .75, .5, .25, 0]:
            angle = math.radians(10 * phase)
            z = 1.91 + offset[0] * math.sin(angle) + offset[1] * math.cos(angle)
            result.append({'pull': phase, 'workingPlateZ': [z, z]})
        return result

    def test_dy_counterarm_lifts_plates_through_full_cycle(self):
        rises = validate_resisted_pull(self.samples((.24, -.36)))
        self.assertTrue(all(.047 < rise < .048 for rise in rises))

    def test_old_downward_counterarm_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'falls'):
            validate_resisted_pull(self.samples((-.14, -.36)))

    def test_endpoint_rise_does_not_hide_intermediate_drop(self):
        samples = [{'pull': p, 'workingPlateZ': [z]} for p, z in [(0, 0), (.3, .2), (.6, .1), (1, .3)]]
        with self.assertRaisesRegex(ValueError, 'falls'):
            validate_resisted_pull(samples)

    def test_one_bad_independent_arm_is_rejected(self):
        with self.assertRaises(ValueError):
            validate_resisted_pull([{'pull': 0, 'workingPlateZ': [0, 0]}, {'pull': 1, 'workingPlateZ': [.1, -.1]}])

    def test_static_or_missing_plates_are_rejected(self):
        for values in [[], [1]]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                validate_resisted_pull([{'pull': 0, 'workingPlateZ': values}, {'pull': 1, 'workingPlateZ': values}])

    def test_nonfinite_plate_position_is_rejected(self):
        with self.assertRaises(ValueError):
            validate_resisted_pull([{'pull': 0, 'workingPlateZ': [0]}, {'pull': 1, 'workingPlateZ': [float('nan')]}])
