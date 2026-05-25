# Cutting a release

Releases are fully automated by `.github/workflows/release.yml`. Tag a
commit on `main` with a `v…` tag and push the tag.

```bash
git tag -a v2.0.0 -m "bizzymod-stats 2.0.0"
git push origin v2.0.0
```

The workflow then:

1. Runs `sourceknight build` (same as CI).
2. Stages a release tree:

   ```
   bizzymod-stats-<version>/
   ├── addons/sourcemod/
   │   ├── plugins/bizzymod_stats.smx
   │   ├── gamedata/bizzymod_stats.txt
   │   ├── translations/bizzymod_stats.phrases.txt
   │   └── configs/bizzymod_stats/{databases,bizzymod_stats}.cfg.example
   ├── schema/
   │   ├── migrations/mysql/*.sql
   │   ├── migrate.py
   │   ├── install.sh
   │   └── requirements.txt
   ├── source.tar.gz
   ├── README.md
   ├── LICENSE
   └── INSTALL.md
   ```

3. Zips it into `bizzymod-stats-<version>.zip`.
4. Generates a changelog from `git log <prev-tag>..HEAD`.
5. Creates a GitHub Release and attaches the zip + changelog.

Versions containing a `-` (e.g. `v2.1.0-rc1`) are marked as pre-releases.

## Version policy

- **MAJOR** — breaking changes to the schema that need user action
  (manual data migration, deprecated columns dropped) or to the
  databases.cfg entry name.
- **MINOR** — new stats, new awards, new commands. Forward-compatible.
- **PATCH** — bug fixes, scoring tweaks via CVar defaults, doc updates.

Schema migrations are always **additive within a minor series**. A
breaking migration (drops, type changes that lose data) bumps MAJOR and
is announced in the release notes.

## Local dry-run

```bash
sourceknight build
ls .sourceknight/**/bizzymod_stats.smx
```

To exercise the packaging logic locally, the same shell snippet from
`release.yml` works from a clean tree — just replace `${{ steps.ver…}}`
with a literal version string.
