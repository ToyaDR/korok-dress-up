extends Node2D

var config: KorokConfig

@onready var sections: VBoxContainer = $ScrollContainer/VBoxContainer

func load_resources() -> void:
  var text := FileAccess.get_file_as_string("res://config/korok.yaml")
  var result := YAML.parse(text)
  if result.has_error():
    push_error(result.get_error())
    return

  var data = result.get_data()

  build_items(data)

func build_items(data: Dictionary) -> void:
  var checked := ConfigSchema.validate(data)
  if not checked.ok():
    push_error(checked.error)
    return

  var errors := ConfigReferences.check(data)
  if not errors.is_empty():
    for error in errors:
      push_error(error)
    return

  config = KorokConfig.from_dict(data)

## Every combination of values for the given properties, one dictionary for each
## If no properties are provided, it returns one empty combination
static func _value_combinations(properties: Array[KorokConfig.Property]) -> Array[Dictionary]:
  var combinations: Array[Dictionary] = [{}]
  for property in properties:
    var extended: Array[Dictionary] = []
    for combination in combinations:
      for value in property.values:
        var with_value := combination.duplicate()
        with_value[property.name] = value
        extended.append(with_value)

    combinations = extended

  return combinations

func _instances_to_options(instances: Array[KorokConfig.Instance]) -> Array[Option]:
  var options: Array[Option] = []
  for instance in instances:
    # todo this is kinda hacky and would be better to have an enumerated list of variants
    # Anything that goes in another one's slot, e.g. nose, needs a holder to find its picture.
    var holder := config.first_holder_for(instance)
    for values in _value_combinations(instance.choices()):
      var label = instance.label_for(values)
      var picture_values := values.duplicate()
      if holder != null:
        picture_values["holder"] = holder.id

      options.append(Option.from(label, instance.texture_path(picture_values), instance, values))

  return options

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
  load_resources()

  print(JSON.stringify(config.to_dict(), "  "))

  # set up the collapsible sections to render the options
  var body_instances: Array[KorokConfig.Instance] = []
  body_instances.assign(config.bodies.values())
  var body_options := _instances_to_options(body_instances)
  add_section("Body", body_options, "body")

  # TODO: collapse or disable the face, nose and held item panels until a body
  # is picked, and the nose panel until a face is. Then drop this starting body.
  $Korok.set_body(body_options[0].instance, body_options[0].values)

  for category in config.categories.values():
    var instances: Array[KorokConfig.Instance] = []
    instances.assign(category.instances.values())
    add_section(category.label, _instances_to_options(instances), category.name)

  # TODO: rebuild the nose panel when $Korok emits `placed` for a face, so its
  # tiles show that face's nose and not the first face's.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
  pass


func add_section(title: String, options: Array[Option], _source: String) -> void:
  var panel := OptionPanel.new()
  panel.title = title
  panel.set_options(options)
  sections.add_child(panel)

  # TODO: click handlers, so picking a tile updates the doll. Connect
  # panel.option_selected to a function that calls $Korok.set_body for a body
  # option and $Korok.place for anything else, both with option.instance and
  # option.values.
