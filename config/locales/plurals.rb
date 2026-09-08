# Arabic has six plural categories; the default backend knows three, so without
# this a count of two renders with the "other" form and reads wrongly.
# The rule is the CLDR one for Arabic.
{
  ar: {
    i18n: {
      plural: {
        keys: [ :zero, :one, :two, :few, :many, :other ],
        rule: lambda do |n|
          mod100 = n % 100

          if n.zero? then :zero
          elsif n == 1 then :one
          elsif n == 2 then :two
          elsif (3..10).cover?(mod100) then :few
          elsif (11..99).cover?(mod100) then :many
          else :other
          end
        end
      }
    }
  }
}
