# The physical half of a universe. Split from Universe::SocietalSchema so each
# call asks for a handful of fields -- local models get noticeably less reliable
# when asked to fill ten long prose fields in one response.
#
# Every field states its length explicitly. Without one, a strong model answers
# a bare "Physics of the world" with several thousand characters, and these
# fields are interpolated into every downstream prompt.
class Universe::PhysicalSchema < RubyLLM::Schema
  string :physics, description: "How physics works here, including any magic or supernatural forces and their limits. One paragraph, 3 to 5 sentences.", max_length: 900
  string :technology, description: "The level and character of technology available. One paragraph, 3 to 5 sentences.", max_length: 900
  string :weapons, description: "The weapons that exist and who carries them. One paragraph, 3 to 5 sentences.", max_length: 900
  string :geographies, description: "The notable terrain, regions and landmarks of this world. One paragraph, 3 to 5 sentences.", max_length: 900
end
