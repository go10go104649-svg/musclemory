-- Resolved FIT PLACE24 ambiguous equipment mappings after manual review.
insert into public.equipment_exercise_mapping (equipment_id, exercise_id, rationale)
values
  ('fit-place24:fp_eq_037d2725574b', 'linear_row', 'FIT PLACE公式でISOライナーロウ/ライナーロウ系プレートロード設備として掲載されるロー動作。設備IDは維持したまま既存 linear_row に紐付ける。'),
  ('fit-place24:fp_eq_b962f153802e', 'linear_row', 'FIT PLACE公式でISOリニアロウ（プレートロード）として掲載。表記差を設備統合せず、動作は既存 linear_row に紐付ける。'),
  ('fit-place24:fp_eq_3ffb97ab19d3', 'high_row', 'FIT PLACE公式でハイロウ（プレートロード）として多数店舗に掲載されるため、既存 high_row に紐付ける。'),
  ('fit-place24:fp_eq_e28aa6bb657a', 'back_extension', 'FIT PLACE公式で独立したバックエクステンションベンチとして多数店舗に掲載。自重と追加荷重の両方を同じベンチで実施可能として紐付ける。'),
  ('fit-place24:fp_eq_e28aa6bb657a', 'weighted_back_extension', 'FIT PLACE公式で独立したバックエクステンションベンチとして多数店舗に掲載。自重と追加荷重の両方を同じベンチで実施可能として紐付ける。'),
  ('fit-place24:fp_eq_e2f90d4521d0', 'machine_hip_thrust', 'FIT PLACEの設備一覧でフリーウェイト区分に置かれる専用ヒップスラスト設備。設備カテゴリは保持し、動作は専用機を表す machine_hip_thrust に紐付ける。'),
  ('fit-place24:fp_eq_9cbae3e29b25', 'machine_arm_curl', 'FIT PLACE公式の筋トレマシン欄にバイセプスカールとして掲載。既存のマシンアームカール種目へ紐付ける。'),
  ('fit-place24:fp_eq_6ac44b958236', 'back_extension_machine', 'FIT PLACE公式の筋トレマシン欄にバックエクステンションマシンとして掲載。専用種目 back_extension_machine に紐付ける。'),
  ('fit-place24:fp_eq_c2e8b4cbe71b', 'machine_hip_thrust', 'FIT PLACE公式の筋トレマシン欄にヒップスラストとして掲載。専用機種目 machine_hip_thrust に紐付ける。'),
  ('fit-place24:fp_eq_2069c8ac3ff1', 'lat_pulldown', 'LEXCO系フィクスドプルダウンはウェイトスタック/ワイヤー駆動で広背筋・僧帽筋を狙うプルダウン機。既存 lat_pulldown に紐付ける。'),
  ('fit-place24:fp_eq_c563b0cde41a', 'pec_fly', '2-in-1のペックフライ/リアデルト機として胸部と三角筋後部の双方に対応するため、pec_fly と rear_delt に紐付ける。'),
  ('fit-place24:fp_eq_c563b0cde41a', 'rear_delt', '2-in-1のペックフライ/リアデルト機として胸部と三角筋後部の双方に対応するため、pec_fly と rear_delt に紐付ける。'),
  ('fit-place24:fp_eq_0a13c23b47c0', 'lat_pulldown', 'FIT PLACE公式の筋トレマシン欄にラットプルダウンとして掲載されるため、既存 lat_pulldown に紐付ける。'),
  ('fit-place24:fp_eq_09d623796663', 'seated_leg_curl', 'FIT PLACE公式では同一店舗でライイング/プローンレッグカールと別に「レッグカール」を掲載する構成が多く、座位系レッグカールとして既存 seated_leg_curl に紐付ける。')
on conflict (equipment_id, exercise_id)
do update set rationale = excluded.rationale;
