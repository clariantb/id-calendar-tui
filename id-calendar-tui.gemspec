# frozen_string_literal: true

Gem::Specification.new do |spec|
  # Fork of adiprnm/id-calendar-tui with official SKB holiday data; the
  # upstream gem name `id-calendar-tui` belongs to the upstream author.
  spec.name          = 'id-calendar-tui-clariant'
  spec.version       = '0.1.3'
  spec.authors       = ['clariantb']
  spec.summary       = 'Terminal-based Indonesian calendar with official holiday data'
  spec.description   = 'A TUI calendar application displaying Indonesian public holidays and cuti bersama ' \
                       'from the official SKB 3 Menteri announcements, with vim-like navigation'
  spec.homepage      = 'https://github.com/clariantb/id-calendar-tui'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.files         = Dir.glob('{lib,bin,data}/**/*') + %w[README.md LICENSE]
  spec.bindir        = 'bin'
  spec.executables   = ['calendar']
  spec.require_paths = ['lib']

  spec.add_dependency 'pastel', '~> 0.8'
  spec.add_dependency 'tty-cursor', '~> 0.7'
end
