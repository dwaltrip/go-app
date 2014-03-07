class GamesController < ApplicationController
  before_filter :require_login, :except => :index
  before_action :find_game, except: [:index, :new, :create]

  def index
    @open_games = Game.open.order('created_at DESC')
  end

  def new
    @game = Game.new
  end

  def create
    # todo: move defaults somewhere more logical
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
    if @game.open? && current_user != @game.creator
      @game.pregame_setup(current_user)
      respond_to { |format| format.json }
    else
      render nothing: true
    end
  end

  def show
    if @game.end_game_scoring?
      @just_entered_scoring_phase = true

      tiles_to_render = @game.tiles_to_render_during_scoring(overwrite_data_store=true)
      @tiles = decorated_tiles(current_user, tiles_to_render)
      @json_scoring_data = json_scoring_updates(reset_content_type_to_html=true)
    end

    @connection_id = generate_token
    @tiles = decorated_tiles(current_user, @game.tiles_to_render(current_user))
  end

  def new_move
    update_helper(@game.new_move(params[:new_move].to_i, current_user))
  end

  def pass_turn
    if @game.pass(current_user)
      if @game.active?
        update_helper(true)
      elsif @game.end_game_scoring?
        @just_entered_scoring_phase = true
        scoring_helper(true)
      end
    else
      render nothing: true
    end
  end

  def undo_turn
    valid_undo_approval = (params[:undo_status] == "approved" && decrypt(params[:move_num]) == @game.move_num)
    undo_requester = @game.opponent(current_user)
    update_helper(valid_undo_approval && @game.undo(undo_requester))
  end

  def request_undo
    if @game.active? && @game.has_player?(current_user)
      # the move_num value encrypted here is verified in games#undo_turn if the undo request is approved
      approval_form = render_to_string(partial: 'undo_approval_form', locals: { move_num: encrypt(@game.move_num) })
      send_realtime_data(event_name: "undo-request", payload: { approval_form: approval_form })
    end
    render nothing: true
  end

  def mark_stones
    scoring_helper(@game.mark_stone(params[:stone_pos].to_i, params[:mark_as]))
  end

  def done_scoring
    if @game.update_done_scoring_flags(current_user)
      if @game.finished?
        # would be nice to not have to parse this (look into RABL, which allows skipping the hash to json string step)
        data = JSON.parse(render_to_string(template: 'games/finalize_game', formats: [:json]))
        send_realtime_data(event_name: "game-finished", payload: data)
      end

      respond_to { |format| format.json { render 'games/finalize_game' } }
    else
      render nothing: true
    end
  end

  def resign
    if @game.resign(current_user)
      data = JSON.parse(render_to_string(template: 'games/finalize_game', formats: [:json]))
      send_realtime_data(event_name: "game-finished", payload: data)
      respond_to { |format| format.json { render 'games/finalize_game' } }
    else
      render nothing: true
    end
  end

  private

  def update_helper(update_action_was_successful)
    pretty_log_game_info("-- games#update_helper -- ")

    if update_action_was_successful
      @tiles = decorated_tiles(current_user, @game.tiles_to_render(current_user, updates_only=true))

      opponent = @game.opponent(current_user)
      opponent_data = JSON.parse(render_to_string(template: 'games/update', formats: [:json], locals: {
        tiles: decorated_tiles(opponent, @game.tiles_to_render(opponent, updates_only=true)),
        user: opponent
      }))

      logger.info "-- games#update_helper -- opponent_data: #{opponent_data.inspect}"
      send_realtime_data(event_name: "game-update", payload: opponent_data)

      respond_to do |format|
        format.json { render 'games/update', locals: { tiles: @tiles, user: current_user } }
      end
    else
      render nothing: true
    end
  end

  def scoring_helper(scoring_update_was_successful)
    if scoring_update_was_successful
      overwrite_data_store = (true if @just_entered_scoring_phase) || false
      @tiles = decorated_tiles(current_user, @game.tiles_to_render_during_scoring(overwrite_data_store))

      send_realtime_data(event_name: "scoring-update", payload: JSON.parse(json_scoring_updates))
      respond_to { |format| format.json { render 'games/scoring' } }
    else
      render nothing: true
    end
  end

  def json_scoring_updates(reset_content_type_to_html=false)
    json = render_to_string(template: 'games/scoring', formats: [:json])
    response.headers["Content-Type"] = 'text/html' if reset_content_type_to_html
    json
  end


  def decorated_tiles(player, tiles_to_render)
    logger.info "-- games#decorated_tiles -- #{player.username} as #{@game.player_color(player)}"
    viewer = @game.viewer(player)
    last_pos = @game.active_board.pos

    scoring_display_mode = @game.end_game_scoring? || @game.finished?
    ko_pos = @game.get_ko_position(player) unless scoring_display_mode
    invalid_moves = @game.invalid_moves unless scoring_display_mode

    tiles_to_render.map do |pos, tile_state|
      new_tile = TilePresenter.new(
        board_size: @game.board_size,
        state: tile_state,
        pos: pos,
        viewer: viewer,
        game_status: @game.status,
        invalid_moves: invalid_moves
      )

      new_tile.territory_status = @game.territory_status(pos) if scoring_display_mode
      new_tile.is_dead_stone = true if scoring_display_mode && @game.has_dead_stone?(pos)

      new_tile.is_most_recent_move = true if pos == last_pos
      new_tile.is_ko = true if pos == ko_pos
      new_tile
    end
  end


  def send_realtime_data(event_data)
    event_data[:connection_id_to_skip] = params[:connection_id]
    event_data[:room_id] = @room_id
    logger.info "-- games#send_realtime_data -- event_data: #{event_data.inspect}"
    $redis.publish "game-events", JSON.dump(event_data)
  end

  def find_game
    begin
      @game = Game.find(params[:id])
      @room_id = "game-#{@game.id}"
      pretty_log_game_info('----')
    rescue ActiveRecord::RecordNotFound
      flash[:alert] = "The requested page does not exist."
      redirect_to games_path
    end
  end

  def pretty_log_game_info(prefix='')
    inspect_prefix = @game.inspect.split[0]
    log_msg1 = "game: #{inspect_prefix} object_id: #{@game.object_id},#{@game.inspect[(inspect_prefix.length)..-1]}"
    log_msg2 = "game.active_board: #{@game.active_board.inspect}"
    logger.info "#{prefix} #{log_msg1}"
    logger.info "#{prefix} #{log_msg2}"
  end

end
