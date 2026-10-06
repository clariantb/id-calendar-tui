#!/usr/bin/env ruby
# frozen_string_literal: true

# Imports Indonesian national holidays + cuti bersama from the government's
# official SKB 3 Menteri announcement and writes them to data/holidays.json.
#
#   ruby scripts/fetch_holidays.rb
#     Scheduled mode (.github/workflows/update-holidays.yml). Imports any missing
#     year in [this year, next year] from the known announcement URLs, then runs
#     the tripwire. Exits 1 when a human must act.
#
#   ruby scripts/fetch_holidays.rb --year 2028 --url https://www.setneg.go.id/baca/index/...
#     Imports (or re-imports) one year from a specific announcement article, for
#     when the government publishes under a URL the scheduled mode does not know.
#
# Design notes:
# - There is no official machine-readable source: the SKB PDF is a scan, so we
#   parse the Setneg/Setkab press release that lists every date. Its format
#   changes between years, so every parse is validated against the article
#   itself: the stated "sebanyak N hari" totals and the weekday printed next to
#   every date must match. A year is written only if all checks pass.
# - Years already in the file are never overwritten by scheduled mode, so hand
#   added amendments (SKB perubahan, e.g. cuti bersama 18 Agustus 2025) persist.
# - Tripwire: Google's public Indonesian holiday calendar is used only as an
#   alarm, never as data. If it lists cuti bersama for a year we do not have,
#   the SKB is out but our import missed it. If it lists a public holiday we do
#   not have, an amendment was probably issued. Either way the job fails so the
#   repository owner is notified instead of the calendar being silently wrong.
# - The app never touches the network; it reads only the committed JSON.

require 'net/http'
require 'json'
require 'uri'
require 'date'
require 'cgi'
require 'optparse'

DATA_FILE = File.expand_path('../data/holidays.json', __dir__)
GOOGLE_ICS = 'https://calendar.google.com/calendar/ical/en.indonesian%23holiday%40group.v.calendar.google.com/public/basic.ics'
USER_AGENT = 'id-calendar-tui holiday importer (+https://github.com/clariantb/id-calendar-tui)'

# Where the announcement has been published in past years. Slugs are not
# guaranteed, which is what the tripwire and --url are for.
def candidate_urls(year)
  [
    "https://www.setneg.go.id/baca/index/inilah_skb_3_menteri_libur_nasional_dan_cuti_bersama_#{year}",
    "https://setkab.go.id/pemerintah-tetapkan-hari-libur-nasional-dan-cuti-bersama-tahun-#{year}/"
  ]
end

