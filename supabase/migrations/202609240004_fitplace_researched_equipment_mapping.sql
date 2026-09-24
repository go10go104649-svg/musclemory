-- Additional researched FIT PLACE24 equipment -> exercise mappings.
with reviewed_mapping(equipment_id, exercise_id, rationale) as (
  values
    ('fit-place24:fp_eq_995bf2a31e42', 'plate_loaded_seated_row', 'メーカー製品情報とFIT PLACE掲載名を照合し、プレートロード式のロー動作として既存種目へ紐付け。'),
    ('fit-place24:fp_eq_f8d1b24f62dd', 'plate_loaded_seated_row', 'メーカー製品情報とFIT PLACE掲載名を照合し、プレートロード式のロー動作として既存種目へ紐付け。'),
    ('fit-place24:fp_eq_8cbf5d2d7ec7', 'plate_loaded_incline_chest_press', 'FIT PLACE系の同名設備とメーカー製品情報を照合し、プレートロード式インクラインチェストプレスとして紐付け。'),
    ('fit-place24:fp_eq_560e50e62b3c', 'plate_loaded_chest_press', '製品仕様でフラットからデクラインのプレス動作を行うプレートロード式コンボ機であることを確認し、両対応種目へ紐付け。'),
    ('fit-place24:fp_eq_560e50e62b3c', 'decline_press_machine', '製品仕様でフラットからデクラインのプレス動作を行うプレートロード式コンボ機であることを確認し、両対応種目へ紐付け。'),
    ('fit-place24:fp_eq_1405e4e81b19', 'plate_loaded_seated_row', 'メーカー製品情報でプレートロード式ロー動作を確認し、既存のプレートロードシーテッドロー種目へ紐付け。'),
    ('fit-place24:fp_eq_eba9225f81e6', 'plate_loaded_lat_pulldown', 'メーカー製品情報でプレートロード式ワイドプルダウンを確認し、既存のプレートロードラットプルダウン種目へ紐付け。')
)
insert into public.equipment_exercise_mapping (equipment_id, exercise_id, rationale)
select m.equipment_id, m.exercise_id, m.rationale
from reviewed_mapping m
join public.equipment e on e.id = m.equipment_id
on conflict (equipment_id, exercise_id)
do update set rationale = excluded.rationale;
