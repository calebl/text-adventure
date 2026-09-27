# PUT BACK TOGETHER A PLACE THAT WAS SPLIT AROUND ONE ROOM.
#
# A world generated before `Location::Parameters::ONE_ROOM` meant "the named
# place is the room" may hold a place laid out as a single room that fills it,
# named "<place> room 1", with the doorway and the whole of the play history on
# that room. `Location::OneRoomFold` is the work and its header is the reasoning,
# including which row survives and why.
#
# ONLY THE EXACT SHAPE IS FOLDED. A candidate that falls short of the proof is
# left alone and named in a note here, and `Story::Doctor` keeps reporting it
# (`one_room_place_left_split`) until somebody decides it by hand.
#
# BEFORE THE SAFE REPAIRS AND THE DOCTOR, so they read the folded world rather
# than reporting the doorway and the room this is about to remove.
#
# IDEMPOTENT: a folded place has no child left, so it is no longer a candidate,
# and a second run finds nothing.
class Update::Steps::FoldOneRoomPlaces < Update::Step
  def self.key = :fold_one_room_places
  def self.reason = "turn a place split around one room back into the room the player chose"

  def call
    lines = []
    notes = []

    stories.each do |story|
      proven, unproven = Location::OneRoomFold.candidates(story).partition(&:proven?)

      proven.each do |fold|
        name = fold.room.name
        fold.fold! unless dry_run?
        lines << "#{story.title}: #{dry_run? ? "would fold" : "folded"} #{name} into #{fold.place.name}"
      end
      unproven.each do |fold|
        notes << "#{story.title}: #{fold.room.name} is left inside #{fold.place.name} -- #{fold.reasons.join("; ")}"
      end
    end

    report(changed: lines.any?, lines: lines, notes: notes)
  end
end
