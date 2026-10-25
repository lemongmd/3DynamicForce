extends SceneTree
## Свои звуки (синтез, без сторонних файлов) -> res://assets/sounds/*.wav.
##   drift_charge_1..3 — новая стадия заряда дрифта: мягкий «тук» + треск искр, без тона
##   (раньше был Blip оригинала — автору ремейка не понравился «писк»). Чем выше стадия,
##   тем ярче треск и длиннее хвост. Треск — в полосе 0.7–3.5 кГц: первая версия держала
##   энергию в «туке» на 85–180 Гц, и на динамиках ноутбука звука почти не было слышно.
##
## Запуск (из корня проекта):
##   godot --headless --path . -s res://scripts/tools/build_sounds.gd

const HandDrawn := preload("res://scripts/tools/hand_drawn.gd")
const OUT_DIR := "res://assets/sounds/"
const RATE := 22050


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for stage in [1, 2, 3]:
		_save(_drift_charge(stage), "drift_charge_%d" % stage)
	quit()


## Стадия 1..3: низкий «тук» (синус, падающий по частоте) + треск — редкие щелчки шума
## через полосовой фильтр, затухает экспонентой.
func _drift_charge(stage: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + stage
	var duration := 0.14 + 0.05 * stage
	var count := int(duration * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var thump_from := 330.0 + 40.0 * stage
	var thump_to := 200.0 + 20.0 * stage
	var crackle_density := 900.0 + 400.0 * stage
	var crackle_decay := 0.045 + 0.025 * stage
	# Полоса треска — средне-высокие частоты (без звона сверху): срез сверху — два фильтра подряд.
	var low_cut := _one_pole(700.0 + 150.0 * stage)
	var high_cut := _one_pole(2600.0 + 450.0 * stage)
	var low := 0.0
	var high := 0.0
	var high2 := 0.0
	var phase := 0.0
	var burst := 0.0
	for i in count:
		var t := float(i) / RATE
		# Тук.
		var freq := lerpf(thump_to, thump_from, exp(-t / 0.03))
		phase += TAU * freq / RATE
		var thump := sin(phase) * exp(-t / 0.03) * 0.3
		# Треск: случайные щелчки, у каждого — короткий хвост шума.
		if rng.randf() < crackle_density / RATE:
			burst = rng.randf_range(0.5, 1.0)
		burst *= 0.93
		var noise := rng.randf_range(-1.0, 1.0) * burst
		high += high_cut * (noise - high)
		high2 += high_cut * (high - high2)
		low += low_cut * (high2 - low)
		var crackle := (high2 - low) * exp(-t / crackle_decay) * (3.0 + 0.5 * stage)
		var attack := minf(t / 0.004, 1.0)
		samples[i] = (thump + crackle) * attack
	# Мягкое сжатие (tanh): треск короткими щелчками, без него пик громкий, а в среднем тихо.
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	for i in count:
		samples[i] = tanh(samples[i] / maxf(peak, 0.0001) * 3.0) / tanh(3.0)
	# Нормализация: пик -1 дБ, мягкий хвост в конце (без щелчка).
	peak = 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	var fade := int(0.02 * RATE)
	for i in count:
		var gain := 0.89 / maxf(peak, 0.0001)
		if i > count - fade:
			gain *= float(count - i) / fade
		samples[i] *= gain
	return samples


## Коэффициент однополюсного фильтра нижних частот на частоте среза.
func _one_pole(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / RATE)


func _save(samples: PackedFloat32Array, file_name: String) -> void:
	var path := OUT_DIR + file_name + ".wav"
	if HandDrawn.is_hand_drawn(path):
		print("пропущено (сделано вручную, assets/hand_drawn.txt): ", path)
		return
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.save_to_wav(ProjectSettings.globalize_path(path))
	print("saved: ", path)
