require 'spec_helper'

# for game actions
INVALID_STATUSES = [:OPEN, :FINISHED, :END_GAME_SCORING]
INVALID_STATUSES_FOR_UNDO = [:OPEN, :FINISHED]

describe Game do

  context "validations" do
    it "has a description with no more than 40 characters" do
      game = Game.new
      game.should be_valid
      game.description = "super duper more than 40 character long descriptive piece of text"
      game.should_not be_valid
    end
  end

  describe ".move_num" do
    it "returns correct values for a new game and incremets by 1 after each move" do
      game = create(:new_active_game)
      Board.initial_board(game)

      expect(game.move_num).to eq(0)
      game.new_move(0, game.active_player)
      expect(game.move_num).to eq(1)
    end
  end

  describe ".new_move" do
    it "creates new board with correct attributes" do
      game = create(:new_active_game)
      Board.initial_board(game)

      new_move_pos = 10
      prev_board = game.boards[-1]
      expect(prev_board.state(new_move_pos)).to be_nil

      game.new_move(10, game.black_player)
      new_board = game.boards[-1]

      expect(prev_board.id).not_to eq(new_board.id)
      expect(new_board.pos).to eq(new_move_pos)
      expect(new_board.state(new_move_pos)).to eq(GoApp::BLACK_STONE)
      expect(new_board.ko).to be_nil
      expect(new_board.pass).to be_false
      expect(new_board.captured_stones).to eq(0)
    end

    it "captures stones properly" do
      #  representation of board for this example:
      #  |_|_|_|_|
      #  |_|b|b|_|
      #  |b|w|w|_|
      #  |_|b|b|_|
      size = 4
      stones = { black: [size + 1, size + 2, 2*size, 3*size + 1, 3*size + 2], white: [2*size + 1, 2*size + 2] }
      killing_move = 2*size + 3

      game = create(:new_active_game, board_size: size)
      Board.initial_board(game)
      board = game.boards[-1]
      stones[:black].each { |stone_pos| board.add_stone(stone_pos, :black) }
      stones[:white].each { |stone_pos| board.add_stone(stone_pos, :white) }
      board.save

      expect(game.boards[-1].captured_stones).to eq(0)

      game.new_move(killing_move, game.black_player)
      new_board = game.boards[-1]

      expect(new_board.captured_stones).to eq(stones[:white].length)
      stones[:white].each do |stone_pos|
        expect(new_board.state(stone_pos)).to eq(GoApp::EMPTY_TILE)
      end
    end

    INVALID_STATUSES.each do |invalid_status|
      it "doesn't update or create, and returns false if game status is '#{invalid_status}'" do
        game = create(:new_active_game)
        game.update_attribute(:status, Game.const_get(invalid_status))

        Board.initial_board(game)
        prev_board = game.boards[-1]

        expect(game.new_move(5, game.black_player)).to be_false
        expect(game.boards[-1].id).to eq(prev_board.id)
      end
    end

    it "doesn't update or create, and returns false if non-active player is current user" do
      game = create(:new_active_game)
      Board.initial_board(game)
      prev_board = game.boards[-1]

      # black goes first by default
      expect(game.new_move(5, game.white_player)).to be_false
      expect(game.boards[-1].id).to eq(prev_board.id)
    end

    it "doesn't update or create, and returns false if other invalid user is current user" do
      game = create(:new_active_game)
      Board.initial_board(game)
      other_user = Player.new(create(:user), game)
      prev_board = game.boards[-1]

      expect(game.new_move(5, other_user)).to be_false
      expect(game.boards[-1].id).to eq(prev_board.id)
    end
  end


  describe ".white_capture_count, .black_capture_count" do
    it "capture counts are properly stored across moves" do
      # |_|w|_|_|*|
      # |w|b|*|_|_|
      # |_|w|_|b|_|
      # |_|_|b|w|*|
      # |*|_|_|b|_|
      size = 5
      stones_to_kill = { black: size + 1, white: (size * (size - 1)) - 2 }
      game = game_with_stones_to_capture(size, stones_to_kill, killing_move: :right_side)
      black_player, white_player = game.black_player, game.white_player

      # no captures yet
      expect(game.captured_count(:white)).to eq(0)
      expect(game.captured_count(:black)).to eq(0)

      # black goes first in regular games
      # killing moves are to the right of the doomed stones (hence the pos + 1)
      game.new_move(stones_to_kill[:white] + 1, black_player)
      expect(game.white_capture_count).to eq(0)
      expect(game.black_capture_count).to eq(1)

      game.new_move(stones_to_kill[:black] + 1, white_player)
      expect(game.white_capture_count).to eq(1)
      expect(game.black_capture_count).to eq(1)

      # play some other boring moves, and verify capture stone counts are still correct
      game.new_move(size * (size - 1), black_player) # out of the way in bottom most left corner
      expect(game.white_capture_count).to eq(1)
      expect(game.black_capture_count).to eq(1)

      game.new_move(size - 1, white_player) # out of the way in the top most right corner
      expect(game.white_capture_count).to eq(1)
      expect(game.black_capture_count).to eq(1)
    end
  end


  describe ".pass" do
    it "creates another board with identical state to the previous board" do
      size = 5
      game = create(:new_active_game, board_size: size)
      Board.initial_board(game)
      play_some_moves(game)

      move_num_before = game.move_num
      board_before = game.boards.to_a[-1]
      game.pass(game.active_player)

      expect(move_num_before + 1).to eq(game.move_num)
      black_stone_count = 0
      white_stone_count = 0
      (size**2).times do |pos|
        previous_state = board_before.state(pos)
        black_stone_count += 1 if previous_state == GoApp::BLACK_STONE
        white_stone_count += 1 if previous_state == GoApp::WHITE_STONE

        expect(previous_state).to eq(game.active_board.state(pos))
      end

      expect(black_stone_count).to eq(2)
      expect(white_stone_count).to eq(2)
    end

    it "sets pass boolean to true and pos to nil for the new board" do
      game = create(:new_active_game)
      Board.initial_board(game)
      game.new_move(1, game.black_player)

      expect(game.active_board.pass).to be_false
      expect(game.active_board.pos).not_to be_nil

      game.pass(game.active_player)

      expect(game.active_board.pass).to be_true
      expect(game.active_board.ko).to be_nil
      expect(game.active_board.pos).to be_nil
    end

    it "sets game status to 'END_GAME_SCORING' after two passes in a row" do
      game = create(:new_active_game)
      Board.initial_board(game)

      2.times do
        expect(game.status).to eq(Game::ACTIVE)
        game.pass(game.active_player)
      end

      expect(game.status).to eq(Game::END_GAME_SCORING)
    end

    INVALID_STATUSES.each do |invalid_status|
      it "doesn't update or create, and returns false if game status is '#{invalid_status}'" do
        game = create(:new_active_game)
        game.update_attribute(:status, Game.const_get(invalid_status))

        Board.initial_board(game)
        prev_board = game.boards[-1]

        expect(game.pass(game.black_player)).to be_false
        expect(game.boards[-1].id).to eq(prev_board.id)
      end
    end

    it "doesn't update or create, and returns false if non-active player is current user" do
      game = create(:new_active_game)
      Board.initial_board(game)
      prev_board = game.boards[-1]

      # black goes first by default
      expect(game.pass(game.white_player)).to be_false
      expect(game.boards[-1].id).to eq(prev_board.id)
    end

    it "doesn't update or create, and returns false if other invalid user is current user" do
      game = create(:new_active_game)
      Board.initial_board(game)
      other_user = Player.new(create(:user), game)
      prev_board = game.boards[-1]

      expect(game.pass(other_user)).to be_false
      expect(game.boards[-1].id).to eq(prev_board.id)
    end

    it "preserves correct captured stone count" do
      # |_|w|_|_|_|
      # |w|b|*|_|_|
      # |_|w|_|b|_|
      # |_|_|b|w|*|
      # |_|_|_|b|_|
      size = 5
      # black: 1 diagonal tile away from top left corner. white: 1 diagonal away from bottom rigtht corner
      stones_to_kill = { black: size + 1, white: (size * (size - 1)) - 2 }
      game = game_with_stones_to_capture(size, stones_to_kill, killing_move: :right_side)
      black_player, white_player = game.black_player, game.white_player

      # killing move on right side --> position of doomed stone + 1
      # black captures a stone, white passes, then we verify capture counts
      game.new_move(stones_to_kill[:white] + 1, black_player)
      game.pass(white_player)
      expect(game.white_capture_count).to eq(0)
      expect(game.black_capture_count).to eq(1)

      # irrelevant, no impact move (bottom left corner) by black to maintain the ordering of turns
      game.new_move(size * (size - 1), black_player)

      # white captures a stone, black passes, then we verify capture counts
      game.new_move(stones_to_kill[:black] + 1, white_player)
      game.pass(black_player)
      expect(game.white_capture_count).to eq(1)
      expect(game.black_capture_count).to eq(1)
    end
  end


  describe ".undo"  do
    def setup_for_undo
      game = create(:new_active_game)
      Board.initial_board(game)

      game.new_move(3, game.black_player)
      return game
    end

    it "deletes most recent board when inactive player performs undo" do
      game = setup_for_undo
      prev_boards = game.boards.to_a

      game.undo(game.black_player)

      expect(game.boards.count).to eq(prev_boards.length - 1)
      expect(prev_boards[-1]).to be_destroyed
      expect(prev_boards[-1].id).not_to eq(game.boards[-1].id)
      expect(prev_boards[-2].id).to eq(game.boards[-1].id)
    end

    it "deletes the last two boards when active player peforms undo" do
      game = setup_for_undo
      game.new_move(13, game.white_player)
      prev_boards = game.boards.to_a

      # it is black's turn, so undo-ing last black move will delete two boards
      game.undo(game.black_player)

      expect(game.boards.count).to eq(prev_boards.length - 2)
      expect(prev_boards[-1]).to be_destroyed
      expect(prev_boards[-2]).to be_destroyed
      expect(prev_boards[-1].id).not_to eq(game.boards[-1].id)
      expect(prev_boards[-2].id).not_to eq(game.boards[-1].id)
      expect(prev_boards[-3].id).to eq(game.boards[-1].id)
    end

    it "does not perform updates/deletions and returns false if player hasn't made any moves yet" do
      game = setup_for_undo
      prev_boards = game.boards.to_a

      # white player hasn't played a move yet
      expect(game.undo(game.white_player)).to be_false

      expect(game.boards[-1].id).to eq(prev_boards[-1].id)
      expect(game.boards.length).to eq(prev_boards.length)
      expect(prev_boards[-1]).to be_persisted
    end

    it "does not perform updates/deletions and returns false if current user is not a player in this game" do
      game = setup_for_undo
      prev_boards = game.boards.to_a
      invalid_player = Player.new(create(:user), game)

      # white player hasn't played a move yet
      expect(game.undo(invalid_player)).to be_false

      expect(game.boards[-1].id).to eq(prev_boards[-1].id)
      expect(game.boards.length).to eq(prev_boards.length)
      expect(prev_boards[-1]).to be_persisted
    end

    INVALID_STATUSES_FOR_UNDO.each do |invalid_status|
      it "doesn't perform updates/deletions, and returns false if game status is '#{invalid_status}'" do
        game = setup_for_undo
        prev_boards = game.boards.to_a
        game.update_attribute(:status, Game.const_get(invalid_status))

        expect(game.undo(game.black_player)).to be_false

        expect(game.boards[-1].id).to eq(prev_boards[-1].id)
        expect(game.boards.length).to eq(prev_boards.length)
        expect(prev_boards[-1]).to be_persisted
      end
    end

    #it "it returns game to 'ACTIVE' status if current status is 'END_GAME_SCORING'"

    it "preserves correct captured stone count" do
      # |_|w|_|_|_|
      # |w|b|*|_|_|
      # |_|w|_|b|_|
      # |_|_|b|w|*|
      # |_|_|_|b|_|
      size = 5
      # black: 1 diagonal tile away from top left corner. white: 1 diagonal away from bottom rigtht corner
      stones_to_kill = { black: size + 1, white: (size * (size - 1)) - 2 }
      game = game_with_stones_to_capture(size, stones_to_kill, killing_move: :right_side)
      black_player, white_player = game.black_player, game.white_player

      # killing move on right side --> position of doomed stone + 1
      game.new_move(stones_to_kill[:white] + 1, black_player)
      game.new_move(stones_to_kill[:black] + 1, white_player)

      expect(game.white_capture_count).to eq(1)
      expect(game.black_capture_count).to eq(1)

      game.undo(white_player)
      expect(game.white_capture_count).to eq(0)
      expect(game.black_capture_count).to eq(1)

      game.undo(black_player)
      expect(game.white_capture_count).to eq(0)
      expect(game.black_capture_count).to eq(0)
    end
  end

