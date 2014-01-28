class GamesController < ApplicationController
  before_filter :require_login, :except => :index
  before_action :find_game, only: [:show, :join, :update, :request_undo]

  def index
    @open_games = Game.open.order('created_at DESC')
  end

  def new
    @game = Game.new
  end

  def create
    @game = Game.new(
      description: params[:game][:description],
      creator: current_user,
      board_size: params[:game][:board_size],
      status: Game::OPEN,
      mode: Game::NOT_RANKED,
      time_settings: "none"
    )

    if @game.save
      redirect_to games_path, notice: 'Game was created successfully!'
    elsif
      render "new"
    end
  end

  def join
    if current_user == @game.creator
      redirect_to games_path, notice: "You can't join a game you created!"
      return
    end

    @game.pregame_setup(current_user)
    redirect_to @game
  end

  def show
    pretty_log_game_info("-- games#show -- ")
    @connection_id = generate_token
    render_game_helper
  end

  def update
    pretty_log_game_info("-- games#update, before -- ")

    if params.key?(:new_move) && @game.new_move(params[:new_move].to_i, current_user)
      @played_move = true

    elsif params.key?(:pass) && @game.pass(current_user)
      @played_move = true

    elsif params.key?(:undo)
      undo_data = decrypt_data(params[:undo_data])
      move_num = undo_data[:move_num] if undo_data
      undoing_player = @game.opponent(current_user)

      # current player has approved the undo which the opponent requested
      # verify current move_num matches the move_num when the undo request was made
      if params[:undo] == "approved" && move_num == @game.move_num && @game.undo(undoing_player)
        @undo_performed = true
      end

    else
      logger.warn "-- games#update -- none of the expected data was found in params, which is a bit fishy"
    end
    @update_processed = @played_move || @undo_performed

    if @update_processed
      render_game_helper

      opponent = @game.opponent(current_user)
      opponent_tiles = decorated_tiles(opponent).map do |pos, tile|
        { pos: pos,
          html: tile.to_html(@game.viewer(opponent)) }
      end

      payload = {
        tiles: opponent_tiles,
        invalid_moves: @game.invalid_moves(opponent),
        header_html: render_to_string(partial: 'game_stats', locals: { game: @game })
      }
      # undo button needs to be re-disabled if the only move for a player is undone
      # special case, handled awkwardly here for now
      payload[:disable_undo_button] = true if (@undo_performed && @game.move_num < 2)

      update_data = {
        event_name: "game-update",
        room_id: "game-#{@game.id}",
        connection_id: params[:connection_id],
        payload: payload
      }
      # publish updated info to redis subscriber on Node.js server which then updates opponent client via websockets
      $redis.publish "game-events", ActiveSupport::JSON.encode(update_data)
    end

    pretty_log_game_info("-- games#update, after -- ")
    respond_to do |format|
      format.html { render "show" }
      format.js
    end
  end

  def request_undo
    # the move_num value created here is verified in games#update if an undo request is approved
    undo_data = encrypt_data({ move_num: @game.move_num })
    approval_form_html = render_to_string(partial: 'undo_approval_form', locals: { undo_data: undo_data })

    $redis.publish "game-events", ActiveSupport::JSON.encode({
      event_name: "undo-request",
      room_id: "game-#{@game.id}",
      connection_id: params[:connection_id],
      payload: { undo_approval_form: approval_form_html }
    })

    respond_to { |format| format.js }
  end

  protected

  def render_game_helper
    @tiles = decorated_tiles(current_user)
    logger.info "-- games#render_game_helper -- @game.invalid_moves: #{@game.invalid_moves.inspect}"
  end

  def decorated_tiles(player)
    tiles = (Hash.new if @update_processed) || Array.new(@game.board_size**2)

    viewer = @game.viewer(player)
    @game.tiles_to_render(player, @update_processed).each do |pos, tile_state|
      tiles[pos] = TilePresenter.new(
        board_size: @game.board_size,
        state: tile_state,
        pos: pos,
        viewer: viewer,
        invalid_moves: @game.invalid_moves
      )
    end
    log_msg = "#{player.username.inspect} as #{@game.player_color(player).inspect} -- tiles.length: #{tiles.length}"
    logger.info "-- games#decorated_tiles -- #{log_msg}"

    if @game.active_board.pos && tiles[@game.active_board.pos]
      tiles[@game.active_board.pos].is_most_recent_move = true
    end
    if @game.get_ko_position(player) && tiles[@game.get_ko_position(player)]
      tiles[@game.get_ko_position(player)].is_ko = true
    end

    tiles
  end

  private

  def find_game
    @game = Game.find(params[:id])
  end

  def pretty_log_game_info(prefix)
    inspect_prefix = @game.inspect.split[0] # use this to insert game.object_id into the game.inspect output
    log_msg1 = "game: #{inspect_prefix} object_id: #{@game.object_id},#{@game.inspect[(inspect_prefix.length)..-1]}"
    log_msg2 = "game.active_board: #{@game.active_board.inspect}"
    logger.info "#{prefix}#{log_msg1}"
    logger.info "#{prefix}#{log_msg2}"
  end

end
