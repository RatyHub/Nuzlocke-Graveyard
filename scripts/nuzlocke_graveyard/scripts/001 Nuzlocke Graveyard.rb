# Nuzlocke Graveyard
# https://github.com/RatyHub/Nuzlocke-Graveyard
#
# Nuzlocke Graveyard is a PSDK plugin that adds an interface for viewing
# the Nuzlocke graveyard of the current save file.

module NuzlockeGraveyard
  VERSION = '1.0.0.0'
  VISIBLE_COUNT = 6

  TEXTS = {
    en: {
      empty: 'No Pokemon in the graveyard.'
    },
    fr: {
      empty: 'Aucun Pokemon dans le cimetière.'
    }
  }.freeze

  class << self
    # Return a localized plugin string. Unsupported languages fall back to English.
    # @param key [Symbol]
    # @return [String]
    def text(key)
      language = defined?($options) && $options ? $options.language.to_s.downcase.to_sym : :en
      dictionary = TEXTS.fetch(language, TEXTS[:en])
      return dictionary.fetch(key, TEXTS[:en].fetch(key))
    end

    # Return the native PSDK Nuzlocke object.
    # @return [PFM::Nuzlocke, nil]
    def nuzlocke
      return nil unless PFM.respond_to?(:game_state)

      PFM.game_state&.nuzlocke
    end

    # Return the native graveyard without mutating it.
    # Entries are displayed from newest to oldest, based on native array order.
    # @return [Array<PFM::Pokemon>]
    def graveyard
      Array(nuzlocke&.graveyard).compact.reverse
    end

  end
end

