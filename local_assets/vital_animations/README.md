# Vital Free50 local trial

Only the five licensed videos below are bundled for the purchase evaluation. Put
the provider's `50gymworkouts.json` in `free50/` and the selected MP4 files in
`free50/videos/` before building locally. The JSON and MP4 files are ignored by
Git; do not commit them. An empty `videos/` directory is kept so a clean checkout
still builds and falls back to the existing form guide.

| SETKEEP exercise ID | Vital asset ID |
| --- | --- |
| `pec_fly` | `0051` |
| `barbell_squat` | `0054` |
| `leg_press` | `0074` |
| `rope_pushdown` | `0085` |
| `machine_lateral_raise` | `0097` |

The provider ID is only an external media reference. SETKEEP's exercise catalog,
history, favorites and existing 3D publication status remain independent.
`ExerciseMedia` also has a `videoUrl` field so an approved production rollout can
resolve a private/public Supabase Storage or CDN URL instead of a bundled asset.
That rollout must replace the local availability check and use a suitable access
policy; it does not require changing exercise IDs.
