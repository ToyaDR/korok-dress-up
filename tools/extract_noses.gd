# Splits each face's painted nose into its own greyscale layer, and works out
# the tint that turns that layer back into each painted color.
#
# Every face folder has the same face painted five times, once per nose color.
# The pixels that differ between those five files are the nose's colored fill.
# For each face this writes:
#   face.png  the blue version with the nose fill cut out
#   nose.png  the nose fill alone, in greyscale
# It then prints one tint per color. Multiplying nose.png by a color's tint
# reproduces that painted nose, which is how Godot's modulate draws it. The
# tints go in the config under the color property.
#
# Run from the project folder:
#   godot --headless --path . --script tools/extract_noses.gd
extends SceneTree

const FACES_DIR := "res://assets/koroks/faces"
const COLORS: Array[String] = ["blue", "darkbrown", "darkgreen", "lightbrown", "lightgreen"]

# How far apart two versions of a pixel have to be, summed over the channels,
# to count as part of the nose. Lower picks up more of the soft edge.
const DIFFERENCE := 0.01

const FIT_ROUNDS := 20


class Face:
	var name: String
	var images: Array[Image] = []
	var nose_pixels: Array[Vector2i] = []

	## Brightness of each nose pixel, in the same order as nose_pixels.
	var grey: PackedFloat32Array = []


func _init() -> void:
	var faces: Array[Face] = []
	for face_name in DirAccess.get_directories_at(FACES_DIR):
		faces.append(load_face(face_name))

	var tints := fit(faces)
	for face in faces:
		save_face(face)

	print("\ntints, for the color property in the config:")
	for c in COLORS.size():
		print("  %s: \"#%s\"" % [COLORS[c], tints[c].to_html(false)])

	print("\nhow far each tinted nose is from the painted one, average per channel out of 255:")
	for face in faces:
		var errors: Array[String] = []
		for c in COLORS.size():
			errors.append("%s %.1f" % [COLORS[c], average_error(face, c, tints[c]) * 255.0])

		print("  %s: %s" % [face.name, ", ".join(errors)])

	quit(0)


func load_face(face_name: String) -> Face:
	var face := Face.new()
	face.name = face_name
	for color in COLORS:
		var path := ProjectSettings.globalize_path("%s/%s/%s-nose.png" % [FACES_DIR, face_name, color])
		var image := Image.load_from_file(path)
		image.convert(Image.FORMAT_RGBA8)
		face.images.append(image)

	var size := face.images[0].get_size()
	for y in size.y:
		for x in size.x:
			if differs(face.images, x, y):
				face.nose_pixels.append(Vector2i(x, y))

	return face


func differs(images: Array[Image], x: int, y: int) -> bool:
	var first := images[0].get_pixel(x, y)
	for i in range(1, images.size()):
		var other := images[i].get_pixel(x, y)
		var gap := absf(other.r - first.r) + absf(other.g - first.g) + absf(other.b - first.b) + absf(other.a - first.a)
		if gap > DIFFERENCE:
			return true

	return false


## Finds a brightness per nose pixel and a tint per color so that brightness
## times tint is as close as possible to every painted pixel. It alternates:
## best tints for the current brightness, then best brightness for those tints.
## The tints are shared by all faces, since each color is one paint.
func fit(faces: Array[Face]) -> Array[Color]:
	for face in faces:
		face.grey.resize(face.nose_pixels.size())
		for i in face.nose_pixels.size():
			var total := 0.0
			for image in face.images:
				var p := image.get_pixelv(face.nose_pixels[i])
				total += (p.r + p.g + p.b) / 3.0

			face.grey[i] = total / face.images.size()

	var tints: Array[Color] = []
	tints.resize(COLORS.size())
	for round in FIT_ROUNDS:
		for c in COLORS.size():
			tints[c] = best_tint(faces, c)

		for face in faces:
			for i in face.nose_pixels.size():
				face.grey[i] = best_grey(face, i, tints)

	# Make the brightest nose pixel white, and scale the tints to match, so the
	# greyscale layer uses the full range.
	var brightest := 0.0
	for face in faces:
		for value in face.grey:
			brightest = maxf(brightest, value)

	for face in faces:
		for i in face.grey.size():
			face.grey[i] /= brightest

	for c in COLORS.size():
		tints[c] = Color(tints[c].r * brightest, tints[c].g * brightest, tints[c].b * brightest)

	return tints


func best_tint(faces: Array[Face], c: int) -> Color:
	var sums := Vector3.ZERO
	var weight := 0.0
	for face in faces:
		for i in face.nose_pixels.size():
			var p := face.images[c].get_pixelv(face.nose_pixels[i])
			var g := face.grey[i]
			sums += Vector3(p.r, p.g, p.b) * g
			weight += g * g

	sums /= maxf(weight, 0.000001)
	return Color(sums.x, sums.y, sums.z)


func best_grey(face: Face, i: int, tints: Array[Color]) -> float:
	var top := 0.0
	var bottom := 0.0
	for c in COLORS.size():
		var p := face.images[c].get_pixelv(face.nose_pixels[i])
		var t := tints[c]
		top += p.r * t.r + p.g * t.g + p.b * t.b
		bottom += t.r * t.r + t.g * t.g + t.b * t.b

	return clampf(top / maxf(bottom, 0.000001), 0.0, 1.0)


func average_error(face: Face, c: int, tint: Color) -> float:
	var total := 0.0
	for i in face.nose_pixels.size():
		var p := face.images[c].get_pixelv(face.nose_pixels[i])
		var g := face.grey[i]
		total += absf(p.r - g * tint.r) + absf(p.g - g * tint.g) + absf(p.b - g * tint.b)

	return total / maxf(face.nose_pixels.size() * 3.0, 1.0)


func save_face(face: Face) -> void:
	var cut := face.images[0].duplicate() as Image
	var size := cut.get_size()
	var nose := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)

	for i in face.nose_pixels.size():
		var at := face.nose_pixels[i]
		var g := face.grey[i]
		cut.set_pixelv(at, Color(0, 0, 0, 0))
		nose.set_pixelv(at, Color(g, g, g, face.images[0].get_pixelv(at).a))

	var folder := ProjectSettings.globalize_path("%s/%s" % [FACES_DIR, face.name])
	cut.save_png(folder + "/face.png")
	nose.save_png(folder + "/nose.png")
	print("%s: %d nose pixels" % [face.name, face.nose_pixels.size()])
