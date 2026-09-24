-- Reviewed FIT PLACE24 T-bar equipment -> exercise mappings.
-- Equipment identity/load type remains independent from the exercise catalog's
-- equipment label. This allows both dedicated plate-loaded and other T-bar
-- implementations to resolve to the same T-bar row exercise.
with reviewed_mapping(equipment_id, exercise_id, rationale) as (
  values
    (
      'fit-place24:fp_eq_93cafce3bb2c',
      't_bar_row',
      '設備名がTバーローを明示し、既存種目 t_bar_row と同一動作。店舗設備の負荷方式と種目マスターの器具分類は分離して扱う。'
    ),
    (
      'fit-place24:fp_eq_aa7f2abd2795',
      't_bar_row',
      '設備名がTバーロー（プレートロード）を明示し、既存種目 t_bar_row と同一動作。プレートロード設備であっても種目IDは共通とし、設備分類と種目分類は分離して扱う。'
    )
)
insert into public.equipment_exercise_mapping (equipment_id, exercise_id, rationale)
select m.equipment_id, m.exercise_id, m.rationale
from reviewed_mapping m
join public.equipment e on e.id = m.equipment_id
on conflict (equipment_id, exercise_id)
do update set rationale = excluded.rationale;
