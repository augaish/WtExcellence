require "test_helper"

# Two locale traps have already caused visible defects: t('document') printed a
# whole translation hash as a table heading, and a namespace added under an
# existing scalar key was silently discarded depending on which file loaded
# last. Both are the same mistake — one key used as both a label and a
# namespace — so it is checked here rather than remembered.
#
# The merged I18n store cannot show either problem, because merging is what
# hides it. These tests read the project's own YAML files instead.
class LocalesConsistencyTest < ActiveSupport::TestCase
  LOCALE_FILES = Dir[Rails.root.join("config/locales/**/*.yml")].sort.freeze

  test "no key is used as both a label and a namespace" do
    conflicts = Hash.new { |hash, key| hash[key] = [] }

    I18n.available_locales.each do |locale|
      shapes = Hash.new { |hash, key| hash[key] = {} }

      LOCALE_FILES.each do |file|
        tree = YAML.unsafe_load_file(file)[locale.to_s]
        next if tree.nil?

        record_shapes(tree, File.basename(file), shapes)
      end

      shapes.each do |path, by_file|
        next if by_file.values.uniq.size < 2

        conflicts["#{locale}.#{path}"] = by_file
      end
    end

    assert_empty conflicts,
      "these keys are a string in one file and a namespace in another, so one silently wins: #{conflicts.inspect}"
  end

  # One direction only. A key the product shows in English must have Arabic, or
  # the Arabic UI falls back to English — the defect the review reported. The
  # reverse is legitimate: Arabic has six plural categories where English has
  # two, and Rails supplies the English datetime tree from the gem.
  test "every key the project defines in English exists in Arabic" do
    missing = (keys_defined_in("en") - keys_defined_in("ar")).sort

    assert_empty missing, "these keys have no Arabic translation: #{missing.join(', ')}"
  end

  # A key defined in two files with two different values is decided by load
  # order, which is not a decision anyone made. It is how a corrected label came
  # back unchanged: the fix was applied to one copy and the other won.
  test "no key is defined twice with different values" do
    I18n.available_locales.each do |locale|
      values = Hash.new { |hash, key| hash[key] = {} }

      LOCALE_FILES.each do |file|
        tree = YAML.unsafe_load_file(file)[locale.to_s]
        next if tree.nil?

        leaf_paths(tree).each do |path|
          values[path][File.basename(file)] = dig_path(tree, path)
        end
      end

      conflicting = values.select { |_path, by_file| by_file.values.uniq.size > 1 }

      assert_empty conflicting.keys.sort,
        "#{locale}: defined more than once with different values, so load order decides which wins"
    end
  end

  private

  def dig_path(tree, path)
    path.split(".").reduce(tree) { |node, key| node.is_a?(Hash) ? node[key] : nil }
  end

  # Records, per dotted path, whether each file treats it as a leaf or a branch.
  def record_shapes(tree, file, shapes, prefix = nil)
    tree.each do |key, value|
      path = [ prefix, key ].compact.join(".")
      shapes[path][file] = value.is_a?(Hash) ? :branch : :leaf

      record_shapes(value, file, shapes, path) if value.is_a?(Hash)
    end
  end

  def keys_defined_in(locale)
    LOCALE_FILES.flat_map do |file|
      tree = YAML.unsafe_load_file(file)[locale]
      tree.nil? ? [] : leaf_paths(tree)
    end.uniq
  end

  def leaf_paths(tree, prefix = nil, paths = [])
    tree.each do |key, value|
      path = [ prefix, key ].compact.join(".")

      if value.is_a?(Hash)
        leaf_paths(value, path, paths)
      else
        paths << path
      end
    end
    paths
  end
end
