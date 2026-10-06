#!/usr/bin/env ruby
# frozen_string_literal: true

# Prepares an automated holiday-data release: bumps the patch version in the
# gemspec, records the release in CHANGELOG.md (taking over any [Unreleased]
# section), and prints the new version. Used by
# .github/workflows/update-holidays.yml.
#
#   ruby scripts/bump_version.rb [PREVIOUS_RELEASE_TAG]

require 'json'
require 'date'

ROOT = File.expand_path('..', __dir__)
GEMSPEC = File.join(ROOT, 'id-calendar-tui.gemspec')
CHANGELOG = File.join(ROOT, 'CHANGELOG.md')
DATA = 'data/holidays.json'
VERSION_RE = /(spec\.version\s*=\s*)'([^']+)'/.freeze

def released_years(tag)
  return {} if tag.to_s.empty?

  json = IO.popen(['git', '-C', ROOT, 'show', "#{tag}:#{DATA}"], err: File::NULL, &:read)
  $?.success? ? (JSON.parse(json)['years'] || {}) : {}
end

spec = File.read(GEMSPEC)
current = spec[VERSION_RE, 2] or abort "no spec.version in #{GEMSPEC}"
major, minor, patch = Gem::Version.new(current).segments
version = [major, minor || 0, (patch || 0) + 1].join('.')
File.write(GEMSPEC, spec.sub(VERSION_RE) { "#{Regexp.last_match(1)}'#{version}'" })

before = released_years(ARGV[0])
after = JSON.parse(File.read(File.join(ROOT, DATA)))['years']
changed = after.keys.reject { |year| after[year] == before[year] }.sort
note = "- Holiday data updated for #{changed.join(', ')} from the official SKB 3 Menteri announcements"
entry = "## [#{version}] - #{Date.today.iso8601}\n\n### Holiday data\n#{note}\n"

log = File.read(CHANGELOG)
log = if log.match?(/^## \[Unreleased\]\n/)
        log.sub(/^## \[Unreleased\]\n/) { entry }
      else
        log.sub(/^## \[/) { "#{entry}\n## [" }
      end
File.write(CHANGELOG, log)

puts version