MONTHS = %w[januari februari maret april mei juni juli agustus september oktober november desember].freeze
WEEKDAYS = %w[minggu senin selasa rabu kamis jumat sabtu].freeze # index == Date#wday
MONTH_RE = /\b(?:#{MONTHS.join('|')})\b/i.freeze
WEEKDAY_RE = /\b(?:#{WEEKDAYS.join('|')})\b/i.freeze
# Leading run of an item that can belong to its date ("Rabu-Kamis, 10-11 Maret 2027").
DATE_PREFIX_RE = /\A(?:\s|,|\.|-|\(|\)|\bdan\b|\d{1,4}|#{MONTH_RE.source}|#{WEEKDAY_RE.source})+/i.freeze
# A date part ends at a month, a weekday, a year or a closing parenthesis; this
# keeps the "1" of "1 Muharam ..." in the name.
DATE_PREFIX_END_RE = /\A.*(?:#{MONTH_RE.source}|#{WEEKDAY_RE.source}|\d{4}|\))/im.freeze

RELIGIOUS_KEYWORDS = [
  'isra', 'idul', 'tahun baru islam', 'muharam', 'maulid', 'nyepi', 'waisak',
  'yesus', 'paskah', 'natal'
].freeze
CULTURAL_KEYWORDS = ['imlek'].freeze

class ImportError < StandardError; end

def classify(name)
  n = name.downcase
  return 'religious' if RELIGIOUS_KEYWORDS.any? { |k| n.include?(k) }
  return 'cultural' if CULTURAL_KEYWORDS.any? { |k| n.include?(k) }

  'national'
end

def http_get(url, redirects = 5)
  uri = URI(url)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 15, read_timeout: 30) do |http|
    http.get(uri.request_uri, 'User-Agent' => USER_AGENT)
  end
  if res.is_a?(Net::HTTPRedirection) && redirects.positive?
    return http_get(URI.join(url, res['location']).to_s, redirects - 1)
  end

  res
end

def html_to_lines(html)
  text = html.dup.force_encoding('UTF-8').scrub('')
             .gsub(%r{<(script|style)\b.*?</\1>}mi, '')
             .gsub(%r{<br\s*/?>|</?(p|li|ol|ul|tr|div|h\d)\b[^>]*>}i, "\n")
             .gsub(/<[^>]+>/, '')
  text = CGI.unescapeHTML(text)
         .gsub(/&nbsp;/i, ' ').gsub(/&[lr]dquo;/i, '"').gsub(/&[lr]squo;/i, "'").gsub(/&[nm]dash;/i, '-')
         .gsub(/\p{Cf}/, '')         # zero-width joiners pasted into the CMS
         .gsub(/[\u2010-\u2015]/, '-') # en/em dashes in ranges
         .tr("\u00a0", ' ')
  text.lines.map { |l| l.gsub(/\s+/, ' ').strip }.reject(&:empty?)
end

# "Rabu-Kamis" -> [3, 4]; "(Sabtu-Minggu)" -> [6, 0]
def weekdays_in(date_part)
  tokens = date_part.scan(/#{WEEKDAY_RE.source}|-/i).map(&:downcase)
  result = []
  tokens.each_with_index do |tok, i|
    next if tok == '-'

    wday = WEEKDAYS.index(tok)
    if i >= 2 && tokens[i - 1] == '-' && WEEKDAYS.include?(tokens[i - 2])
      d = result.last
      result << d while (d = (d + 1) % 7) != wday
    end
    result << wday
  end
  result
end

# "10-11 Maret 2027" / "9, 12 dan 15 Maret" / "31 Maret-1 April" -> [Date, ...]
def dates_in(date_part, year)
  dates = []
  pending = []
  cross_month_range = false
  prev = nil
  date_part.scan(/\d+|#{MONTH_RE.source}|-/i).each do |tok|
    if tok == '-'
      if prev =~ /\A\d+\z/
        pending << :range
      elsif prev =~ MONTH_RE
        cross_month_range = true
      end
    elsif tok =~ /\A\d+\z/
      n = tok.to_i
      if tok.length == 4
        raise ImportError, "year #{n} in '#{date_part}' (expected #{year})" unless n == year
      else
        pending << n
      end
    else
      month = MONTHS.index(tok.downcase) + 1
      new_dates = []
      pending.each_with_index do |p, i|
        next if p == :range

        if pending[i - 1] == :range && i >= 2
          (pending[i - 2] + 1..p).each { |d| new_dates << Date.new(year, month, d) }
        else
          new_dates << Date.new(year, month, p)
        end
      end
      raise ImportError, "month without day in '#{date_part}'" if new_dates.empty?

      if cross_month_range && dates.any?
        (dates.last + 1...new_dates.first).each { |d| dates << d }
      end
      dates.concat(new_dates)
      pending = []
      cross_month_range = false
    end
    prev = tok
  end
  raise ImportError, "day without month in '#{date_part}'" unless pending.empty?

  dates
end

def parse_item(line, year)
  body = line.sub(/\A\d+\.\s*/, '')
  prefix = body[DATE_PREFIX_RE].to_s[DATE_PREFIX_END_RE].to_s
  raise ImportError, "no date in item '#{line}'" unless prefix =~ MONTH_RE

  # Trailing list punctuation; keep the abbreviation dot in "saw." but drop "(Natal).".
  name = body[prefix.length..].sub(/\A[\s:,-]+/, '').sub(/[\s;]+\z/, '').sub(/\)\.\z/, ')')
  raise ImportError, "no name in item '#{line}'" if name.empty?

  dates = dates_in(prefix, year)
  wdays = weekdays_in(prefix)
  if wdays != dates.map(&:wday)
    raise ImportError, "weekdays #{wdays.map { |w| WEEKDAYS[w] }} do not match dates " \
                       "#{dates.map(&:to_s)} in item '#{line}'"
  end

  dates.map { |d| [d, name] }
end

def item_line?(line)
  line.sub(/\A\d+\.\s*/, '') =~ /\A(?:#{WEEKDAY_RE.source}|\d{1,2}\b)/i && line =~ MONTH_RE
end

# Items of the first list whose header line matches. Headers can also appear
# in unrelated text, so a header with no items right below it is skipped.
def list_under(lines)
  lines.each_index do |i|
    next unless yield(lines[i])

    items = lines[(i + 1)..].take_while { |l| item_line?(l) }
    return items if items.any?
  end
  nil
end

# Returns [{ 'date', 'name', 'type' }] for one announcement page, or raises.
def parse_announcement(html, year)
  lines = html_to_lines(html)
  text = lines.join("\n")

  declared_national = text[/libur nasional[^.\n]*?sebanyak\s+(\d+)\s+hari/i, 1]&.to_i
  declared_cuti = text[/cuti bersama\s+sebanyak\s+(\d+)\s+hari/i, 1]&.to_i
  raise ImportError, 'stated totals ("sebanyak N hari") not found' unless declared_national && declared_cuti

  national_items = list_under(lines) { |l| l =~ /daftar\b.*libur nasional/i && l !~ /cuti bersama/i }
  cuti_items = list_under(lines) { |l| l =~ /daftar\b.*cuti bersama/i }
  raise ImportError, 'holiday lists not found' unless national_items && cuti_items

  national = national_items.flat_map { |l| parse_item(l, year) }
  cuti = cuti_items.flat_map { |l| parse_item(l, year) }

  if national.size != declared_national
    raise ImportError, "parsed #{national.size} national holidays, article states #{declared_national}"
  end
  raise ImportError, "parsed #{cuti.size} cuti bersama days, article states #{declared_cuti}" if cuti.size != declared_cuti

  all_dates = (national + cuti).map(&:first)
  raise ImportError, 'duplicate dates in parsed lists' if all_dates.uniq.size != all_dates.size

  missing = [[1, 1], [8, 17], [12, 25]].map { |m, d| Date.new(year, m, d) } - national.map(&:first)
  raise ImportError, "fixed holidays missing: #{missing.map(&:to_s).join(', ')}" unless missing.empty?

  entries = national.map { |d, n| { 'date' => d.to_s, 'name' => n, 'type' => classify(n) } } +
            cuti.map { |d, n| { 'date' => d.to_s, 'name' => "Cuti Bersama #{n}", 'type' => classify(n) } }
  entries.sort_by { |e| e['date'] }
end

# [:imported, entries, url] | [:not_published, nil, nil]; raises if a page exists but fails validation.
def import_from_candidates(year)
  failures = []
  candidate_urls(year).each do |url|
    res = http_get(url)
    next unless res.is_a?(Net::HTTPSuccess)

    begin
      return [:imported, parse_announcement(res.body, year), url]
    rescue ImportError => e
      failures << "#{url}: #{e.message}"
    end
  rescue StandardError => e
    warn "  #{url}: #{e.class}: #{e.message}"
  end
  raise ImportError, failures.join("\n") unless failures.empty?

  [:not_published, nil, nil]
end

# { Date => [summary, public_holiday?] }
def google_events
  res = http_get(GOOGLE_ICS)
  raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

  body = res.body.force_encoding('UTF-8').gsub(/\r?\n[ \t]/, '') # unfold ICS lines
  body.scan(/BEGIN:VEVENT.*?END:VEVENT/m).each_with_object({}) do |ev, acc|
    date = ev[/DTSTART;VALUE=DATE:(\d{8})/, 1] or next
    acc[Date.strptime(date, '%Y%m%d')] = [ev[/^SUMMARY:(.*)$/, 1].to_s.strip, ev =~ /^DESCRIPTION:Public holiday/ ? true : false]
  end
end

def tripwire(years_data, window)
  events = google_events
  problems = []
  window.each do |year|
    in_year = events.select { |d, _| d.year == year }
    record = years_data[year.to_s]
    if record.nil?
      if in_year.any? { |_, (summary, _)| summary =~ /joint holiday/i }
        problems << "#{year}: Google already lists cuti bersama, so the SKB is out, but no announcement was found at " \
                    "#{candidate_urls(year).join(' or ')}. Find the Setneg/Setkab article and run: " \
                    "ruby scripts/fetch_holidays.rb --year #{year} --url URL"
      end
      next
    end

    ours = record['holidays'].map { |h| Date.parse(h['date']) }
    extra = in_year.select { |d, (_, pub)| pub && !ours.include?(d) }
    next if extra.empty?

    listed = extra.sort.map { |d, (summary, _)| "#{d} #{summary}" }.join('; ')
    problems << "#{year}: Google lists public holidays missing from data/holidays.json (an SKB amendment?): " \
                "#{listed}. Verify against official sources and add them to the #{year} holidays."
  end
  problems
rescue StandardError => e
  warn "tripwire skipped: could not read Google calendar (#{e.message})"
  []
end

def write_data(years)
  sorted = years.keys.sort.to_h { |k| [k, years[k]] }
  output = {
    '_comment' => 'Official SKB 3 Menteri holidays, imported by scripts/fetch_holidays.rb. ' \
                  'Scheduled runs only add missing years; hand-added amendments are kept.',
    'years' => sorted
  }
  File.write(DATA_FILE, "#{JSON.pretty_generate(output)}\n")
  puts "Wrote #{DATA_FILE} (years: #{sorted.keys.join(', ')})"
end

def report(problems)
  problems.each do |p|
    warn p
    puts "::error::#{p}" if ENV['GITHUB_ACTIONS']
  end
end

options = {}
OptionParser.new do |o|
  o.banner = 'Usage: fetch_holidays.rb [--year YEAR --url ANNOUNCEMENT_URL]'
  o.on('--year YEAR', Integer) { |v| options[:year] = v }
  o.on('--url URL') { |v| options[:url] = v }
  o.on('--force', 'replace a year that is already imported, dropping its hand-added amendments') { options[:force] = true }
end.parse!

years = File.exist?(DATA_FILE) ? (JSON.parse(File.read(DATA_FILE))['years'] || {}) : {}

if options[:url] || options[:year]
  abort 'both --year and --url are required' unless options[:url] && options[:year]
  if years.key?(options[:year].to_s) && !options[:force]
    abort "#{options[:year]} is already imported (sources: #{years[options[:year].to_s]['sources'].join(', ')}). " \
          'Re-importing replaces it and drops hand-added amendments; pass --force to do so.'
  end

  res = http_get(options[:url])
  abort "#{options[:url]}: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

  begin
    entries = parse_announcement(res.body, options[:year])
  rescue ImportError => e
    abort "#{options[:year]}: #{e.message}"
  end
  years[options[:year].to_s] = { 'sources' => [options[:url]], 'holidays' => entries }
  puts "#{options[:year]}: imported #{entries.size} days from #{options[:url]}"
  write_data(years)
  exit
end

window = (Date.today.year..Date.today.year + 1)
problems = []
changed = false

window.each do |year|
  if years.key?(year.to_s)
    puts "#{year}: already imported, keeping"
    next
  end

  begin
    status, entries, url = import_from_candidates(year)
    if status == :not_published
      puts "#{year}: not announced yet"
      next
    end
    years[year.to_s] = { 'sources' => [url], 'holidays' => entries }
    changed = true
    puts "#{year}: imported #{entries.size} days from #{url}"
  rescue ImportError => e
    problems << "#{year}: announcement found but failed validation, nothing written:\n#{e.message}"
  end
end

write_data(years) if changed
problems.concat(tripwire(years, window))
report(problems)
exit(problems.empty? ? 0 : 1)