module GamePlay
  # Read-only scene presenting the native PSDK Nuzlocke graveyard.
  # Its layout deliberately reuses the Party Menu components one for one.
  class NuzlockeGraveyard < BaseCleanUpdate::FrameBalanced
    SELECTOR_RECTS = [[0, 0, 132, 53], [0, 64, 132, 53]].freeze

    def initialize
      super()
      @entries = ::NuzlockeGraveyard.graveyard
      @index = 0
      @top_row = 0
      @counter = 0
      @scrollbar_dragging = false
      Mouse.wheel = 0
    end

    def update_inputs
      return action_a if Input.trigger?(:A)
      return action_b if Input.trigger?(:B)
      return move_selector(:down) if Input.trigger?(:DOWN)
      return move_selector(:up) if Input.trigger?(:UP)
      return move_selector(:left) if Input.trigger?(:LEFT)
      return move_selector(:right) if Input.trigger?(:RIGHT)

      true
    end

    def update_mouse(moved)
      update_mouse_ctrl_buttons(@base_ui.ctrl, [:action_a, nil, nil, :action_b])
      return true if update_mouse_wheel
      return true if update_mouse_scrollbar
      return true unless moved || Mouse.trigger?(:left)

      @team_buttons.each_with_index do |button, local_index|
        next unless button.simple_mouse_in?

        index = visible_start + local_index
        select_index(index) if @index != index
        action_a if Mouse.trigger?(:left)
        break
      end
      true
    end

    def update_graphics
      update_selector
      @base_ui.update_background_animation
      @team_buttons.each(&:update_graphics)
      true
    end
    alias update_during_process update_graphics

    private

    def create_graphics
      raise LiteRGSS::DisplayWindow::ClosedWindowError unless Graphics.window

      create_viewport
      create_base_ui
      create_team_buttons
      create_frames
      create_selector
      create_scrollbar
      create_empty_text
      refresh_display
      sort_graphics_with_selector_on_top
    end

    def create_base_ui
      # Same text bank as Party_Menu: ": infos" and ": retour", localized by PSDK.
      @base_ui = UI::GenericBase.new(@viewport, [ext_text(9000, 14), nil, nil, ext_text(9000, 17)])
    end

    def create_team_buttons
      @team_buttons = visible_entries.each_with_index.map do |pokemon, index|
        button = UI::TeamButton.new(@viewport, index)
        button.x += index.even? ? 4 : -4
        button.y += 24 if index.even?
        button.y -= 2
        button.data = pokemon
        button
      end
    end

    def create_frames
      @black_frame = Sprite.new(@viewport)
      @frame = Sprite.new(@viewport).set_bitmap('nuzlocke_graveyard/frame', :interface)
      @frame.z = 100
    end

    def create_selector
      @selector = Sprite.new(@viewport).set_bitmap('team/Cursors', :interface)
      @selector.src_rect.set(*SELECTOR_RECTS[0])
      @selector.z = 101
    end

    def create_scrollbar
      @scrollbar = UI::Dex::ScrollBar.new(@viewport)
      @scrollbar.z = 102
    end

    def create_empty_text
      @empty_stack = UI::SpriteStack.new(@viewport)
      @empty_text = @empty_stack.add_text(20, 105, 280, 20, ::NuzlockeGraveyard.text(:empty), 1, color: 0)
      @empty_text.z = 10
    end

    def refresh_display
      @empty_text.visible = @entries.empty?
      @selector.visible = !@team_buttons.empty?
      unless @team_buttons.empty?
        @index = @index.clamp(0, @entries.size - 1)
        update_selector_coordinates
      end
      update_scrollbar
    end

    def refresh_team_buttons
      @team_buttons.each(&:dispose)
      create_team_buttons
      refresh_display
      sort_graphics_with_selector_on_top
    end

    def sort_graphics_with_selector_on_top
      highest_button_z = @team_buttons.flat_map(&:stack).map(&:z).max || 0
      @selector.z = [@selector.z, highest_button_z + 1].max
      @viewport.sort_z
      Graphics.sort_z
    end

    def visible_entries
      @entries[visible_start, ::NuzlockeGraveyard::VISIBLE_COUNT] || []
    end

    def select_index(index)
      return false unless index.between?(0, @entries.size - 1)

      @index = index
      play_cursor_se
      update_visible_window
      true
    end

    def move_selector(direction)
      return play_buzzer_se if @team_buttons.empty?

      previous_index = @index
      party_size = @entries.size
      case direction
      when :down
        next_index = @index + 2
        next_index = @index % 2 if next_index >= party_size
        @index = next_index
      when :up
        next_index = @index - 2
        if next_index.negative?
          next_index = party_size - 1
          next_index -= 1 if next_index % 2 != @index % 2
        end
        @index = next_index
      when :left
        @index = (@index - 1) % party_size
      when :right
        @index = (@index + 1) % party_size
      end
      play_cursor_se if @index != previous_index
      update_visible_window
      true
    end

    def update_selector_coordinates
      button = @team_buttons[@index - visible_start]
      @selector.set_position(button.x + 3, button.y + 3) if button
    end

    def update_visible_window
      selected_row = @index / 2
      new_top_row = @top_row
      new_top_row = selected_row if selected_row < @top_row
      new_top_row = selected_row - 2 if selected_row > @top_row + 2
      new_top_row = new_top_row.clamp(0, max_top_row)
      if new_top_row != @top_row
        @top_row = new_top_row
        refresh_team_buttons
      else
        update_selector_coordinates
        update_scrollbar
      end
    end

    def visible_start
      @top_row * 2
    end

    def total_rows
      (@entries.size + 1) / 2
    end

    def max_top_row
      [total_rows - 3, 0].max
    end

    def update_scrollbar
      @scrollbar.visible = @entries.size > ::NuzlockeGraveyard::VISIBLE_COUNT
      return unless @scrollbar.visible

      @scrollbar.max_index = total_rows - 1
      @scrollbar.index = @index / 2
    end

    def update_mouse_scrollbar
      return false unless @scrollbar.visible

      @scrollbar_dragging = true if Mouse.trigger?(:LEFT) && @scrollbar.simple_mouse_in?
      return false unless @scrollbar_dragging
      return @scrollbar_dragging = false unless Mouse.press?(:LEFT)

      row = @scrollbar.drag_mouse_index
      index = row * 2 + (@index % 2)
      index -= 1 if index >= @entries.size
      select_index(index) if index != @index
      true
    end

    def update_mouse_wheel
      return false if Mouse.wheel == 0 || @team_buttons.empty?

      direction = Mouse.wheel.positive? ? :up : :down
      Mouse.wheel = 0
      move_selector(direction)
      true
    end

    def update_selector
      return unless @selector.visible

      @counter += 1
      if @counter == 60
        @selector.src_rect.set(*SELECTOR_RECTS[1])
      elsif @counter >= 120
        @counter = 0
        @selector.src_rect.set(*SELECTOR_RECTS[0])
      end
    end

    def action_a
      pokemon = @entries[@index]
      return play_buzzer_se unless pokemon

      play_decision_se
      GamePlay.open_summary(pokemon, @entries)
      true
    ensure
      $scene = nil unless Graphics.window
    end

    def action_b
      play_cancel_se
      @running = false
      false
    end
  end

  class << self
    # Open the native Nuzlocke graveyard UI.
    def open_nuzlocke_graveyard
      current_scene.call_scene(GamePlay::NuzlockeGraveyard)
    end
  end
end

# Event/console convenience method.
def open_nuzlocke_graveyard
  GamePlay.open_nuzlocke_graveyard
end
