-- KANEKIN FITNESS GYM official-page snapshot.
-- The gym has warned that this page may be stale, so unknown quantities and
-- confirmation dates stay null. Each manufacturer/model is a separate stable
-- row, allowing later additions/removals to change only the store relation.
begin;

insert into public.gym_chains (id, name, search_aliases)
values (
  'kanekin-fitness-gym',
  'KANEKIN FITNESS GYM',
  array['カネキン', 'カネキンジム', 'カネキンフィットネスジム']
)
on conflict (id) do update set
  name = excluded.name,
  search_aliases = excluded.search_aliases,
  updated_at = now();

insert into public.gym_stores (
  id, chain_id, source_id, name, prefecture, city, address, station,
  official_url, equipment_status, active, checked_at, source
) values (
  'kanekin-fitness-gym:matsudo',
  'kanekin-fitness-gym',
  'matsudo',
  '松戸店',
  '千葉県',
  '松戸市',
  '千葉県松戸市西馬橋幸町3-1',
  '馬橋駅',
  'https://www.kanekinfitnessgym.com/',
  'published',
  true,
  null,
  jsonb_build_object(
    'source_url', 'https://www.kanekinfitnessgym.com/',
    'equipment_source_url', 'https://www.kanekinfitnessgym.com/services-3-1',
    'captured_on', '2026-09-24',
    'equipment_freshness', 'legacy_page_unverified',
    'note', '公式掲載一覧を初期スナップショットとして採用。現地の追加・撤去は今後個別に反映する。'
  )
)
on conflict (id) do update set
  chain_id = excluded.chain_id,
  source_id = excluded.source_id,
  name = excluded.name,
  prefecture = excluded.prefecture,
  city = excluded.city,
  address = excluded.address,
  station = excluded.station,
  official_url = excluded.official_url,
  equipment_status = excluded.equipment_status,
  active = excluded.active,
  checked_at = excluded.checked_at,
  source = excluded.source,
  updated_at = now();

