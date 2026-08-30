# Nuzlocke Graveyard
# https://github.com/RatyHub/Nuzlocke-Graveyard
#
# Nuzlocke Graveyard is a PSDK plugin that adds an interface for viewing
# the Nuzlocke graveyard of the current save file.

module NuzlockeGraveyard
  MODE = :dex
  VISIBLE_COUNT = 6

  TEXTS = {
    en: {
      empty: 'No Pokemon in the graveyard.',
      dead: 'Dead:'
    },
    fr: {
      empty: 'Aucun Pokemon dans le cimetière.',
      dead: 'Morts :'
    }
  }.freeze

  # Minimal view object expected by the native Pokedex UI components.
  DexEntryView = Struct.new(:pokemon, :seen, :caught) do
    def displayed?
      return true
    end
  end

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

module UI
  module NuzlockeGraveyard
    # Pokedex-style button displaying an individual graveyard Pokemon.
    class DexButton < SpriteStack
      SELECTED_X = 147
      UNSELECTED_X = 163
      ROW_HEIGHT = 40

      def initialize(viewport, index)
        super(viewport, SELECTED_X, 62)
        create_sprites
        set_position(index == 0 ? SELECTED_X : UNSELECTED_X, y - ROW_HEIGHT + index * ROW_HEIGHT)
      end

      def selected=(value)
        @shadow.visible = !value
        set_position(value ? SELECTED_X : UNSELECTED_X, y)
      end

      def update_graphics
        @pokemon_icon.update
      end

      private

      def create_sprites
        add_background(button_background_name)
        @pokemon_icon = add_sprite(17, 15, NO_INITIAL_IMAGE, type: PokemonIconSprite)
        add_text(46, 0, 116, 16, :level_pokemon_number, type: SymText, color: 10)
        add_text(35, 16, 72, 16, :given_name, type: SymText, color: 10)
        add_sprite(127, 6, NO_INITIAL_IMAGE, type: GenderSprite)
        with_cache(:pokedex) do
          @shadow = add_foreground('But_ListShadow')
        end
      end

      def button_background_name
        language = defined?($options) && $options ? $options.language.to_s.downcase : 'en'
        suffix = language == 'fr' ? 'fr' : 'en'
        return "nuzlocke_graveyard/button_#{suffix}"
      end
    end

    # Pokedex counter panel reduced to the graveyard total only.
    class DeadCount < SpriteStack
      PANEL_HEIGHT = 26
      LABEL_COUNT_GAP = 4

      def initialize(viewport)
        super(viewport, 0, 152, default_cache: :pokedex)
        background = add_background('WinNum')
        background.src_rect.height = PANEL_HEIGHT
        label = add_text(2, 0, 79, PANEL_HEIGHT, ::NuzlockeGraveyard.text(:dead), color: 10)
        label.bold = true
        @count = add_text(label.real_width + LABEL_COUNT_GAP, 0, 79, PANEL_HEIGHT, '0', 0, color: 10)
      end

      def count=(value)
        @count.text = value.to_i.to_s
      end
    end
  end
end

