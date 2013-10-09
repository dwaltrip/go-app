module BoardHelper
  require 'JSON'
  require 'set'

  class BoardHandler
    BLANK = 0
    BLACK = 1
    WHITE = 2

    def initialize(params = {})
      Rails.logger.info "-- BoardHandler.initialize -- entering"
      Rails.logger.info "-- BoardHandler.initialize -- params: #{params.inspect}"

      @size = params.fetch(:size, 19)

      if params.key?(:json_board)
        @board = JSON.parse(params[:json_board])
      else
        @board = params.fetch(:board, Array.new(@size**2, 0))
      end

      Rails.logger.info "-- BoardHandler.initialize -- exiting"
    end

    def valid_pos?(pos)
      x, y = pos % @size, pos / @size
      1 <= x and x <= @size and 1 <= y and y <= @size
    end

    def get_neighbors(pos, options = {})
      color = options.fetch(:color, nil)

      left = pos - 1
      top = pos - @size
      right = pos + 1
      bot = pos + @size

      # setting to nil if outside boundary of board
      left = nil if pos % @size == 0
      right = nil if (pos + 1) % @size == 0
      bot = nil if bot < 0
      top = nil if top >= @size**2

      [left, top, right, bot].keep_if do |candidate_pos|
        color and candidate_pos ? @board[pos] == color : candidate_pos
      end
    end

    def build_group(coords)
      if valid_pos?(coords)
        group_members = Set.new [pos]
        not_yet_processed = Set.new []
        blanks = Set.new []
        color = @board[pos]

        next_pos = pos
        while not next_pos.nil?  do
          #get_neighbors(pos, color: color).each do |neighbor_pos|
          get_neighbors(pos).each do |neighbor_pos|
            new_member = group_members.add? neighbor_pos if @board[pos] == color
            not_yet_processed.add neighbor_pos if new_member
            blanks.add neighbor_pos if @board[pos] == BLANK
          end
          next_pos = not_yet_processed.first
          not_yet_processed.subtract [next_pos]
        end

         return group_members, blanks.size
      end
      return nil
    end

    #private

    #def yx2i(y, x)
    #  (y - 1) * @size + x
    #end

    #def process_move(position)
    #  # check if any black groups died
    #  neighbors = [[1, 1], [1, -1], [-1. 1], [-1, -1]]

    #  neighbors.each do |dx, dy|
    #    group = build_group 
    #  end

    #  # check if it was ko

    #  # return list of invalid moves
    #end
  end

end