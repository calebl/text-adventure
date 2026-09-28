# WHETHER TWO WRITTEN NAMES ARE ONE NAME, asked one way everywhere a name is
# looked up: equal once each is put through Ruby's `String#downcase`, and
# nothing wider. The Rust engine asks exactly this -- its `text::casecmp` and
# every collision check in its realization are `ruby_downcase` on both sides --
# so a name the engine resolves is a name the server resolves, and the reverse.
#
# NOT SQLite's `LOWER()`, which folds ASCII only. `WHERE LOWER(name) = ?` bound
# to a Ruby-downcased string folded the two sides by two different rules, so a
# stored name that opened on a capital outside ASCII ("Écu of the ward") did not
# even match itself: a realization naming it again wrote a second row of one
# name, and a proposal naming a person by their own full name placed nobody.
# That is why `.any?` and `.first` read the names into Ruby and compare them here
# rather than in SQL -- every set they read is one story's, and bounded.
#
# NOT `String#casecmp?` either, which case-FOLDS ("Straße" and "STRASSE" are one
# name to it, two to `downcase`). Folding is the wider rule, but it is not the
# engine's, and one rule is the whole point: two lookups that disagree about
# which names are one name are how the same word came to resolve two ways.
#
# THE DATABASE'S OWN GUARD IS NARROWER, AND THAT IS SAFE. `Character`'s unique
# index is on `LOWER(fullname)`, SQLite's ASCII fold, and its validation asks
# the same. Two names that fold together there differ only in ASCII case, so
# they are one name here too: a lookup asked through this module refuses
# everything the index would, and a name the index would take that this calls
# taken is refused before it gets that far.
#
# WIDER QUESTIONS ARE ASKED ELSEWHERE, ON PURPOSE. Whether two names spell the
# same PLACE with an article or a run of spaces between them is
# `WorldSeed.natural_key`, which builds on this same `downcase`.
module SameName
  module_function

  def key(name) = name.to_s.downcase

  def same?(one, other) = key(one) == key(other)

  # WHETHER ANY ROW OF `scope` IS CALLED `name` in any of `columns`.
  def any?(scope, name, *columns)
    !find_id(scope, name, columns).nil?
  end

  # THE FIRST ROW OF `scope` CALLED `name` in any of `columns`, or nil. First by
  # id, so a scope holding two answers the same way twice.
  def first(scope, name, *columns)
    id = find_id(scope, name, columns)
    id && scope.find(id)
  end

  def find_id(scope, name, columns)
    wanted = key(name)
    scope.order(:id).pluck(:id, *columns)
         .detect { |(_, *names)| names.any? { |written| !written.nil? && key(written) == wanted } }
         &.first
  end
  private_class_method :find_id
end