module GamePlay
  # Read-only scene presenting the native PSDK Nuzlocke graveyard.
  # Its layout can reuse either the Party Menu or Pokedex components.
  class NuzlockeGraveyard < BaseCleanUpdate::FrameBalanced
    SELECTOR_RECTS = [[0, 0, 132, 53], [0, 64, 132, 53]].freeze
    DEX_PAGE_JUMP = 10

    def initialize
      super()
      @entries = ::NuzlockeGraveyard.graveyard
      @mode = ::NuzlockeGraveyard::MODE
      @index = 0
      @top_row = 0
      @counter = 0
      @scrollbar_dragging = false
      Mouse.wheel = 0
    end

    def update_inputs
      return action_a if Input.trigger?(:A)
      return action_b if Input.trigger?(:B)
      return update_dex_inputs if dex_mode?
      return move_selector(:down) if Input.trigger?(:DOWN)
      return move_selector(:up) if Input.trigger?(:UP)
      return move_selector(:left) if Input.trigger?(:LEFT)
      return move_selector(:right) if Input.trigger?(:RIGHT)

      true
    end

    def update_mouse(moved)
      update_mouse_ctrl_buttons(@base_ui.ctrl, [:action_a, nil, nil, :action_b])
      return update_dex_mouse(moved) if dex_mode?
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
      if dex_mode?
        @base_ui.update_background_animation
        @dex_face.update_graphics if @dex_face.visible
        @dex_arrow.update if @dex_arrow.visible
        @dex_buttons.each(&:update_graphics)
      else
        update_selector
        @base_ui.update_background_animation
        @team_buttons.each(&:update_graphics)
      end
      true
    end
    alias update_during_process update_graphics

    private

    def create_graphics
      raise LiteRGSS::DisplayWindow::ClosedWindowError unless Graphics.window

      create_viewport
      create_base_ui
      if dex_mode?
        create_frames
        create_dex_layout
        create_empty_text
        refresh_display
        Graphics.sort_z
      else
        create_team_buttons
        create_frames
        create_selector
        create_scrollbar
        create_empty_text
        refresh_display
        sort_graphics_with_selector_on_top
      end
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

    def create_dex_layout
      @dex_face = UI::Dex::FacePanel.new(@viewport)
      @dex_buttons = Array.new(::NuzlockeGraveyard::VISIBLE_COUNT) do |index|
        UI::NuzlockeGraveyard::DexButton.new(@viewport, index)
      end
      @dex_arrow = UI::Dex::Arrow.new(@viewport)
      @scrollbar = UI::Dex::ScrollBar.new(@viewport)
      @dead_count = UI::NuzlockeGraveyard::DeadCount.new(@viewport)
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
      return refresh_dex_display if dex_mode?

      @empty_text.visible = @entries.empty?
      @selector.visible = !@team_buttons.empty?
      unless @team_buttons.empty?
        @index = @index.clamp(0, @entries.size - 1)
        update_selector_coordinates
      end
      update_scrollbar
    end

    def refresh_dex_display
      empty = @entries.empty?
      @empty_text.visible = empty
      @dex_face.visible = !empty
      @dex_arrow.visible = !empty
      @dead_count.count = @entries.size
      @index = @index.clamp(0, @entries.size - 1) unless empty

      base_index = dex_base_index
      selected_button = nil
      @dex_buttons.each_with_index do |button, slot|
        position = base_index + slot
        pokemon = @entries[position] if position >= 0
        unless pokemon
          button.visible = false
          next
        end

        button.visible = true
        button.selected = position == @index
        button.data = pokemon
        selected_button = button if position == @index
      end

      unless empty
        @dex_face.data = dex_view(@entries[@index])
        @dex_arrow.y = selected_button.y + 11 if selected_button
      end

      @scrollbar.visible = @entries.size > ::NuzlockeGraveyard::VISIBLE_COUNT
      if @scrollbar.visible
        @scrollbar.max_index = @entries.size - 1
        @scrollbar.index = @index
      end
    end

    def dex_view(pokemon)
      return ::NuzlockeGraveyard::DexEntryView.new(pokemon, true, true)
    end

    # Match the native Pokedex list window: the selection stays near the middle
    # whenever enough entries exist around it.
    def dex_base_index
      return -1 if @entries.size < 5
      return -1 if @index < 2

      return @index - 2
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
      dex_mode? ? refresh_dex_display : update_visible_window
      true
    end

    def update_dex_inputs
      return move_dex_selector(1, true) if Input.trigger?(:DOWN)
      return move_dex_selector(-1, true) if Input.trigger?(:UP)
      return move_dex_selector(-DEX_PAGE_JUMP, false) if Input.trigger?(:LEFT)
      return move_dex_selector(DEX_PAGE_JUMP, false) if Input.trigger?(:RIGHT)

      true
    end

    def move_dex_selector(offset, wrap)
      return play_buzzer_se if @entries.empty?

      previous_index = @index
      max_index = @entries.size - 1
      @index = wrap ? (@index + offset) % @entries.size : (@index + offset).clamp(0, max_index)
      play_cursor_se if @index != previous_index
      refresh_dex_display
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

    def update_dex_mouse(moved)
      return true if update_mouse_dex_wheel
      return true if update_mouse_dex_scrollbar
      return true unless moved || Mouse.trigger?(:left)

      base_index = dex_base_index
      @dex_buttons.each_with_index do |button, slot|
        next unless button.visible && button.simple_mouse_in?

        position = base_index + slot
        next unless position.between?(0, @entries.size - 1)

        if Mouse.trigger?(:left)
          position == @index ? action_a : select_index(position)
        end
        break
      end
      true
    end

    def update_mouse_dex_wheel
      return false if Mouse.wheel == 0 || @entries.empty?

      offset = Mouse.wheel.positive? ? -1 : 1
      Mouse.wheel = 0
      move_dex_selector(offset, true)
      true
    end

    def update_mouse_dex_scrollbar
      return false unless @scrollbar.visible

      @scrollbar_dragging = true if Mouse.trigger?(:LEFT) && @scrollbar.simple_mouse_in?
      return false unless @scrollbar_dragging
      unless Mouse.press?(:LEFT)
        @scrollbar_dragging = false
        return false
      end

      index = @scrollbar.drag_mouse_index.clamp(0, @entries.size - 1)
      select_index(index) if index != @index
      true
    end

    def dex_mode?
      return @mode == :dex
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
