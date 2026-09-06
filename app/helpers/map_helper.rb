# The two strings the map draws on a node, and nothing else -- the picture's
# coordinates all come off `Story::Map`, so what is left for a helper is
# wording.
module MapHelper
  # WHAT A NODE SAYS ABOUT ITSELF UNDER ITS NAME, as marks rather than as
  # sentences, because the line is `Story::Map::NODE_WIDTH` wide. A zero says
  # nothing and is left off -- most rooms in most worlds have nobody in them and
  # nothing on the floor, and an empty line is quieter than four zeroes.
  #
  # "unwalked" IS NOT ONE OF THOSE, and is written on every place that has one:
  # the frontier is what this page is for, so it is said on the node whether or
  # not there is anything else to say about it.
  def map_node_marks(node)
    marks = []
    marks << "#{node.people}p" if node.people.positive?
    marks << "#{node.things}i" if node.things.positive?
    marks << "#{node.rooms}r" if node.rooms.positive?
    marks << node.location.danger if node.dangerous?
    marks << node.location.hazard if node.hazardous?
    marks << "unwalked" if node.frontier?
    marks.join(" · ")
  end

  # THE WHOLE OF WHAT THE RECORDS SAY ABOUT A PLACE, for the tooltip the browser
  # draws off an SVG `<title>` with no script involved.
  def map_node_reading(node)
    parts = [ node.name, node.location.detail_level ]
    parts << "you are here" if node.here
    parts << "nobody has walked in" unless node.visited
    parts << "#{node.people} present" if node.people.positive?
    parts << "#{node.things} lying here" if node.things.positive?
    parts << "#{node.rooms} rooms inside" if node.rooms.positive?
    parts << "danger: #{node.location.danger}" if node.dangerous?
    parts << "hazard: #{node.location.hazard} d#{node.location.hazard_die}" if node.hazardous?
    parts << node.box.to_s if node.box
    parts << "footprint #{node.location.width}x#{node.location.depth} paces" if node.interior? && node.box.nil?
    parts.join(" - ")
  end
end
