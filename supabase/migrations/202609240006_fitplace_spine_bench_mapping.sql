-- Researched spine-bench mappings.
insert into public.equipment_exercise_mapping (equipment_id, exercise_id, rationale)
values
  ('fit-place24:fp_eq_6648753b6736', 'bench_press', 'BULL公式製品情報でラック一体型のベンチプレス用設備であることを確認。フラットベンチ＋バーベルラックを内包する種目へ紐付け。'),
  ('fit-place24:fp_eq_6648753b6736', 'close_grip_bench_press', 'BULL公式製品情報でラック一体型のベンチプレス用設備であることを確認。フラットベンチ＋バーベルラックを内包する種目へ紐付け。'),
  ('fit-place24:fp_eq_6648753b6736', 'skull_crusher', 'BULL公式製品情報でラック一体型のベンチプレス用設備であることを確認。フラットベンチ＋バーベルラックを内包する種目へ紐付け。'),
  ('fit-place24:fp_eq_1a79fd7858b1', 'bench_press', '設備名と同系統スパインベンチ製品仕様から、セーフティ付きラック一体型ベンチプレス設備として紐付け。'),
  ('fit-place24:fp_eq_1a79fd7858b1', 'close_grip_bench_press', '設備名と同系統スパインベンチ製品仕様から、セーフティ付きラック一体型ベンチプレス設備として紐付け。'),
  ('fit-place24:fp_eq_1a79fd7858b1', 'skull_crusher', '設備名と同系統スパインベンチ製品仕様から、セーフティ付きラック一体型ベンチプレス設備として紐付け。')
on conflict (equipment_id, exercise_id)
do update set rationale = excluded.rationale;
