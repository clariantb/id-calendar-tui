require 'date'
require 'pastel'
require 'tty-cursor'

require_relative 'holidays'

module IndonesiaCalendar
  class CalendarApp
    MONTHS_ID = %w[
      Januari Februari Maret April Mei Juni
      Juli Agustus September Oktober November Desember
    ].freeze

    WEEKDAYS_ID = %w[Min Sen Sel Rab Kam Jum Sab].freeze

    CELL_WIDTH = 4

    attr_reader :view_date

    def initialize
      @pastel = Pastel.new
      @view_date = Date.today
      @running = true
      @show_help = true
      @mode = :calendar
      @screen_width = 70
      @cursor = TTY::Cursor
      @needs_redraw = false
    end

    def run
      setup_terminal
      render
      main_loop
    ensure
      cleanup_terminal
      puts
      puts @pastel.green('Terima kasih telah menggunakan Kalender Indonesia!')
    end

    private

    def windows?
      RUBY_PLATFORM =~ /mswin|mingw|cygwin/
    end

    def setup_terminal
      @cursor.hide
      print "\e[?1049h"
      print "\e[?25l"  # Hide cursor using escape sequence

      if windows?
        setup_windows_terminal
      else
        @original_stty = `stty -g 2>/dev/null`.chomp
        system('stty cbreak -echo min 1 time 0 2>/dev/null') || system('stty -icanon -echo min 1 time 0 2>/dev/null')
      end
      $stdout.flush
    end

    def setup_windows_terminal
      require 'io/console'
      require 'win32api'

      # Get the Windows console handle
      kernel32 = Win32API.new('kernel32', 'GetStdHandle', ['L'], 'L')
      @stdout_handle = kernel32.call(-11)  # STD_OUTPUT_HANDLE = -11
      @stdin_handle = kernel32.call(-10)   # STD_INPUT_HANDLE = -10

      # Save and set console input mode
      get_mode = Win32API.new('kernel32', 'GetConsoleMode', %w[L P], 'I')
      set_mode = Win32API.new('kernel32', 'SetConsoleMode', %w[L L], 'I')

      mode_buf = [0].pack('L')
      get_mode.call(@stdin_handle, mode_buf)
      @original_console_mode = mode_buf.unpack1('L')

      # Enable window input, disable line input and echo
      new_mode = 0x0080 | 0x0008 # ENABLE_WINDOW_INPUT | ENABLE_PROCESSED_INPUT
      set_mode.call(@stdin_handle, new_mode)

      # Set output mode for virtual terminal processing
      get_mode.call(@stdout_handle, mode_buf)
      @original_stdout_mode = mode_buf.unpack1('L')
      set_mode.call(@stdout_handle, @original_stdout_mode | 0x0004) # ENABLE_VIRTUAL_TERMINAL_PROCESSING
    rescue LoadError
      # Fall back to basic mode
    end

    def cleanup_terminal
      if windows?
        cleanup_windows_terminal
      elsif @original_stty && !@original_stty.empty?
        system("stty #{@original_stty} 2>/dev/null")
      end
      print "\e[?25h" # Show cursor using escape sequence
      @cursor.show
      print "\e[?1049l"
      $stdout.flush
    end

    def cleanup_windows_terminal
      if @stdin_handle && @original_console_mode
        set_mode = Win32API.new('kernel32', 'SetConsoleMode', %w[L L], 'I')
        set_mode.call(@stdin_handle, @original_console_mode)
      end
      if @stdout_handle && @original_stdout_mode
        set_mode = Win32API.new('kernel32', 'SetConsoleMode', %w[L L], 'I')
        set_mode.call(@stdout_handle, @original_stdout_mode)
      end
    rescue StandardError
      # Ignore errors during cleanup
    end

    def get_terminal_size
      if windows?
        get_windows_terminal_size
      else
        height, width = `stty size`.split.map(&:to_i)
        [height, width]
      end
    rescue StandardError
      [24, 80] # Default fallback
    end

    def get_windows_terminal_size
      require 'io/console'
      $stdout.winsize
    rescue StandardError
      [24, 80]
    end

    def main_loop
      while @running
        changed = handle_input
        render if changed || @needs_redraw
        @needs_redraw = false
      end
    end

    def render
      terminal_height, terminal_width = get_terminal_size

      # Calculate vertical centering - position in upper third of screen
      ui_height = 15 # Smaller value = higher on screen
      top_padding = [(terminal_height - ui_height) / 3, 0].max

      # Calculate horizontal centering
      left_padding = [(terminal_width - @screen_width) / 2, 0].max

      print "\e[2J"  # Clear entire screen
      print "\e[H"   # Move to home position

      # Move cursor to calculated vertical position
      print "\e[#{top_padding}H" if top_padding > 0

      # Render each component centered
      title = render_title
      calendar = render_calendar
      holiday_panel = render_holiday_panel
      status_bar = render_status_bar

      all_content = [title, calendar, holiday_panel, status_bar].join("\n")

      # Add left padding to each line
      centered_lines = all_content.split("\n").map do |line|
        ' ' * left_padding + line
      end

      print centered_lines.join("\n")
      $stdout.flush
    end

    def render_title
      title_text = 'KALENDER INDONESIA'
      date_text = "#{MONTHS_ID[@view_date.month - 1]} #{@view_date.year}"
      today_text = "Hari Ini: #{Date.today.day} #{MONTHS_ID[Date.today.month - 1]} #{Date.today.year}"

      lines = []
      lines << @pastel.cyan("┌#{'─' * (@screen_width - 2)}┐")
      lines << @pastel.cyan('│') + (' ' * (@screen_width - 2)) + @pastel.cyan('│')
      lines << @pastel.cyan('│') + center_text(@pastel.bold.yellow("★ #{title_text} ★"),
                                               @screen_width - 2) + @pastel.cyan('│')
      lines << @pastel.cyan('│') + center_text(@pastel.white(date_text), @screen_width - 2) + @pastel.cyan('│')
      lines << @pastel.cyan('│') + center_text(@pastel.bright_black(today_text), @screen_width - 2) + @pastel.cyan('│')
      lines << @pastel.cyan('│') + (' ' * (@screen_width - 2)) + @pastel.cyan('│')
      lines << @pastel.cyan("└#{'─' * (@screen_width - 2)}┘")

      lines.join("\n")
    end

    def render_calendar
      month_holidays = IndonesiaCalendar::Holidays.holidays_for_month(@view_date.year, @view_date.month)

      first_day = Date.new(@view_date.year, @view_date.month, 1)
      last_day = Date.new(@view_date.year, @view_date.month, -1)
      days_in_month = last_day.day
      start_wday = first_day.wday

      lines = []

      # Calendar content width should match screen width minus borders
      content_width = @screen_width - 4 # │ space ... space │
      calendar_grid_width = CELL_WIDTH * 7 + 6 # 7 cells + 6 spaces between
      calendar_padding = (content_width - calendar_grid_width) / 2

      title = " #{MONTHS_ID[@view_date.month - 1]} #{@view_date.year} "
      lines << @pastel.cyan("┌─#{title}#{'─' * (@screen_width - 3 - title.length)}┐")
      lines << @pastel.cyan('│') + (' ' * (@screen_width - 2)) + @pastel.cyan('│')

      header = WEEKDAYS_ID.each_with_index.map do |d, i|
        if [0, 6].include?(i)
          @pastel.red(d.center(CELL_WIDTH))
        else
          @pastel.yellow(d.center(CELL_WIDTH))
        end
      end.join(' ')

      header_visible = header.gsub(/\e\[[0-9;]*m/, '')
      # Center the header in the content area
      lines << @pastel.cyan("│ #{' ' * calendar_padding}#{header}#{' ' * (content_width - calendar_padding - header_visible.length)} │")
      lines << @pastel.cyan("│ #{' ' * calendar_padding}#{'─' * calendar_grid_width}#{' ' * (content_width - calendar_padding - calendar_grid_width)} │")

      current_line = Array.new(start_wday) { ' ' * CELL_WIDTH }

      (1..days_in_month).each do |day|
        current_date = Date.new(@view_date.year, @view_date.month, day)
        day_str = format_day_cell(current_date, day, month_holidays)
        current_line << day_str

        next unless current_line.length == 7

        line_content = current_line.join(' ')
        line_visible = line_content.gsub(/\e\[[0-9;]*m/, '')
        lines << @pastel.cyan("│ #{' ' * calendar_padding}#{line_content}#{' ' * (content_width - calendar_padding - line_visible.length)} │")
        current_line = []
      end

      unless current_line.empty?
        current_line += Array.new(7 - current_line.length, ' ' * CELL_WIDTH)
        line_content = current_line.join(' ')
        line_visible = line_content.gsub(/\e\[[0-9;]*m/, '')
        lines << @pastel.cyan("│ #{' ' * calendar_padding}#{line_content}#{' ' * (content_width - calendar_padding - line_visible.length)} │")
      end

      weeks_count = ((days_in_month + start_wday) / 7.0).ceil
      (5 - weeks_count).times do
        lines << @pastel.cyan("│ #{' ' * calendar_padding}#{' ' * calendar_grid_width}#{' ' * (content_width - calendar_padding - calendar_grid_width)} │")
      end

      lines << @pastel.cyan('│') + (' ' * (@screen_width - 2)) + @pastel.cyan('│')
      lines << @pastel.cyan("└#{'─' * (@screen_width - 2)}┘")

      lines.join("\n")
    end

    def format_day_cell(date, day, month_holidays)
      day_num = day.to_s.rjust(2)
      is_holiday = month_holidays.key?(date)
      is_today = date == Date.today
      is_weekend = date.wday == 0 || date.wday == 6

      if is_today
        @pastel.on_green.black(" #{day_num} ")
      elsif is_holiday
        @pastel.red(" #{day_num}*")
      elsif is_weekend
        @pastel.bright_black(" #{day_num} ")
      else
        @pastel.white(" #{day_num} ")
      end
    end

    def render_holiday_panel
      month_holidays = IndonesiaCalendar::Holidays.holidays_for_month(@view_date.year, @view_date.month)

      lines = []
      lines << @pastel.yellow("┌─ Hari Libur #{'─' * (@screen_width - 15)}┐")
      lines << @pastel.yellow('│') + (' ' * (@screen_width - 2)) + @pastel.yellow('│')

      if !IndonesiaCalendar::Holidays.announced?(@view_date.year)
        unknown_year_notice(@view_date.year).each do |text|
          lines << @pastel.yellow('│') + @pastel.bright_black(text.ljust(@screen_width - 2)) + @pastel.yellow('│')
        end
      elsif month_holidays.empty?
        text = '  Tidak ada hari libur bulan ini'
        lines << @pastel.yellow('│') + text.ljust(@screen_width - 2) + @pastel.yellow('│')
      else
        month_holidays.each do |date, holiday|
          type = format_holiday_type(holiday[:type])
          type_visible = type.gsub(/\e\[[0-9;]*m/, '')

          # Truncate long official names (e.g. "Cuti Bersama ...") so the panel
          # border stays aligned and the padding below can never go negative.
          fixed_width = 4 + 2 + 2 + 1 + type_visible.length # "    " + day + ". " + " " + type
          name_budget = [@screen_width - 2 - fixed_width, 1].max
          name_text = holiday[:name]
          name_text = "#{name_text[0, name_budget - 1]}…" if name_text.length > name_budget

          day_str = @pastel.cyan(date.day.to_s.rjust(2))
          name = @pastel.white(name_text)

          line = "    #{day_str}. #{name} #{type}"
          line_visible = line.gsub(/\e\[[0-9;]*m/, '')
          lines << @pastel.yellow('│') + line + ' ' * [@screen_width - 2 - line_visible.length, 0].max + @pastel.yellow('│')
        end
      end

      lines << @pastel.yellow("│#{' ' * (@screen_width - 2)}│")
      lines << @pastel.yellow("└#{'─' * (@screen_width - 2)}┘")

      lines.join("\n")
    end

    def unknown_year_notice(year)
      latest = IndonesiaCalendar::Holidays.latest_announced_year
      if latest.nil? || year > latest
        ["  Hari libur #{year} belum diumumkan pemerintah.",
         '  Menunggu SKB 3 Menteri tentang libur nasional dan cuti bersama.']
      else
        ["  Data hari libur #{year} tidak tersedia."]
      end
    end

    def format_holiday_type(type)
      case type
      when :national
        @pastel.red('[Nasional]')
      when :religious
        @pastel.magenta('[Keagamaan]')
      when :cultural
        @pastel.cyan('[Budaya]')
      else
        ''
      end
    end

    def render_status_bar
      lines = []

      help_items = [
        "#{@pastel.bright_black('h')} #{@pastel.bright_black('Bulan')}#{@pastel.bright_black(' -')}",
        "#{@pastel.bright_black('l')} #{@pastel.bright_black('Bulan')}#{@pastel.bright_black(' +')}",
        "#{@pastel.bright_black('j')} #{@pastel.bright_black('Tahun')}#{@pastel.bright_black(' -')}",
        "#{@pastel.bright_black('k')} #{@pastel.bright_black('Tahun')}#{@pastel.bright_black(' +')}",
        "#{@pastel.bright_black('g')} #{@pastel.bright_black('Today')}",
        "#{@pastel.bright_black('q')} #{@pastel.bright_black('Keluar')}"
      ]

      help_text = help_items.join('  ')
      help_visible = help_text.gsub(/\e\[[0-9;]*m/, '')
      content_width = @screen_width - 4 # │ space ... space │
      help_padding = (content_width - help_visible.length) / 2
      help_line = " #{' ' * help_padding}#{help_text}#{' ' * (content_width - help_visible.length - help_padding)} "

      lines << ''
      lines << " #{help_line} "

      lines.join("\n")
    end

    def handle_input
      changed = false
      begin
        key = read_char
        return false if key.nil?

        if key == "\e"
          c2 = read_char
          return false if c2.nil?

          if c2 == '['
            c3 = read_char
            case c3
            when 'C'
              @view_date = @view_date >> 1
              changed = true
            when 'D'
              @view_date = @view_date << 1
              changed = true
            end
          end
          return changed
        end

        case key
        when 'q', 'Q', "\u0003"
          @running = false
        when 'h', 'H'
          @view_date = @view_date << 1
          changed = true
        when 'l', 'L'
          @view_date = @view_date >> 1
          changed = true
        when 'j', 'J'
          @view_date = Date.new(@view_date.year - 1, @view_date.month, 1)
          changed = true
        when 'k', 'K'
          @view_date = Date.new(@view_date.year + 1, @view_date.month, 1)
          changed = true
        when 'g'
          @view_date = Date.today
          changed = true
        end
      rescue IOError, Errno::EIO
        @running = false
      rescue StandardError => e
        # Ignore errors
      end
      changed
    end

    def read_char
      if windows?
        read_char_windows
      else
        read_char_unix
      end
    end

    def read_char_windows
      require 'io/console'
      # On Windows, use console API for proper key reading
      begin
        # Use IO#raw if available (Ruby 2.4+)
        $stdin.raw do
          return $stdin.getch
        end
      rescue StandardError
        # Fallback for older Ruby versions
        $stdin.getch
      end
    end

    def read_char_unix
      $stdin.getc
    end

    def center_text(text, width)
      visible_width = text.gsub(/\e\[[0-9;]*m/, '').length
      total_padding = [(width - visible_width), 0].max
      left_padding = total_padding / 2
      right_padding = total_padding - left_padding
      ' ' * left_padding + text + ' ' * right_padding
    end
  end
end
