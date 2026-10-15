### Grid-based panel for selecting specific options
class_name OptionPanel extends FoldableContainer

### Just a consistent tile for the grid
class OptionTile extends TextureButton:
  signal chosen(option: Option)

  var option: Option

  func _init(tile_option: Option) -> void:
    option = tile_option

    if option.image is Texture2D:
      var image := option.image.get_image()
      var bounds := Rect2i(Vector2i.ZERO, image.get_size())
      var rect := image.get_used_rect().grow(16).intersection(bounds)
      var cropped := AtlasTexture.new()
      cropped.atlas = option.image
      cropped.region = rect
      texture_normal = cropped
    else:
      texture_normal = option.image

    # self_modulate tints only this tile's own picture,
    # which keeps modulate free, e.g. for a hover effect.
    self_modulate = option.tint
    ignore_texture_size = true
    stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    custom_minimum_size = Vector2(180, 180)
    tooltip_text = option.label

    pressed.connect(func() -> void: chosen.emit(option))

  func _make_custom_tooltip(_for_text: String) -> Object:
    var label := Label.new()
    label.text = option.label
    label.add_theme_font_size_override("font_size", 32)
    return label


### A signal that emits the information of any selected option
signal option_selected(option: Option)

var grid := GridContainer.new()

func _init() -> void:
  grid.columns = 5
  grid.add_theme_constant_override("h_separation", 16)
  grid.add_theme_constant_override("v_separation", 16)
  add_theme_font_size_override("font_size", 32)

  mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

  var style := StyleBoxFlat.new()
  style.bg_color = Color("dddddd")
  style.set_content_margin_all(32)
  add_theme_stylebox_override("panel", style)

  add_child(grid)

### Sets the options for the panel, clearing out any existing tiles first
func set_options(options: Array[Option]) -> void:
  for child in grid.get_children():
    grid.remove_child(child)
    child.queue_free()

  for option in options:
    var tile := OptionTile.new(option)
    tile.chosen.connect(_on_tile_chosen)
    grid.add_child(tile)

func _on_tile_chosen(option: Option) -> void:
  option_selected.emit(option)
