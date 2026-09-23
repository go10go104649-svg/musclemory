"""Mechanical sanity checks, never a substitute for visual or native QA."""
import math


def validate_resisted_pull(samples, tolerance=1e-5):
    """Each working plate must rise monotonically as concentric pull increases."""
    if len(samples) < 2:
        raise ValueError('Resisted pull needs multiple samples')
    ordered = sorted(samples, key=lambda sample: sample['pull'])
    count = len(ordered[0]['workingPlateZ'])
    if not count or ordered[-1]['pull'] - ordered[0]['pull'] <= tolerance:
        raise ValueError('Missing working plates or pull range')
    previous = None
    for sample in ordered:
        values = sample['workingPlateZ']
        if len(values) != count or not all(math.isfinite(z) for z in values):
            raise ValueError('Invalid working plate samples')
        if previous is not None and any(z < old - tolerance for z, old in zip(values, previous)):
            raise ValueError('Working plate falls during concentric pull')
        previous = values
    rises = [end - start for start, end in zip(ordered[0]['workingPlateZ'], ordered[-1]['workingPlateZ'])]
    if any(rise <= tolerance for rise in rises):
        raise ValueError('Working plate provides no gravitational resistance')
    return rises