end

# this could be a little faster if it simply modifies the state of the initial board
def play_some_moves(game)
  first_player = game.active_player
  second_player = game.inactive_player
  size = game.board_size
  moves = [size + 1, 2*size - 2, 3*size + 1, 4*size - 2]

  i = 0
  2.times do
    [first_player, second_player].each do |player|
      game.new_move(moves[i], player)
      i += 1
    end
  end
end

def game_with_stones_to_capture(size, stones_to_kill, options={})
  sides = { top_side: -size, bottom_side: size, right_side: 1, left_side: -1 }
  game = create(:new_active_game, board_size: size)
  Board.initial_board(game)

  opponent = { black: :white, white: :black }
  surrounding_tiles = {}
  # surround each stone_to_kill on left, top, and bottom sides, so that we can kill in one move (right side)
  stones_to_kill.each do |color, pos|
    # opponent hash is used because each color is surrounding the doomed stone of the opposite color
    surrounding_tiles[opponent[color]] = []
    sides.each do |side, delta|
      surrounding_tiles[opponent[color]] << (pos + delta) unless options[:killing_move] == side
    end
  end

  board = game.boards[-1]
  # mark board with initial stones (artificial setup, will look like comment pictorial above, minus asterisks)
  [:black, :white].each do |color|
    board.add_stone(stones_to_kill[color], color)
    surrounding_tiles[color].each { |pos| board.add_stone(pos, color) }
  end
  board.save

  game
end
