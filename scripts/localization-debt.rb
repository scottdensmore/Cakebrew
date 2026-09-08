#!/usr/bin/env ruby
# Repository policy lives in AGENTS.md. Uses macOS plutil, not a second .strings decoder.
require 'json'
require 'open3'
require 'optparse'
require 'strscan'
require 'cgi'

module LocalizationDebt
  LOCALES = %w[de en fr it pt zh-Hans].freeze
  CATEGORIES = %w[placeholders intentional unreviewed_equal different missing extra].freeze
  LIMIT = 2 * 1024 * 1024
  class InvalidInput < StandardError; end

  class MetadataObject < Hash
    def []=(key, value)
      raise InvalidInput, "duplicate metadata field: #{key.inspect}" if key?(key)
      super
    end
  end

  def self.read(path)
    raise InvalidInput, "input exceeds #{LIMIT} bytes: #{path}" if File.size(path) > LIMIT
    File.binread(path)
  end

  def self.native_json(source, label)
    out, err, status = Open3.capture3('/usr/bin/plutil', '-convert', 'json', '-o', '-', '--', '-', stdin_data: source)
    raise InvalidInput, "invalid strings in #{label}: #{err.strip} #{out.strip}" unless status.success?
    JSON.parse(out)
  end

  def self.strings(path)
    source = read(path)
    if source.start_with?("\xFF\xFE".b)
      source = source.byteslice(2..-1).force_encoding('UTF-16LE').encode('UTF-8')
    elsif source.start_with?("\xFE\xFF".b)
      source = source.byteslice(2..-1).force_encoding('UTF-16BE').encode('UTF-8')
    else
      source = source.sub(/\A\xEF\xBB\xBF/n, '').force_encoding('UTF-8')
    end
    raise InvalidInput, "invalid encoding in #{path}" unless source.valid_encoding?

    # plutil accepts duplicate dictionary keys (last wins). Scan only the flat,
    # quoted .strings grammar, then let plutil decode key escapes in an ARRAY
    # where duplicates survive. Values are always decoded by plutil as well.
    scanner = StringScanner.new(source)
    keys = []
    skip = -> { scanner.skip(/(?:\s+|\/\/[^\n]*(?:\n|\z)|\/\*.*?\*\/)+/m) }
    quoted = /"(?:[^"\\]|\\.)*"/m
    loop do
      skip.call
      break if scanner.eos?
      key = scanner.scan(quoted)
      raise InvalidInput, "expected quoted string key in #{path}" unless key
      keys << key
      skip.call
      raise InvalidInput, "expected = in #{path}" unless scanner.scan(/=/)
      skip.call
      raise InvalidInput, "expected quoted string value in #{path}" unless scanner.scan(quoted)
      skip.call
      raise InvalidInput, "expected ; in #{path}" unless scanner.scan(/;/)
    end
    decoded_keys = native_json("(#{keys.join(',')})", path)
    raise InvalidInput, "duplicate key in #{path}" unless decoded_keys.uniq.length == decoded_keys.length
    values = native_json("{#{source}\n}", path)
    unless values.is_a?(Hash) && values.keys.sort == decoded_keys.sort && values.values.all? { |value| value.is_a?(String) }
      raise InvalidInput, "expected flat string dictionary in #{path}"
    end
    values
  end

  def self.annotations(path, tables)
    data = JSON.parse(read(path), object_class: MetadataObject)
    unless data.is_a?(Hash) && data.keys.sort == %w[intentional placeholders version] &&
           data['version'].is_a?(Integer) && data['version'] == 1
      raise InvalidInput, 'metadata must have version 1, placeholders and intentional arrays'
    end
    marks = {}
    %w[placeholders intentional].each do |category|
      entries = data[category]
      raise InvalidInput, "metadata #{category} must be an array" unless entries.is_a?(Array)
      entries.each do |entry|
        unless entry.is_a?(Hash) && entry.keys.sort == %w[key locales reason] && entry['key'].is_a?(String) &&
               entry['reason'].is_a?(String) && !entry['reason'].strip.empty? && entry['locales'].is_a?(Array) &&
               !entry['locales'].empty? && entry['locales'].uniq == entry['locales'] &&
               (entry['locales'] - (LOCALES - ['en'])).empty?
          raise InvalidInput, "invalid metadata entry in #{category}"
        end
        key = entry['key']
        entry['locales'].each do |locale|
          pair = [locale, key]
          raise InvalidInput, "duplicate/conflicting metadata for #{pair.inspect}" if marks.key?(pair)
          unless tables['en'].key?(key) && tables[locale].key?(key) && tables[locale][key] == tables['en'][key]
            raise InvalidInput, "stale or unknown metadata for #{pair.inspect}; annotated values must equal English"
          end
          marks[pair] = category
        end
      end
    end
    marks
  rescue JSON::ParserError => error
    raise InvalidInput, "invalid metadata: #{error.message}"
  end

  def self.report(root, metadata_path)
    paths = Dir.glob(File.join(root, 'Cakebrew/*.lproj/Localizable.strings')).sort
    inventory = paths.map { |path| File.basename(File.dirname(path), '.lproj') }
    raise InvalidInput, "locale inventory must be #{LOCALES.join(', ')}; found #{inventory.join(', ')}" unless inventory == LOCALES
    tables = paths.to_h { |path| [File.basename(File.dirname(path), '.lproj'), strings(path)] }
    marks = annotations(metadata_path, tables)
    english = tables.fetch('en')
    locales = (LOCALES - ['en']).to_h do |locale|
      values = tables.fetch(locale)
      row = CATEGORIES.to_h { |category| [category, []] }
      english.keys.sort.each do |key|
        category = if !values.key?(key)
                     'missing'
                   elsif values[key] != english[key]
                     'different'
                   else
                     marks.fetch([locale, key], 'unreviewed_equal')
                   end
        row[category] << key
      end
      row['extra'] = (values.keys - english.keys).sort
      row['counts'] = CATEGORIES.to_h { |category| [category, row[category].length] }
      [locale, row]
    end
    { 'english_keys' => english.length, 'locales' => locales }
  end

  def self.markdown(data)
    lines = ['# Localization debt', '', "English keys: #{data['english_keys']}", '',
             'Informational: debt counts do not fail CI. Unreviewed equal values are candidates, not confirmed placeholders.',
             'Different from English is not a translation-quality assessment.', '',
             '| Locale | Confirmed placeholders | Intentional English | Unreviewed equal | Different | Missing | Extra |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    data['locales'].each do |locale, row|
      lines << "| #{locale} | #{CATEGORIES.map { |category| row['counts'][category] }.join(' | ')} |"
    end
    data['locales'].each do |locale, row|
      lines += ['', "## #{locale}"]
      CATEGORIES.each do |category|
        lines += ['', "### #{category} (#{row['counts'][category]})", '', '<pre>']
        row[category].each { |key| lines << "  #{CGI.escapeHTML(JSON.generate(key))}" }
        lines << '</pre>'
      end
    end
    lines.join("\n") + "\n"
  end

  def self.main(arguments)
    root = File.expand_path('..', __dir__)
    metadata_path = File.join(__dir__, 'localization-debt.json')
    json = false
    summary = nil
    parser = OptionParser.new do |options|
      options.banner = 'Usage: ruby scripts/localization-debt.rb [--root PATH] [--metadata PATH] [--json] [--summary PATH]'
      options.on('--root PATH') { |path| root = File.expand_path(path) }
      options.on('--metadata PATH') { |path| metadata_path = File.expand_path(path) }
      options.on('--json') { json = true }
      options.on('--summary PATH') { |path| summary = path }
    end
    parser.parse!(arguments)
    raise InvalidInput, "unexpected arguments: #{arguments.inspect}" unless arguments.empty?
    data = report(root, metadata_path)
    text = markdown(data)
    File.open(summary, 'a') { |file| file.write(text) } if summary
    puts(json ? JSON.pretty_generate(data) : text)
    0
  rescue InvalidInput, OptionParser::ParseError, SystemCallError, EncodingError => error
    # JSON quoting prevents input filenames/diagnostics from becoming CI commands.
    warn "Localization report error: #{JSON.generate(error.message)}"
    1
  end
end

exit LocalizationDebt.main(ARGV) if $PROGRAM_NAME == __FILE__
