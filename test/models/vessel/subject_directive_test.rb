require "test_helper"

class Vessel::SubjectDirectiveTest < ActiveSupport::TestCase
  test "extracts subject and strips the directive line from the body" do
    subject, body = Vessel::SubjectDirective.extract("OBJET Arrivée mardi /OBJET\nOn arrive à Horta.")

    assert_equal "Arrivée mardi", subject
    assert_equal "On arrive à Horta.", body
  end

  test "is case insensitive on the directive keywords" do
    subject, body = Vessel::SubjectDirective.extract("objet Coucou /objet\nSalut")

    assert_equal "Coucou", subject
    assert_equal "Salut", body
  end

  test "tolerates leading blank lines before the directive" do
    subject, body = Vessel::SubjectDirective.extract("\n\nOBJET Bonjour /OBJET\nLe corps")

    assert_equal "Bonjour", subject
    assert_equal "Le corps", body
  end

  test "tolerates surrounding whitespace inside the directive" do
    subject, body = Vessel::SubjectDirective.extract("  OBJET   Plein de vent   /OBJET  \nTexte")

    assert_equal "Plein de vent", subject
    assert_equal "Texte", body
  end

  test "returns nil subject and untouched body when no directive" do
    subject, body = Vessel::SubjectDirective.extract("Just a normal message\nsecond line")

    assert_nil subject
    assert_equal "Just a normal message\nsecond line", body
  end

  test "ignores a directive that is not on the first non-empty line" do
    text = "Some intro\nOBJET Too late /OBJET\nbody"
    subject, body = Vessel::SubjectDirective.extract(text)

    assert_nil subject
    assert_equal text, body
  end

  test "ignores an unclosed directive" do
    text = "OBJET no closing tag\nbody here"
    subject, body = Vessel::SubjectDirective.extract(text)

    assert_nil subject
    assert_equal text, body
  end

  test "keeps multi-line body after the directive" do
    subject, body = Vessel::SubjectDirective.extract("OBJET Sujet /OBJET\nligne 1\nligne 2")

    assert_equal "Sujet", subject
    assert_equal "ligne 1\nligne 2", body
  end

  test "handles blank or nil body" do
    assert_equal [ nil, "" ], Vessel::SubjectDirective.extract(nil)
    assert_equal [ nil, "" ], Vessel::SubjectDirective.extract("")
  end
end
