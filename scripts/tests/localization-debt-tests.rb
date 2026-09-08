#!/usr/bin/env ruby
# Focused, hermetic reporter tests; no app or Homebrew process is launched.
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'

class LocalizationDebtTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SCRIPT = File.join(ROOT, 'scripts/localization-debt.rb')
  LOCALES = %w[de en fr it pt zh-Hans].freeze

  def setup
    @root = Dir.mktmpdir('cakebrew-l10n-test-')
    @fixture_metadata_path = File.join(@root, 'metadata.json')
    LOCALES.each { |locale| strings(locale, '"z" = "z"; "a" = "a"; "brand" = "Cakebrew"; "different" = "English";') }
    strings('de', '"z" = "z"; "a" = "a"; "brand" = "Cakebrew"; "different" = "Deutsch";')
    write_fixture_metadata('placeholders' => [{ 'key' => 'a', 'locales' => ['de'], 'reason' => 'New English placeholder.' }],
                           'intentional' => [{ 'key' => 'brand', 'locales' => ['de'], 'reason' => 'Product name.' }])
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def strings(locale, source)
    path = File.join(@root, 'Cakebrew', "#{locale}.lproj", 'Localizable.strings')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def write_fixture_metadata(overrides = {})
    File.write(@fixture_metadata_path, JSON.generate({ 'version' => 1, 'placeholders' => [], 'intentional' => [] }.merge(overrides)))
  end

  def run_report(*arguments, env: {}, default_root: false)
    paths = default_root ? [] : ['--root', @root, '--metadata', @fixture_metadata_path]
    Open3.capture3(env, RbConfig.ruby, SCRIPT, *paths, *arguments, chdir: @root)
  end

  def report
    out, err, status = run_report('--json')
    assert status.success?, err
    JSON.parse(out)
  end

  def assert_invalid(fragment)
    out, err, status = run_report('--json')
    refute status.success?, 'Invalid input must fail instead of reporting zero debt.'
    assert_empty out
    assert_includes err, fragment
  end

  def test_classification_counts_and_debt_do_not_fail
    data = report
    assert_equal 4, data.fetch('english_keys')
    de = data.fetch('locales').fetch('de')
    assert_equal ['a'], de.fetch('placeholders')
    assert_equal ['brand'], de.fetch('intentional')
    assert_equal ['z'], de.fetch('unreviewed_equal')
    assert_equal ['different'], de.fetch('different')
    assert_equal [], de.fetch('missing')
    assert_equal [], de.fetch('extra')
    assert_equal 1, de.fetch('counts').fetch('placeholders')
    assert_equal %w[a brand different z], data.fetch('locales').fetch('fr').fetch('unreviewed_equal')
    assert_equal %w[de fr it pt zh-Hans], data.fetch('locales').keys
  end

  def test_result_metadata_remains_readable_after_fixture_teardown
    completed = self.class.new('test_classification_counts_and_debt_do_not_fail')
    completed.setup
    completed.teardown

    # Minitest 5.25 reads metadata in Result.from after teardown. Exercise
    # that callback on older Minitest too, if the suite exposes the method.
    assert_kind_of Hash, completed.metadata if completed.respond_to?(:metadata)
    assert_kind_of Minitest::Result, Minitest::Result.from(completed)
  end

  def test_missing_and_extra_are_separate
    strings('fr', '"a" = "a"; "extra" = "Bonjour";')
    fr = report.fetch('locales').fetch('fr')
    assert_equal %w[brand different z], fr.fetch('missing')
    assert_equal ['extra'], fr.fetch('extra')
    assert_equal ['a'], fr.fetch('unreviewed_equal')
  end

  def test_native_comments_escapes_and_utf16
    write_fixture_metadata
    source = '/* "fake" = "ignored"; */ "a\\U0062" = "line\\n\\"quoted\\""; // comment' + "\n" + '"\\U4F60" = "\\U597D";'
    LOCALES.each { |locale| strings(locale, source) }
    path = File.join(@root, 'Cakebrew/de.lproj/Localizable.strings')
    File.binwrite(path, "\xFF\xFE".b + source.encode('UTF-16LE').b)
    assert_equal ['ab', '你'], report.fetch('locales').fetch('de').fetch('unreviewed_equal')
  end

  def test_duplicate_literal_and_escaped_keys_are_rejected
    ['"a" = "one"; "a" = "two";', '"a" = "one"; "\\U0061" = "two";'].each do |source|
      strings('fr', source)
      assert_invalid('duplicate key')
    end
  end

  def test_malformed_or_non_string_tables_fail
    ['"a" = "unterminated;', '"a" = ("array");', '"a" = { "nested" = "value"; };'].each do |source|
      strings('fr', source)
      assert_invalid('fr')
    end
  end

  def test_locale_inventory_cannot_silently_shrink_or_expand
    FileUtils.rm(File.join(@root, 'Cakebrew/fr.lproj/Localizable.strings'))
    assert_invalid('locale inventory')
    strings('fr', '"a" = "a";')
    strings('es', '"a" = "a";')
    assert_invalid('locale inventory')
  end

  def test_metadata_is_strict_and_stale_entries_fail
    cases = [
      { 'version' => 2 }, { 'unknown' => [] }, { 'placeholders' => {} },
      { 'placeholders' => [{ 'key' => 'absent', 'locales' => ['de'], 'reason' => 'x' }] },
      { 'placeholders' => [{ 'key' => 'a', 'locales' => ['en'], 'reason' => 'x' }] },
      { 'placeholders' => [{ 'key' => 'a', 'locales' => [], 'reason' => 'x' }] },
      { 'placeholders' => [{ 'key' => 'a', 'locales' => ['de', 'de'], 'reason' => 'x' }] },
      { 'placeholders' => [{ 'key' => 'a', 'locales' => ['de'], 'reason' => ' ' }] },
      { 'placeholders' => [{ 'key' => 'different', 'locales' => ['de'], 'reason' => 'stale' }] },
      { 'placeholders' => [{ 'key' => 'a', 'locales' => ['de'], 'reason' => 'x', 'typo' => true }] }
    ]
    cases.each { |value| write_fixture_metadata(value); assert_invalid('metadata') }
    entry = { 'key' => 'a', 'locales' => ['de'], 'reason' => 'x' }
    write_fixture_metadata('placeholders' => [entry], 'intentional' => [entry])
    assert_invalid('metadata')
    write_fixture_metadata('placeholders' => [entry, entry])
    assert_invalid('metadata')
    File.write(@fixture_metadata_path, '{bad')
    assert_invalid('metadata')
  end

  def test_markdown_is_deterministic_safe_and_summary_matches_stdout
    write_fixture_metadata
    LOCALES.each { |locale| strings(locale, '"::error::\\n<script>`&" = "same";') }
    summary = File.join(@root, 'summary.md')
    out, err, status = run_report('--summary', summary)
    assert status.success?, err
    assert_includes out, 'Different from English is not a translation-quality assessment.'
    assert_includes out, '&lt;script&gt;'
    refute_match(/^::error::/, out)
    refute_includes out, '<script>'
    assert_equal out, File.read(summary)
    assert_equal out, run_report.first
  end

  def test_invalid_input_does_not_write_summary
    strings('de', 'broken')
    summary = File.join(@root, 'summary.md')
    _, _, status = run_report('--summary', summary)
    refute status.success?
    refute File.exist?(summary)
  end

  def test_metadata_duplicate_json_fields_and_noninteger_version_fail
    File.write(@fixture_metadata_path, '{"version":2,"version":1,"placeholders":[],"intentional":[]}')
    assert_invalid('metadata')
    write_fixture_metadata('version' => 1.0)
    assert_invalid('metadata')
  end

  def test_bounded_input_invalid_encoding_and_cli_errors
    strings('fr', ' ' * (2 * 1024 * 1024 + 1))
    assert_invalid('exceeds')
    strings('fr', "\xFF".b)
    assert_invalid('encoding')
    _, err, status = run_report('--unknown')
    refute status.success?
    assert_includes err, 'invalid option'
    _, err, status = run_report('unexpected')
    refute status.success?
    assert_includes err, 'unexpected arguments'
  end

  def native_table(root, locale)
    path = File.join(root, 'Cakebrew', "#{locale}.lproj", 'Localizable.strings')
    out, err, status = Open3.capture3('/usr/bin/plutil', '-convert', 'json', '-o', '-', '--', path)
    assert status.success?, err
    JSON.parse(out)
  end

  def test_default_paths_are_independent_of_current_directory_and_counts_are_consistent
    out, err, status = run_report('--json', default_root: true)
    assert status.success?, err
    assert_inventory_report(JSON.parse(out), ROOT)
  end

  def assert_inventory_report(data, root)
    english_keys = native_table(root, 'en').keys.sort
    assert_equal english_keys.length, data.fetch('english_keys')
    assert_equal LOCALES - ['en'], data.fetch('locales').keys
    categories = %w[placeholders intentional unreviewed_equal different missing extra]
    (LOCALES - ['en']).each do |locale|
      row = data.fetch('locales').fetch(locale)
      assert_equal categories.sort, row.fetch('counts').keys.sort
      categories.each { |category| assert_equal row.fetch(category).length, row.fetch('counts').fetch(category) }
      # Every English key belongs to exactly one category, regardless of debt.
      assert_equal english_keys, (categories - ['extra']).flat_map { |category| row.fetch(category) }.sort
      locale_keys = native_table(root, locale).keys
      assert_equal (english_keys - locale_keys).sort, row.fetch('missing')
      assert_equal (locale_keys - english_keys).sort, row.fetch('extra')
    end
  end

  def test_valid_new_key_in_all_locales_does_not_fail_inventory_check
    before = report
    LOCALES.each do |locale|
      path = File.join(@root, 'Cakebrew', "#{locale}.lproj", 'Localizable.strings')
      File.open(path, 'a') { |file| file.write("\n\"Regression test new key\" = \"New English text\";\n") }
    end
    after = report
    assert_equal before.fetch('english_keys') + 1, after.fetch('english_keys')
    after.fetch('locales').each_value do |row|
      assert_includes row.fetch('unreviewed_equal'), 'Regression test new key'
    end
    assert_inventory_report(after, @root)
  end

  def test_unreviewed_translation_does_not_fail_inventory_check
    before = report.fetch('locales').fetch('de')
    key = 'z'
    assert_includes before.fetch('unreviewed_equal'), key
    values = native_table(@root, 'de')
    values[key] = 'Regressionstest: neuer deutscher Text'
    strings('de', values.map { |name, value| "#{JSON.generate(name)} = #{JSON.generate(value)};" }.join("\n"))
    after = report
    de = after.fetch('locales').fetch('de')
    assert_equal before.fetch('unreviewed_equal') - [key], de.fetch('unreviewed_equal')
    assert_equal (before.fetch('different') + [key]).sort, de.fetch('different')
    assert_inventory_report(after, @root)
  end

  def test_native_formulae_values_preserve_existing_translations
    expected = { 'de' => 'Formeln', 'fr' => 'Formules', 'it' => 'Formule', 'pt' => 'Fórmulas', 'zh-Hans' => 'Formulae' }
    actual = expected.keys.to_h do |locale|
      [locale, native_table(ROOT, locale).fetch('Formulae')]
    end
    assert_equal expected, actual
  end

  def test_ci_runs_tests_then_report_without_masking_errors
    source = File.read(File.join(ROOT, '.github/workflows/ci.yml'))
    assert_match(/ruby scripts\/tests\/localization-debt-tests\.rb/, source)
    assert_match(/ruby scripts\/localization-debt\.rb --summary "\$GITHUB_STEP_SUMMARY"/, source)
    assert_operator source.index('ruby scripts/tests/localization-debt-tests.rb'), :<, source.index('ruby scripts/localization-debt.rb')
    refute_includes source, 'continue-on-error'
  end
end