with listed_equipment(slug, name, category, load_type, manufacturer, model) as (
  values
    ('delta-incline-pec-fly', 'インクラインペックフライ', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Incline Pec Fly'),
    ('delta-dual-axis-incline-bench', 'デュアルアクシスインクラインベンチ', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Dual Axis Incline Bench'),
    ('delta-dual-axis-decline-bench', 'デュアルアクシスデクラインベンチ', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Dual Axis Decline Bench'),
    ('delta-low-row', 'ローロー', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Low-Row'),
    ('delta-shoulder-press', 'ショルダープレス', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Shoulder Press'),
    ('delta-reverse-front-lat-pulldown', 'リバースフロントラットプルダウン', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Reverse Front-Lat Pull Down'),
    ('delta-standing-lateral-raise', 'スタンディングラテラルレイズ', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Standing Lateral Raise'),
    ('delta-bicep-curl', 'バイセップカール', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Bicep Curl'),
    ('delta-vertical-chest-press', 'バーティカルチェストプレス', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Vertical Chest Press'),
    ('delta-hack-squat', 'ハックスクワット', '筋トレ', 'not_specified', 'DELTA FITNESS', 'Hack Squat'),
    ('delta-functional-training-tower', 'ファンクショナルトレーニングタワー', '筋トレ', 'cable_named', 'DELTA FITNESS', 'Functional Training Tower'),
    ('delta-belt-squat', 'ベルトスクワット', 'フリーウェイト', 'not_specified', 'DELTA FITNESS', 'Belt Squat'),
    ('delta-utility-bench', 'ユーティリティーベンチ', 'フリーウェイト', 'not_specified', 'DELTA FITNESS', 'Utility Bench'),
    ('dumbbells-1-60kg', 'ダンベル（1〜60kg）', 'フリーウェイト', 'not_specified', null, 'Dumbells 1kg-60kg'),
    ('bull-bench-press-rack', 'ベンチプレスラック', 'フリーウェイト', 'not_specified', 'BULL', 'Bench Press Rack'),
    ('bull-power-rack', 'パワーラック', 'フリーウェイト', 'not_specified', 'BULL', 'Power Rack'),
    ('bull-smith-machine', 'スミスマシン', 'フリーウェイト', 'not_specified', 'BULL', 'Smith Machine'),
    ('bull-cable-machine', 'ケーブルマシン', '筋トレ', 'cable_named', 'BULL', 'Cable Machine'),
    ('bull-front-lat-pulldown', 'フロントラットプルダウン', '筋トレ', 'cable_named', 'BULL', 'Front-Lat Pulldown'),
    ('bull-adjustable-bench', 'アジャスタブルベンチ', 'フリーウェイト', 'not_specified', 'BULL', 'Adjustable Bench'),
    ('bull-flat-bench', 'フラットベンチ', 'フリーウェイト', 'not_specified', 'BULL', 'Flat Bench'),
    ('matrix-treadmill', 'トレッドミル', '有酸素', 'not_specified', 'MATRIX', 'Treadmill'),
    ('matrix-8-way-cable-station', 'ケーブルステーション', '筋トレ', 'cable_named', 'MATRIX', '8-Way Cable Station'),
    ('matrix-fitness-bike', 'フィットネスバイク', '有酸素', 'not_specified', 'MATRIX', 'Fitness Bike'),
    ('rogue-power-rack', 'パワーラック', 'フリーウェイト', 'not_specified', 'ROGUE', 'Power Rack'),
    ('rogue-adjustable-bench', 'アジャスタブルベンチ', 'フリーウェイト', 'not_specified', 'ROGUE', 'Adjustable Bench'),
    ('rogue-flat-bench', 'フラットベンチ', 'フリーウェイト', 'not_specified', 'ROGUE', 'Flat Bench'),
    ('hammer-strength-leg-extension', 'レッグエクステンション', '筋トレ', 'not_specified', 'HAMMER STRENGTH', 'Leg Extension'),
    ('hammer-strength-leg-press', 'レッグプレス', '筋トレ', 'not_specified', 'HAMMER STRENGTH', 'Leg Press'),
    ('hammer-strength-leg-curl', 'レッグカール', '筋トレ', 'not_specified', 'HAMMER STRENGTH', 'Leg Curl'),
    ('cybex-cross-trainer', 'クロストレーナー', '有酸素', 'not_specified', 'CYBEX', 'Cross Trainer'),
    ('cybex-calf-raise', 'カーフレイズ', '筋トレ', 'not_specified', 'CYBEX', 'Calf Raise'),
    ('precor-chest-press', 'チェストプレス', '筋トレ', 'not_specified', 'PRECOR', 'Chest Press'),
    ('precor-shoulder-press', 'ショルダープレス', '筋トレ', 'not_specified', 'PRECOR', 'Shoulder Press'),
    ('precor-seated-row', 'シーテッドロー', '筋トレ', 'not_specified', 'PRECOR', 'Seated Row'),
    ('precor-t-bar-row', 'Tバーロー', '筋トレ', 'not_specified', 'PRECOR', 'T-Bar Row'),
    ('precor-inner-outer-thigh', 'インナー／アウターサイ', '筋トレ', 'not_specified', 'PRECOR', 'Inner/Outer Thigh')
)
insert into public.equipment (
  id, name, normalized_name, category, load_type, manufacturer, model,
  display_name, aliases, needs_review, source
)
select
  'kanekin:' || slug,
  name,
  public.gym_search_text(name),
  category,
  load_type,
  manufacturer,
  model,
  concat_ws(' ', manufacturer, name),
  array_remove(array[model], null),
  false,
  jsonb_build_object(
    'source_equipment_id', slug,
    'snapshot_id', 'official-page-2026-09-24',
    'source_url', 'https://www.kanekinfitnessgym.com/services-3-1',
    'captured_on', '2026-09-24',
    'equipment_freshness', 'legacy_page_unverified',
    'listed_name', concat_ws(' ', manufacturer, model, name)
  )
from listed_equipment
on conflict (id) do update set
  name = excluded.name,
  normalized_name = excluded.normalized_name,
  category = excluded.category,
  load_type = excluded.load_type,
  manufacturer = excluded.manufacturer,
  model = excluded.model,
  display_name = excluded.display_name,
  aliases = excluded.aliases,
  needs_review = excluded.needs_review,
  source = excluded.source,
  updated_at = now();

insert into public.gym_store_equipment (
  store_id, equipment_id, quantity, available, unavailable_quantity,
  raw_name, source_url, checked_at, source_kind, source
)
select
  'kanekin-fitness-gym:matsudo',
  e.id,
  null,
  true,
  null,
  e.source->>'listed_name',
  'https://www.kanekinfitnessgym.com/services-3-1',
  null,
  'official',
  jsonb_build_object(
    'snapshot_id', 'official-page-2026-09-24',
    'captured_on', '2026-09-24',
    'equipment_freshness', 'legacy_page_unverified'
  )
from public.equipment e
where e.source->>'snapshot_id' = 'official-page-2026-09-24'
on conflict (store_id, equipment_id) do update set
  quantity = excluded.quantity,
  available = excluded.available,
  unavailable_quantity = excluded.unavailable_quantity,
  raw_name = excluded.raw_name,
  source_url = excluded.source_url,
  checked_at = excluded.checked_at,
  source_kind = excluded.source_kind,
  source = excluded.source,
  updated_at = now();

-- Direct mappings only cover movements possible on the named equipment alone.
-- Bench-dependent free-weight movements are represented by rules below.
with mapping_groups(equipment_id, exercise_ids, rationale) as (
  values
    ('kanekin:delta-incline-pec-fly', array['incline_fly_machine'], '公式掲載機種名から専用インクラインフライ動作へ紐付け。'),
    ('kanekin:delta-dual-axis-incline-bench', array['incline_press_machine'], '公式掲載機種名から専用インクラインプレス動作へ紐付け。'),
    ('kanekin:delta-dual-axis-decline-bench', array['decline_press_machine'], '公式掲載機種名から専用デクラインプレス動作へ紐付け。'),
    ('kanekin:delta-low-row', array['low_row'], '公式掲載機種名からローロー動作へ紐付け。'),
    ('kanekin:delta-shoulder-press', array['shoulder_press'], '公式掲載機種名からショルダープレス動作へ紐付け。'),
    ('kanekin:delta-reverse-front-lat-pulldown', array['reverse_grip_lat_pulldown'], '公式掲載機種名からリバースグリップのラットプルダウン動作へ紐付け。'),
    ('kanekin:delta-standing-lateral-raise', array['machine_lateral_raise'], '公式掲載機種名からマシンラテラルレイズへ紐付け。'),
    ('kanekin:delta-bicep-curl', array['machine_arm_curl'], '公式掲載機種名からマシンアームカールへ紐付け。'),
    ('kanekin:delta-vertical-chest-press', array['chest_press'], '公式掲載機種名からチェストプレス動作へ紐付け。'),
    ('kanekin:delta-hack-squat', array['hack_squat'], '公式掲載機種名からハックスクワット動作へ紐付け。'),
    ('kanekin:delta-functional-training-tower', array['cable_curl','cable_fly','cable_lateral_raise','face_pull','rope_pushdown','straight_bar_pushdown'], '既存の汎用デュアルプーリーと同じ保守的なケーブル種目セット。'),
    ('kanekin:delta-belt-squat', array['belt_squat'], '公式掲載機種名からベルトスクワット動作へ紐付け。'),
    ('kanekin:dumbbells-1-60kg', array['arnold_press','concentration_curl','dumbbell_curl','dumbbell_shoulder_press','dumbbell_shrug','french_press','front_raise','goblet_squat','hammer_curl','lateral_raise','lunge','one_arm_dumbbell_row','rear_raise','reverse_lunge','russian_twist','single_leg_rdl','split_squat','triceps_kickback','walking_lunge','weighted_crunch','zottman_curl'], 'ダンベル単体で実施できる既存種目。ベンチ必須種目は組み合わせルールで判定。'),
    ('kanekin:bull-bench-press-rack', array['bench_press'], '専用ベンチプレスラックとして公式掲載。'),
    ('kanekin:bull-power-rack', array['barbell_curl','barbell_shrug','barbell_squat','bent_over_row','deadlift','front_squat','good_morning','military_press','pendlay_row','rack_pull','romanian_deadlift','sumo_deadlift','upright_row'], '既存パワーラックと同じ、ベンチを必要としないバーベル種目セット。'),
    ('kanekin:rogue-power-rack', array['barbell_curl','barbell_shrug','barbell_squat','bent_over_row','deadlift','front_squat','good_morning','military_press','pendlay_row','rack_pull','romanian_deadlift','sumo_deadlift','upright_row'], '既存パワーラックと同じ、ベンチを必要としないバーベル種目セット。'),
    ('kanekin:bull-smith-machine', array['smith_bench_press','smith_bulgarian_split_squat','smith_decline_press','smith_incline_press','smith_shoulder_press','smith_squat'], '既存スミスマシンと同じ種目セット。'),
    ('kanekin:bull-cable-machine', array['cable_curl','cable_fly','cable_lateral_raise','face_pull','rope_pushdown','straight_bar_pushdown'], '既存の汎用デュアルプーリーと同じ保守的なケーブル種目セット。'),
    ('kanekin:bull-front-lat-pulldown', array['lat_pulldown'], '公式掲載機種名からラットプルダウン動作へ紐付け。'),
    ('kanekin:matrix-treadmill', array['treadmill'], '公式掲載機種名からトレッドミル種目へ紐付け。'),
    ('kanekin:matrix-8-way-cable-station', array['cable_curl','cable_fly','cable_lateral_raise','face_pull','rope_pushdown','straight_bar_pushdown'], '既存の汎用デュアルプーリーと同じ保守的なケーブル種目セット。'),
    ('kanekin:matrix-fitness-bike', array['exercise_bike'], '公式掲載機種名からフィットネスバイク種目へ紐付け。'),
    ('kanekin:hammer-strength-leg-extension', array['leg_extension'], '公式掲載機種名からレッグエクステンション動作へ紐付け。'),
    ('kanekin:hammer-strength-leg-press', array['leg_press'], '公式掲載機種名からレッグプレス動作へ紐付け。'),
    ('kanekin:hammer-strength-leg-curl', array['leg_curl'], '掲載ページは姿勢を特定しないため、既存の汎用レッグカールへ紐付け。'),
    ('kanekin:cybex-cross-trainer', array['cross_trainer'], '公式掲載機種名からクロストレーナー種目へ紐付け。'),
    ('kanekin:cybex-calf-raise', array['calf_raise'], '掲載ページは座位・立位を特定しないため、既存の汎用カーフレイズへ紐付け。'),
    ('kanekin:precor-chest-press', array['chest_press'], '公式掲載機種名からチェストプレス動作へ紐付け。'),
    ('kanekin:precor-shoulder-press', array['shoulder_press'], '公式掲載機種名からショルダープレス動作へ紐付け。'),
    ('kanekin:precor-seated-row', array['seated_row'], '公式掲載機種名からシーテッドロー動作へ紐付け。'),
    ('kanekin:precor-t-bar-row', array['t_bar_row'], '公式掲載機種名からTバーロー動作へ紐付け。'),
    ('kanekin:precor-inner-outer-thigh', array['hip_abduction','hip_adduction'], '複合機名に明記されたアウターサイとインナーサイの両動作へ紐付け。')
)
insert into public.equipment_exercise_mapping (equipment_id, exercise_id, rationale)
select equipment_id, unnest(exercise_ids), rationale
from mapping_groups
on conflict (equipment_id, exercise_id) do update set rationale = excluded.rationale;

-- Rack + bench rules. Each physical machine keeps its own rule items so a later
-- removal immediately changes “この店舗でできる” without rewriting mappings.
with racks(slug, equipment_id) as (
  values
    ('bull-power-rack', 'kanekin:bull-power-rack'),
    ('rogue-power-rack', 'kanekin:rogue-power-rack')
), benches(slug, equipment_id, adjustable) as (
  values
    ('bull-adjustable-bench', 'kanekin:bull-adjustable-bench', true),
    ('bull-flat-bench', 'kanekin:bull-flat-bench', false),
    ('rogue-adjustable-bench', 'kanekin:rogue-adjustable-bench', true),
    ('rogue-flat-bench', 'kanekin:rogue-flat-bench', false)
), movements(exercise_id, adjustable_only) as (
  values
    ('bench_press', false),
    ('close_grip_bench_press', false),
    ('skull_crusher', false),
    ('hip_thrust', false),
    ('incline_barbell_press', true)
), rules as (
  select
    'kanekin:rack-bench:' || r.slug || ':' || b.slug || ':' || m.exercise_id as id,
    m.exercise_id,
    r.equipment_id as rack_id,
    b.equipment_id as bench_id
  from racks r cross join benches b cross join movements m
  where not m.adjustable_only or b.adjustable
)
insert into public.exercise_equipment_rules (id, exercise_id, rationale)
select id, exercise_id, 'カネキン掲載のラックと対応ベンチが両方利用可能な場合のみ判定。'
from rules
on conflict (id) do update set
  exercise_id = excluded.exercise_id,
  rationale = excluded.rationale,
  updated_at = now();

with racks(slug, equipment_id) as (
  values
    ('bull-power-rack', 'kanekin:bull-power-rack'),
    ('rogue-power-rack', 'kanekin:rogue-power-rack')
), benches(slug, equipment_id, adjustable) as (
  values
    ('bull-adjustable-bench', 'kanekin:bull-adjustable-bench', true),
    ('bull-flat-bench', 'kanekin:bull-flat-bench', false),
    ('rogue-adjustable-bench', 'kanekin:rogue-adjustable-bench', true),
    ('rogue-flat-bench', 'kanekin:rogue-flat-bench', false)
), movements(exercise_id, adjustable_only) as (
  values
    ('bench_press', false),
    ('close_grip_bench_press', false),
    ('skull_crusher', false),
    ('hip_thrust', false),
    ('incline_barbell_press', true)
), rules as (
  select
    'kanekin:rack-bench:' || r.slug || ':' || b.slug || ':' || m.exercise_id as id,
    r.equipment_id as rack_id,
    b.equipment_id as bench_id
  from racks r cross join benches b cross join movements m
  where not m.adjustable_only or b.adjustable
)
insert into public.exercise_equipment_rule_items (rule_id, equipment_id)
select id, rack_id from rules
union all
select id, bench_id from rules
on conflict (rule_id, equipment_id) do nothing;

-- Dumbbell + bench rules follow the same independent-equipment structure.
with benches(slug, equipment_id, adjustable) as (
  values
    ('bull-adjustable-bench', 'kanekin:bull-adjustable-bench', true),
    ('bull-flat-bench', 'kanekin:bull-flat-bench', false),
    ('rogue-adjustable-bench', 'kanekin:rogue-adjustable-bench', true),
    ('rogue-flat-bench', 'kanekin:rogue-flat-bench', false)
), movements(exercise_id, adjustable_only) as (
  values
    ('flat_dumbbell_press', false),
    ('dumbbell_fly', false),
    ('dumbbell_pullover', false),
    ('bulgarian_split_squat', false),
    ('incline_dumbbell_press', true),
    ('incline_dumbbell_fly', true),
    ('chest_supported_dumbbell_row', true),
    ('incline_dumbbell_curl', true),
    ('spider_curl', true)
), rules as (
  select
    'kanekin:dumbbell-bench:' || b.slug || ':' || m.exercise_id as id,
    m.exercise_id,
    b.equipment_id as bench_id
  from benches b cross join movements m
  where not m.adjustable_only or b.adjustable
)
insert into public.exercise_equipment_rules (id, exercise_id, rationale)
select id, exercise_id, 'カネキン掲載のダンベルと対応ベンチが両方利用可能な場合のみ判定。'
from rules
on conflict (id) do update set
  exercise_id = excluded.exercise_id,
  rationale = excluded.rationale,
  updated_at = now();

with benches(slug, equipment_id, adjustable) as (
  values
    ('bull-adjustable-bench', 'kanekin:bull-adjustable-bench', true),
    ('bull-flat-bench', 'kanekin:bull-flat-bench', false),
    ('rogue-adjustable-bench', 'kanekin:rogue-adjustable-bench', true),
    ('rogue-flat-bench', 'kanekin:rogue-flat-bench', false)
), movements(exercise_id, adjustable_only) as (
  values
    ('flat_dumbbell_press', false),
    ('dumbbell_fly', false),
    ('dumbbell_pullover', false),
    ('bulgarian_split_squat', false),
    ('incline_dumbbell_press', true),
    ('incline_dumbbell_fly', true),
    ('chest_supported_dumbbell_row', true),
    ('incline_dumbbell_curl', true),
    ('spider_curl', true)
), rules as (
  select
    'kanekin:dumbbell-bench:' || b.slug || ':' || m.exercise_id as id,
    b.equipment_id as bench_id
  from benches b cross join movements m
  where not m.adjustable_only or b.adjustable
)
insert into public.exercise_equipment_rule_items (rule_id, equipment_id)
select id, 'kanekin:dumbbells-1-60kg' from rules
union all
select id, bench_id from rules
on conflict (rule_id, equipment_id) do nothing;

commit;
