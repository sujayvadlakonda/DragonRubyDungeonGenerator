# A dungeon generator based off of https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/
# The generation process has 4 steps:

# 1. Attempt to create rooms a certain number of times
# 2. Create mazes using a random flood fill algorithm
# 3. Connect the mazes and the rooms
# 4. Remove any dead end maze tiles

class DungeonGenerator
  attr_gtk

  def tick
    defaults
    render
    if state.tick_count % 2 == 0 # Allows previous Thread to animate
      calc
    end
  end
  
  def defaults
    state.grid_size = 27 # Should always be an odd number
    state.cell_size = 20
    state.game_state ||= :room

    room.attempted ||= 0
    room.attempts = 200
    room.rects ||= []
    
    maze.points ||= []
    maze.flood_fill_stack ||= []

    connect.connectors ||= []
    connect.first_room ||= nil
    connect.flood_fill ||= []
    connect.main_region ||= []

    remove.dead_ends ||= []
  end

  def render
    render_dungeon_background
    render_room
    render_maze
    render_connect
    render_grid_lines
    outputs.labels << [800, 700, state.game_state]
  end

  def render_dungeon_background 
    background = [0, 0, grid_size, grid_size, dungeon_background_color]
    outputs.solids << scale_rect(background)
  end

  def render_room
    room.rects.each do |room|
      outputs.solids << scale_rect(room)
    end
  end

  def render_maze
    maze.points.each do |x, y|
      rect = [x, y, 1, 1, maze_color]
      outputs.solids << scale_rect(rect)
    end
  end

  def render_connect
    connect.main_region.each do |x, y|
      rect = [x, y, 1, 1, connect_color]
      outputs.solids << scale_rect(rect)
    end
  end

  def scale_rect rect 
    x, y, width, height, r, g, b = *rect
    [x * cell_size, y * cell_size, width * cell_size, height * cell_size, r, g, b]
  end

  def render_grid_lines 
    for i in 0..state.grid_size
      outputs.lines << vertical_line(i)
      outputs.lines << horizontal_line(i)
    end
  end

  def vertical_line column
    [column * cell_size, 0, column * cell_size, state.grid_size * cell_size]
  end

  def horizontal_line row
    [0, row * cell_size, state.grid_size * cell_size, row * cell_size]
  end


  def calc
    calc_room
    calc_maze
    calc_connect
    calc_remove
  end

  # Attempts to generate a room a certain number of times
  # If the room is valid it draws it
  # Else attempts another one
  def calc_room
    return unless state.game_state == :room
    return state.game_state = :maze if state.room.attempted >= state.room.attempts
    state.room.attempted += 1

    room = random_room

    if valid_room?(room) 
      state.room.rects << room
    else
      calc_room # Attempt to generate another room
    end
  end

  def valid_room? room
    rect_within_bounds?(room) && !rect_touches_room?(room)
  end

  def random_room
    room = random_square
    room = rectangularize(room)
    room << room_color
    room
  end

  def random_square
    x = rand(state.grid_size)
    y = rand(state.grid_size)
    size = rand(6) + 3 # Min size: 3, Max size: 8
    [x, y, size, size]
  end

  def rectangularize square
    # Weird math to make room more rectangular and less squarey
    x, y, width, height = *square
    rectangularity = rand(width / 2 + 1)
    width_or_height = rand(2)
    if width_or_height == 0
      width += rectangularity
    else
      height += rectangularity
    end

    # Force rect to have odd width and height
    if width % 2 == 0
      width -= 1
    end
    if height % 2 == 0
      height -= 1
    end

    [x, y, width, height]
  end

  def rect_within_bounds? rect
    x, y, width, height = *rect
    (x + width < grid_size) && (y + height < grid_size)
  end
  
  def point_intersect_room? x, y
    rect_intersect_room?([x, y, 1, 1])
  end

  def rect_intersect_room? rect
    room.rects.each do |room|
      return true if room.intersect_rect?(rect)
    end
    false
  end
  
  def point_touches_room? x, y
    rect_touches_room?([x, y, 1, 1])
  end
  
  def rect_touches_room? rect 
    x, y, width, height = *rect
    expanded_rect = [x - 1, y - 1, width + 2, height + 2]
    rect_intersect_room?(expanded_rect)
  end


  def calc_maze 
    return unless state.game_state == :maze
  
    return maze_flood_fill unless maze.flood_fill_stack.empty? # Maze Flood Fill Animations

    # Checks every point starting from top left corner
    # Tries to start a new maze path
    for x in 0..(state.grid_size - 1)
      for y in (state.grid_size - 1).downto(0)
        if maze_starting_point?(x, y)
          return add_maze(x, y)
        end
      end
    end

    state.game_state = :connect # If there are no more maze starting points
  end

  def maze_flood_fill
    return calc_maze if state.maze.flood_fill_stack.empty? # Start new maze if no flood fills
    
    # x, y is the point to be flood filled
    # direction is the direction in which the flood fill was approached
    x, y, direction = *maze.flood_fill_stack.pop

    return maze_flood_fill unless maze_flood_fillable?(x, y, direction)
    
    add_maze(x, y)
  end

  # Prepares to flood fill from any newly added maze
  def add_maze x, y
    maze.points << [x, y]
    random_valid_directions(x, y).each do |direction|
      maze.flood_fill_stack << translate_point(x, y, direction)
    end
  end

  def maze_flood_fillable? x, y, direction
    empty_point?(x, y) && !bumps_into_maze?(x, y, direction) && !point_touches_room?(x, y)
  end

  def empty_point? x, y
    !maze?(x, y) && !point_intersect_room?(x, y)
  end

  def bumps_into_maze? x, y, direction
    significant_points(x, y, direction).each do |sig_x, sig_y|
      return true if maze?(sig_x, sig_y)
    end
    false
  end

  # Points that have to be empty to flood fill x, y
  # Depends on the direction the flood fill was approached in
  def significant_points x, y, direction
    return left_significant_points(x, y) if direction == :left 
    return up_significant_points(x, y) if direction == :up
    return right_significant_points(x, y) if direction == :right 
    return down_significant_points(x, y) if direction == :down
  end
  
  def left_significant_points x, y
    [[x, y - 1], [x, y + 1], [x - 1, y - 1], [x - 1, y], [x - 1, y + 1]]
  end
  
  def up_significant_points x, y
    [[x - 1, y], [x + 1, y], [x - 1, y + 1], [x, y + 1], [x + 1, y + 1]] 
  end

  def right_significant_points x, y
    [[x, y - 1], [x, y + 1], [x + 1, y - 1], [x + 1, y], [x + 1, y + 1]] 
  end
  
  def down_significant_points x, y
    [[x - 1, y], [x + 1, y], [x - 1, y - 1], [x, y - 1], [x + 1, y - 1]] 
  end


  # 0. Identify All Connectors
  # 1. Pick a random room to be main region
  # 2. Open a random connector touching the main region 
  # 3. Flood fill all to main region
  # 4. Remove extra connectors
  # 5. If any connectors left, go to #2
  def calc_connect
    return unless state.game_state == :connect

    # Only runs when calc_connect is called for the first time
    unless connect.first_room
      calc_connectors
      connect.first_room = room.rects.clone.shift
    end


    if connect.flood_fill.empty?
      remove_extra_connectors
      if connect.connectors.empty?
        return state.game_state = :remove
      end
      open_connector
    end

    connect_flood_fill
  end

  def calc_connectors
    for x in 0..(state.grid_size - 1)
      for y in (state.grid_size - 1).downto(0)
        connect.connectors << [x, y] if connector?(x, y)
      end
    end
  end

  def remove_extra_connectors
    connect.connectors.select! { |x, y| connector?(x, y) }
  end

  # Flood fills multiple directions at once
  # Attempts to flood fill to all adjacent points
  def connect_flood_fill
    current_flood_fill = connect.flood_fill.clone
    connect.flood_fill = []

    current_flood_fill.each do |x, y|
      connect.main_region << [x, y]
      adjacent_points(x, y).each do |a_x, a_y|
        if connect_flood_fillable?(a_x, a_y)
          connect.flood_fill << [a_x, a_y]
        end
      end
    end

    connect.flood_fill.uniq!
  end

  def connector? x, y
    return false unless empty_point?(x, y)

    # 3 Types of regions
    connects_main_region = false
    connects_maze        = false
    rooms_connected      = 0

    # Checks what region the adjacent points belong to
    adjacent_points(x, y).each do |adj_x, adj_y|
      if connect.main_region.include?([adj_x, adj_y])
        connects_main_region = true
      elsif maze?(adj_x, adj_y)
        connects_maze = true
      elsif point_intersect_room?(adj_x, adj_y)
        rooms_connected += 1 
      end
    end

    # Tallies unique adjacent regions
    unique_regions_connected = 0
    if connects_main_region
      unique_regions_connected += 1
    end
    if connects_maze
      unique_regions_connected += 1
    end
    unique_regions_connected += rooms_connected

    unique_regions_connected > 1
  end

  
  def connect_flood_fillable? x, y
    return false if connect.main_region.include?([x, y])
    return true if point_intersect_room?(x, y)
    return true if maze?(x, y)
    false
  end

  def open_connector
    main_connectors = connect.connectors.select { |x, y| touches_main_region?(x, y) }
    connector = connect.connectors.delete(main_connectors[rand(main_connectors.length)])
    connect.flood_fill << connector
    maze.points << connector

    if rand(5) == 0 # 20% Chance For Extra Connector
      return unless connector

      room = room_touching_connector(*connector) # The room that is being connected
      return unless room

      room_connectors = connectors_touching_room(room) # The possible extra connectors
      return if room_connectors.empty?
      
      random_room_connector = room_connectors[rand(room_connectors.length)]
      connect.flood_fill << random_room_connector
      maze.points << random_room_connector
    end
  end

  def room_touching_connector x, y
    adjacent_points(x, y).each do |adj_x, adj_y|
      # The room that is being connected is not part of the main_region yet
      if !main_region?(adj_x, adj_y) && point_intersect_room?(adj_x, adj_y)
        room.rects.each do |rect|
          return rect if rect.intersect_rect?([adj_x, adj_y, 1, 1])
        end
      end
    end
    nil
  end

  def connectors_touching_room room
    x = room[0]      
    y = room[1]      
    width = room[2] 
    height = room[3]
    expanded_room = [x - 1, y - 1, width + 2, height + 2]
    main_connectors = connect.connectors.select { |x, y| touches_main_region?(x, y) }
    main_connectors.select{|c_x, c_y| expanded_room.intersect_rect?([c_x, c_y, 1, 1])}
  end


  def touches_main_region? x, y
    adjacent_points(x, y).each do |adj_x, adj_y|
      return true if main_region?(adj_x, adj_y)
    end
    false
  end
  
  def main_region? x, y
    return true if connect.first_room.intersect_rect?([x, y, 1, 1])

    connect.main_region.include?([x, y])
  end
  

  def translate_point x, y, direction
    if direction == :left
      x -= 1
    elsif direction == :up
      y += 1
    elsif direction == :right
      x += 1
    elsif direction == :down
      y -= 1
    end
    [x, y, direction]
  end

  def random_valid_directions x, y
    valid_directions(x, y).shuffle
  end
  
  def valid_directions x, y
    directions = []
    unless x == 0
      directions << :left
    end
    unless x == state.grid_size - 1
      directions << :right
    end
    unless y == 0
      directions << :down
    end
    unless y == state.grid_size - 1
      directions << :up
    end
    directions
  end

  def maze_starting_point? x, y
    empty_point?(x, y) && !point_touches_maze?(x, y) && !point_touches_room?(x, y)
  end

  def point_touches_maze? x, y
    neighbor_points(x, y).each do |neighbor_x, neighbor_y|
      return true if maze?(neighbor_x, neighbor_y)
    end
    false
  end

  def maze? x, y
    maze.points.include?([x, y])
  end

  def neighbor_points x, y
    adjacent_points(x, y) + diagonal_points(x, y)
  end

  def adjacent_points x, y
    points = []
    unless x == 0
      points << [x - 1, y]
    end
    unless x == grid_size - 1
      points << [x + 1, y]
    end
    unless y == 0
      points << [x, y - 1]
    end
    unless y == grid_size - 1
      points << [x, y + 1]
    end
    points
  end
  
  def diagonal_points x, y
    points = []
    unless x == 0 or y == 0
      points << [x - 1, y - 1]
    end
    unless x == grid_size - 1 or y == 0
      points << [x + 1, y - 1]
    end
    unless x == grid_size - 1 or y == grid_size - 1
      points << [x + 1, y + 1]
    end
    unless x == 0 or y == grid_size - 1
      points << [x - 1, y + 1]
    end
    points
  end
  

  # Removes all maze dead ends
  def calc_remove
    return unless state.game_state == :remove
    
    if remove.dead_ends.empty?
      calc_dead_ends # Calc initial dead ends
    end

    remove_dead_ends # Remove dead ends while finding new ones

    if remove.dead_ends.empty?
      state.game_state = :done
    end
  end

  def calc_dead_ends
    remove.dead_ends = maze.points.select { |x, y| dead_end?(x, y) }
  end

  def dead_end? x, y
    return false unless maze?(x, y)
    adjacent_points(x, y).reject { |a_x, a_y| empty_point?(a_x, a_y) }.length <= 1
  end

  def remove_dead_ends
    dead_ends = remove.dead_ends.clone
    remove.dead_ends = []

    dead_ends.each do |x, y|
      if dead_end?(x, y)
        # Deletes dead end
        connect.main_region.delete([x, y])
        maze.points.delete([x, y])

        # New dead ends must be adjacent to old dead ends
        adjacent_points(x, y).each {|point| remove.dead_ends << point }
      end
    end
  end

  def dungeon_background_color
    [170, 170, 170]
  end
  
  def random_color
    [rand(256), rand(256), rand(256)]
  end

  def room_color
    [246, 156, 196]
  end

  def maze_color
    [253, 253, 149]
  end

  def connect_color
    [119, 153, 204]
  end

  def room
    state.room
  end

  def maze
    state.maze
  end

  def connect
    state.connect
  end

  def remove
    state.remove
  end
  
  def grid_size
    state.grid_size
  end

  def cell_size
    state.cell_size
  end
end


def tick args
  if args.inputs.keyboard.key_down.r
    args.gtk.reset
    reset
    return
  end

  $dungeon_generator ||= DungeonGenerator.new
  $dungeon_generator.args = args
  $dungeon_generator.tick
end

def reset 
  $dungeon_generator = nil
end
