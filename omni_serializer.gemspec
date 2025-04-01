# frozen_string_literal: true

require_relative 'lib/omni_serializer/version'

Gem::Specification.new do |spec|
  spec.name = 'omni_serializer'
  spec.version = OmniSerializer::VERSION
  spec.authors = ['Arkadiy Zabazhanov']
  spec.email = ['kinwizard@gmail.com']

  spec.summary = 'A universal serializer for Ruby'
  spec.description = 'Serializes an object graph to any format'
  spec.homepage = 'https://github.com/pyromaniac/omni_serializer'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "https://github.com/pyromaniac/omni_serializer"
  spec.metadata['changelog_uri'] = "https://github.com/pyromaniac/omni_serializer/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'dataloader'
  spec.add_dependency 'dry-initializer'
  spec.add_dependency 'dry-struct'
  spec.add_dependency 'dry-types'
end
