# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Holiday data is imported from the official SKB 3 Menteri announcements
  (Setneg/Setkab) instead of api-hari-libur, which had wrong 2027 dates (Nyepi,
  second day of Idulfitri, Paskah, all cuti bersama) and was missing cuti bersama
  16 February 2026
- Years with no announcement show "belum diumumkan" instead of a partial
  computed list
- The holiday update workflow runs weekly, keeps its schedule from being
  disabled for inactivity, and fails loudly when an announcement or amendment
  is not reflected in the data
- Holiday data changes are released automatically: the update workflow bumps
  the patch version, tags, and dispatches the release workflow, which refuses to
  publish data the app cannot load
- Published as the `id-calendar-tui-clariant` gem and
  `ghcr.io/clariantb/id-calendar-tui` image; the `id-calendar-tui` gem name
  belongs to the upstream author

### Fixed
- 2025 now includes the added cuti bersama on 18 August 2025

## [0.1.0] - 2025-03-09

### Added
- Initial release of ID Calendar TUI
- Full calendar view with Indonesian public holidays
- Vim-like navigation (h/l for months, j/k for years)
- Arrow key navigation support
- Jump to today with 'g'
- Color-coded holidays:
  - National holidays (red)
  - Religious holidays (magenta)
  - Cultural holidays (cyan)
- Holiday types displayed: National, Islamic, Hindu, Chinese, Christian
- Terminal UI with centered layout
- Windows compatibility support
- Docker support for containerized usage
- RubyGems distribution
- GitHub Container Registry (GHCR) distribution
- Automated release workflow via GitHub Actions

### Technical
- Removed unused gems (tty-reader, tty-box)
- Clean dependency list: pastel, tty-cursor only
- Support for Ruby 2.6+

[0.1.0]: https://github.com/adiprnm/id-calendar-tui/releases/tag/v0.1.0