# Extracts an optional subject from the first line of an outbound message body.
#
# Sailors can override the default "Hutmail message" subject by leading the body
# with a single-line directive:
#
#   OBJET Arrivée mardi /OBJET
#   On arrive mardi à Horta, tout va bien.
#
# Rules:
#   - The directive must be on the very first non-empty line of the body.
#   - It is case-insensitive ("objet" is tolerated).
#   - It must be single-line: both OBJET and /OBJET on the same line.
#   - Everything after the closing /OBJET (following lines) is the message body.
#   - If no well-formed directive is found, the subject is nil and the body is
#     returned untouched (current behaviour: default subject applies).
class Vessel::SubjectDirective
  DIRECTIVE = /\A[ \t]*OBJET[ \t]+(.+?)[ \t]*\/OBJET[ \t]*\r?\n?/i

  def self.extract(body)
    new(body).extract
  end

  def initialize(body)
    @body = body.to_s
  end

  def extract
    if (match = leading_directive)
      [ subject_from(match), body_without_directive(match) ]
    else
      [ nil, @body ]
    end
  end

  private
    def leading_directive
      stripped = @body.sub(/\A(?:[ \t]*\r?\n)+/, "")
      @leading_offset = @body.length - stripped.length
      stripped.match(DIRECTIVE)
    end

    def subject_from(match)
      match[1].strip
    end

    def body_without_directive(match)
      consumed = @leading_offset + match.end(0)
      @body[consumed..].to_s
    end
end
