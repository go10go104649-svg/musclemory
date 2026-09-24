# Gym reference data import

All chains share `gym_chains`, `gym_stores`, `equipment`, `gym_store_equipment`
and the many-to-many `equipment_exercise_mapping`. A namespace plus the source's
stable ID identifies each imported row; similar names are never merged automatically.
`user_gym_stores` and `gym_equipment_reports` are private owner-only RLS tables.
Unauthenticated device registrations stay in local preferences; they are not public
profiles, are not silently transferred to a signed-in account, and are not included
in the workout backup. Workout records/drafts retain an optional `gymStoreId` in
addition to their existing `gymName`.

## Import

Apply `supabase/migrations/202609230001_gym_equipment.sql` through the project's
migration workflow. The current linked project has this migration applied and
recorded. With Python + openpyxl and an authenticated, linked Supabase CLI:

```sh
python3 tool/gym_import/import_master.py --input /path/to/master.xlsx \
  --chain-id fit-place24 --chain-name 'FIT PLACE24' \
  --mapping tool/gym_import/fitplace_mappings.json \
  --requirements tool/gym_import/fitplace_requirement_rules.json
# Review counts and validation, then use the same command with --apply.
```

The workbook is opened read-only, hashed before/after, never saved. SQL is created
in a temporary directory and removed. No key, workbook or generated payload belongs
in Git. The importer validates before executing one transaction. Repeating an
import upserts by stable keys; it does not delete missing stores, equipment or
mappings. Closures/removals must be reviewed and marked `active=false` /
`available=false` by an administrator, not inferred from an absent source row.
Importing the same source again reapplies its explicit availability information.
Manufacturer, model, station and quantity stay null when absent. Raw source
metadata, raw equipment names, source URLs, dates and review notes are retained.
NFKC/whitespace normalization is only an additional equipment search name; it is
not an identity or fuzzy merge rule.

Mapping entries require an exact source ID, expected name, load type, reviewed
source and valid selectable catalog exercise IDs. Unknown/ambiguous equipment is
visible with “対応種目は現在準備中です”. Mappings can be added server-side without an
app update when the exercise ID already exists in the app's catalog. Older clients
ignore unknown exercise IDs safely. Another chain can use the same tables and UI;
normalize its source to the documented workbook columns or adapt the reader only,
then supply its own chain ID and reviewed mapping file.

## Current source audit (2026-09-23)

244 stores, 219 equipment IDs, 1,582 store-equipment pairs, no duplicate keys or
orphan references. Equipment coverage: 35 published, 3 not published, 206 not
collected. All 244 station fields and all 219 manufacturer/model fields are absent.
368 quantities are explicit; 1,214 remain null. 60 equipment IDs have 106 reviewed
exercise mappings; 159 are unmapped. This is partial equipment coverage, not a claim
that every listed store has a complete equipment inventory.

## Mapping updates (2026-09-24)

Direct equipment mappings cover 205 of 219 equipment IDs with 349
equipment-exercise rows. In addition, 163 multi-equipment rules / 326 rule items
model combinations such as rack + bench and dumbbell + adjustable bench.

Generic racks are direct sources for barbell movements that do not require a bench.
Bench-press variants are only considered available when a compatible rack and bench
are both present. Dumbbell press/fly variants likewise require dumbbells plus the
appropriate bench angle. Generic curl benches no longer imply preacher curls by
themselves; they require dumbbells or a rack/barbell source.

14 equipment IDs still have no direct mapping. Explicit manual review can resolve a source row
that is still marked `needs_review` by setting `reviewed_source_override: true`
on that exact mapping entry; the importer rejects implicit overrides and rejects
using the flag on clean source rows. Some are intentionally represented
only through combination rules (generic benches), while others remain source rows
marked `needs_review` or are too ambiguous to infer safely. The store filter uses
the server-side `gym_store_exercise_ids` function to union direct mappings with
satisfied combination rules.

Apply migrations through
`202609240006_fitplace_spine_bench_mapping.sql` (or rerun the importer with both
`--mapping` and `--requirements`) before treating these counts as live
linked-project data.
## Search and reports

Public search is server-paged (30), equipment is store-scoped/paged (50). Search
matches store name, city or station, with literal wildcard escaping. Trigram/FK
indexes cover lookups. Reports require login, are inserted as `pending`, and never
mutate the master. Only administrators can approve/reject/resolve. The database
serializes each user's reports and rejects repeated same-store/equipment/type
reports within 5 minutes, and more than 5 reports per user in 5 minutes. New-equipment
reports require a name. RLS and column grants prevent self-approval and cross-user
reads/deletes. Account deletion cascades personal registrations and reports.

## Verification

```sh
python3 -m unittest discover -s tool/gym_import -p 'test_*.py'
supabase db query --linked --file supabase/tests/gym_equipment.sql
supabase db query --linked --file supabase/tests/gym_multi_equipment_rules.sql
flutter test --no-pub test/gym_integration_test.dart test/fitplace_catalog_test.dart test/workout_gym_test.dart
flutter analyze --no-pub
```

DB tests use temporary fixtures inside a rolled-back transaction. Native smoke QA
is `integration_test/gym_store_flow_test.dart` with the existing screenshot driver
and local ignored `supabase.json` build configuration. It reads real public master
data; it does not create real accounts, post reports or modify the master.
