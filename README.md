# ID Calendar TUI

[![Gem Version](https://badge.fury.io/rb/id-calendar-tui-clariant.svg)](https://badge.fury.io/rb/id-calendar-tui-clariant)
[![Docker Image](https://img.shields.io/badge/GHCR-latest-blue?logo=docker)](https://github.com/clariantb/id-calendar-tui/pkgs/container/id-calendar-tui)

A terminal-based calendar application for Indonesian public holidays with vim-like navigation.

Fork of [adiprnm/id-calendar-tui](https://github.com/adiprnm/id-calendar-tui) that
takes holiday data from the official SKB 3 Menteri announcements and releases it
automatically, published as the `id-calendar-tui-clariant` gem.

![Calendar Screenshot](screenshot.png)

## Features

- Full calendar view with Indonesian public holidays
- Vim-like navigation (h/j/k/l)
- Navigate months with arrow keys
- Jump to today with `g`
- Color-coded holidays (National, Religious, Cultural)
- Clean, centered TUI interface

## Installation

### Via RubyGems

```bash
gem install id-calendar-tui-clariant
calendar
```

### Via Docker (GHCR)

```bash
docker run --rm -it ghcr.io/clariantb/id-calendar-tui:latest
```

### From Source

```bash
git clone https://github.com/clariantb/id-calendar-tui.git
cd id-calendar-tui
bundle install
bundle exec ruby bin/calendar
```

## Usage

```bash
# Run the calendar
calendar

# Or with bundle
bundle exec calendar
```

## Navigation

| Key | Action |
|-----|--------|
| `h`, `←` | Previous month |
| `l`, `→` | Next month |
| `j`, `k` | Previous/Next year |
| `g` | Go to today |
| `q`, `Ctrl+C` | Quit |

## Holidays Included

- **National Holidays**: New Year, Independence Day, etc.
- **Islamic Holidays**: Eid al-Fitr, Eid al-Adha, etc.
- **Hindu Holidays**: Nyepi (Day of Silence)
- **Chinese New Year**: Imlek, Cap Go Meh
- **Christian Holidays**: Good Friday, Easter, Christmas

### Holiday Data

Holiday dates (libur nasional and *cuti bersama*) live in `data/holidays.json` and
come from the government's official SKB 3 Menteri announcement as published by
Setneg/Setkab. There is no official machine-readable source, so
`scripts/fetch_holidays.rb` parses the press release and accepts it only if it
matches the article's own stated totals ("sebanyak N hari") and the weekday printed
beside every date.

A weekly GitHub Action (`.github/workflows/update-holidays.yml`) imports next
year's list as soon as it is announced (usually September–October) and commits it.
The action fails, so GitHub notifies the repository owner, when Google's public
Indonesian holiday calendar shows that a decree is out but the import found
nothing, or that a holiday was added by an amendment (*SKB perubahan*). To fix:

```bash
# Announcement published under a new URL
ruby scripts/fetch_holidays.rb --year 2028 --url https://www.setneg.go.id/baca/index/...
```

Amendments are added by hand to that year's `holidays` in `data/holidays.json`,
with the announcement URL in `sources`; `--year`/`--url` refuses to re-import an
existing year unless given `--force`, which would drop them. Scheduled runs never
overwrite a year that is already imported. Years that have not been announced
show *"belum diumumkan"* instead of guessed dates.

The app reads only this file (no network at runtime), so the same workflow also
releases: whenever `data/holidays.json` differs from the latest `v*` tag (a new
import or a pushed amendment), it bumps the patch version, adds a CHANGELOG
entry, tags, and dispatches `release.yml`, which validates the data and publishes
the gem and Docker image.

## Requirements

- Ruby 2.6+
- Terminal with color support

## Development

```bash
# Install dependencies
bundle install

# Run the application
bundle exec ruby bin/calendar

# Build gem
bundle exec gem build id-calendar-tui.gemspec

# Build Docker image
docker build -t id-calendar-tui .
```

## Releasing

Holiday data releases are automatic (see [Holiday Data](#holiday-data)). For a
code release:

```bash
# Update version in id-calendar-tui.gemspec and CHANGELOG.md
git add .
git commit -m "Bump version to x.x.x"
git tag vx.x.x
git push origin vx.x.x
```

Either way `release.yml` publishes to
[RubyGems](https://rubygems.org/gems/id-calendar-tui-clariant) and
[GHCR](https://github.com/clariantb/id-calendar-tui/pkgs/container/id-calendar-tui).
One-time setup is in [RELEASING.md](RELEASING.md).

## Contributing

Bug reports and pull requests are welcome.

## License

MIT License - see [LICENSE](LICENSE) file for details.