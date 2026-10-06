require 'date'
require 'json'

module IndonesiaCalendar
  module Holidays
    DATA_FILE = File.expand_path('../data/holidays.json', __dir__)

    TYPE_SYMBOLS = { 'national' => :national, 'religious' => :religious, 'cultural' => :cultural }.freeze

    # Loaded once and memoized: { year(Integer) => { Date => { name:, type: } } }
    # Only years whose SKB 3 Menteri has been imported are present; nothing is
    # guessed for other years, because most holidays follow lunar calendars and
    # cuti bersama is a yearly government decision.
    def self.data
      @data ||= load_data
    end

    def self.load_data
      raw = JSON.parse(File.read(DATA_FILE))
      (raw['years'] || {}).each_with_object({}) do |(year_str, record), result|
        days = {}
        record['holidays'].each do |entry|
          date = Date.parse(entry['date'])
          days[date] ||= { name: entry['name'], type: TYPE_SYMBOLS.fetch(entry['type'], :national) }
        end
        result[year_str.to_i] = days.sort.to_h
      end
    rescue JSON::ParserError, ArgumentError, NoMethodError => e
      # The file is hand-edited for amendments; a broken edit must be loud, not
      # silently turn every year into "belum diumumkan".
      raise "#{DATA_FILE} is invalid (#{e.class}: #{e.message})"
    end

    def self.announced?(year)
      data.key?(year)
    end

    def self.latest_announced_year
      data.keys.max
    end

    def self.holidays_for_month(year, month)
      data.fetch(year, {}).select { |date, _| date.month == month }
    end
  end
end
