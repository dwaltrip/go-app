class Board < ActiveRecord::Base
  belongs_to :game, inverse_of: :boards, touch: true

  DB_STONE_MAPPINGS = {
    :black => GoApp::BLACK_STONE,
    :white => GoApp::WHITE_STONE
  }

  def self.initial_board(game)
    board = new(
      game: game,
      move_num: 0,
      captured_stones: 0
    )

    # if handicap, create initial board with pre-placed handicap stones, else leave blank
    if game.handicap
      logger.warn '-- inside Board.initial_board -- HANDICAP NOT YET IMPLEMENTED'
    end

    board.save
  end

  def pos_nums_and_tile_states(pos_list=nil)
    if pos_list == nil
      Array.new(self.game.board_size**2) { |n| [n, state(n)] }
    else
      logger.info "-- board.pos_nums_and_tile_states -- pos_list: #{pos_list.inspect}"
      pos_list.to_a.sort.map { |n| [n, state(n)] }
    end
  end

  def tiles
    Array.new(self.game.board_size**2) { |n| state(n) }
  end

  # this should be implemented better. we should have smart defaults for attributes,
  # and only change releveant ones
  def replicate_and_update(pos, captured_count, color)
    new_board = self.dup
    new_board.game = self.game
    new_board.move_num = self.move_num + 1
    new_board.pos = pos
    new_board.add_stone(pos, color)
    new_board.captured_stones = captured_count
    new_board.ko = nil
    new_board.pass = false

    new_board
  end

  def add_stone(pos, color)
    set_state(pos, DB_STONE_MAPPINGS[color])
  end

  def remove_stones(new_captures)
    logger.info "-- Board.remove_stones: new_captures= #{new_captures.inspect}"

    if new_captures
      new_captures.each { |pos| set_state(pos, GoApp::EMPTY_TILE) }
    end

    self.captured_stones += new_captures.size
  end

  def state(tile_pos)
    self["pos_#{tile_pos}"]
  end

  def set_state(tile_pos, new_state)
    self["pos_#{tile_pos}"] = new_state
  end

  def time_left
    self.seconds_remaining
  end

  def stone_lists
    black_stones, white_stones = [], []
    (0...self.game.board_size**2).each do |n|
      val = state(n)
      if val == GoApp::BLACK_STONE
        black_stones << n
      elsif val == GoApp::WHITE_STONE
        white_stones << n
      end
    end
    [black_stones, white_stones]
  end

  def black_stones
    black_stones, white_stones = self.stone_lists
    black_stones
  end

  def white_stones
    black_stones, white_stones = self.stone_lists
    white_stones
  end

  def inspect
    regexp = /\Apos_[\d]+\Z/ # don't print out the 361 attributes storing tile state
    inspections =
      if @attributes
        self.class.column_names.collect do |name|
          "#{name}: #{attribute_for_inspect(name)}" if (has_attribute?(name) && (name !~ regexp))
        end
      else
        ["not initialized"]
      end
    "#<#{self.class} #{inspections.compact.join(", ")}>"
  end

end
