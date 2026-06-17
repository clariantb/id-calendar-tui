# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'id-calendar-tui'
  spec.version       = '0.1.2'
  spec.authors       = ['Your Name']
  spec.email         = ['your.email@example.com']
  spec.summary       = 'Terminal-based Indonesian calendar with holiday support'
  spec.description   = 'A TUI calendar application displaying Indonesian public holidays with vim-like navigation'
  spec.homepage      = 'https://github.com/adiprnm/id-calendar-tui'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.files         = Dir.glob('{lib,bin,data}/**/*') + %w[README.md LICENSE]
  spec.bindir        = 'bin'
  spec.executables   = ['calendar']
  spec.require_paths = ['lib']

  spec.add_dependency 'pastel', '~> 0.8'
  spec.add_dependency 'tty-cursor', '~> 0.7'
end
