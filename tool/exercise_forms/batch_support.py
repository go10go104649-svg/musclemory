"""Noninteractive scene isolation. No Blender dependency; no review promotion."""
import json


def family(spec):
    name, equipment = spec['animationId'], spec['equipmentId']
    if equipment in ('lower_chest_fly_machine', 'incline_fly_machine'):
        return 'inclined_lever_fly'
    if name in ('hinged_press', 'pulldown', 'linear_rail_row', 'lever_row',
                'back_extension', 'chin_up', 'reverse_fly', 'rollout', 'pressdown', 'knee_machine'):
        return name
    if name in ('press', 'fly') and equipment in (
            'barbell', 'dumbbell', 'press_machine', 'fly_machine', 'shoulder_machine'):
        return 'press_fly'
    if name in ('squat', 'hinge') and spec['parameters'].get('plantedFeet', False):
        return 'lower_body'
    if name == 'curl' and equipment in ('barbell', 'dumbbell'):
        return 'curl'
    if name == 'raise' and equipment == 'dumbbell' and 'raisePlane' in spec['parameters']:
        return 'raise'
    if name == 'row' and equipment == 'cable_row':
        return 'cable_row'
    if name == 'overhead_press' and equipment in ('barbell', 'dumbbell'):
        return 'vertical_press'
    return None


def blockers(spec, unreviewed_draft=False):
    reasons = []
    if family(spec) is None:
        reasons.append('motion family not implemented')
    if not unreviewed_draft and (not spec.get('references') or not spec.get('review', {}).get('equipmentReference')):
        reasons.append('equipment reference not reviewed')
    return reasons


def run_selected(specs, author, report, unreviewed_draft=False):
    """One failure does not discard other scenes; success means export only."""
    results = []
    for spec in specs:
        row = {'exerciseId': spec['exerciseId'], 'family': family(spec),
               'equipmentReferenceReviewed': bool(spec.get('review', {}).get('equipmentReference'))}
        reasons = blockers(spec, unreviewed_draft)
        if reasons:
            row.update(result='skipped', reasons=reasons)
        else:
            try:
                author(spec)
            except Exception as error:
                row.update(result='failed', reasons=[f'{type(error).__name__}: {error}'])
            else:
                row.update(result='generated', reviewApproved=False)
        results.append(row)
        report.write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    return results
