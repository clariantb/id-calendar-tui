require 'date'
require 'json'

module IndonesiaCalendar
  module Holidays
    DATA_FILE = File.expand_path('../data/holidays.json', __dir__)

    TYPE_SYMBOLS = { 'national' => :national, 'religious' => :religious, 'cultural' => :cultural }.freeze

    # National holidays with mathematically fixed dates. Used as a fallback for
    # years the API has not published yet, so the calendar is never empty.
    FIXED = {
      [1, 1] => 'Tahun Baru Masehi',
      [5, 1] => 'Hari Buruh Internasional',
      [6, 1] => 'Hari Lahir Pancasila',
      [8, 17] => 'Hari Kemerdekaan Republik Indonesia',
      [12, 25] => 'Hari Raya Natal'
    }.freeze

    # Loaded once and memoized: { year(Integer) => { Date => { name:, type: } } }
    def self.data
      @data ||= load_data
    end

    def self.load_data
      raw = JSON.parse(File.read(DATA_FILE))
      result = {}
      (raw['years'] || {}).each do |year_str, entries|
        year = year_str.to_i
        result[year] = {}
        entries.each do |entry|
          date = Date.parse(entry['date'])
          result[year][date] = { name: entry['name'], type: TYPE_SYMBOLS.fetch(entry['type'], :national) }
        end
      end
      result
    rescue StandardError
      {}
    end

    # Authoritative API data when available (includes cuti bersama); otherwise a
    # computed fallback of the deterministic national + Christian holidays. Lunar
    # holidays (Islamic/Imlek/Nyepi/Waisak) only appear for published years.
    def self.all_holidays_for_year(year)
      return data[year].sort.to_h if data.key?(year)

      computed_holidays(year).sort.to_h
    end

    def self.holidays_for_month(year, month)
      all_holidays_for_year(year).select { |date, _| date.month == month }
    end

    def self.computed_holidays(year)
      result = {}
      FIXED.each { |(month, day), name| result[Date.new(year, month, day)] = { name: name, type: :national } }

      easter = calculate_easter(year)
      result[easter - 2] = { name: 'Wafat Yesus Kristus (Jumat Agung)', type: :religious }
      result[easter] = { name: 'Hari Paskah', type: :religious }
      result[easter + 39] = { name: 'Kenaikan Yesus Kristus', type: :religious }
      result
    end

    # Anonymous Gregorian (Gauss) algorithm — valid for any year.
    def self.calculate_easter(year)
      a = year % 19
      b = year / 100
      c = year % 100
      d = b / 4
      e = b % 4
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = (19 * a + b - d - g + 15) % 30
      i = c / 4
      k = c % 4
      l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month = (h + l - 7 * m + 114) / 31
      day = ((h + l - 7 * m + 114) % 31) + 1
      Date.new(year, month, day)
    end
  end
end
