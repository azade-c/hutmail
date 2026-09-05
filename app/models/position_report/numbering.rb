module PositionReport::Numbering
  extend ActiveSupport::Concern

  included do
    before_create :assign_sequence

    validates :sequence, uniqueness: { scope: :vessel_id }
  end

  def number_label
    "n° #{sequence}"
  end

  private
    # Numbers are handed out once and never reused, so POSREPORTDEL 12 means the
    # same point today as it did when the skipper read it off the map — even if
    # the points around it have been deleted since. Counting the surviving
    # reports would not do: deleting the last one would free its number, and the
    # next report would answer to a POSREPORTDEL still on its way over the radio.
    def assign_sequence
      self.sequence ||= claim_next_sequence
    end

    def claim_next_sequence
      vessel.increment!(:last_position_sequence)
      vessel.last_position_sequence
    end
end
