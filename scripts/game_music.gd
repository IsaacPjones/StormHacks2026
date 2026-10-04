extends AudioStreamPlayer

## Skip trailing silence without editing the original audio file.
@export_range(0.0, 30.0, 0.1) var loop_end_trim_seconds: float = 3.5


func _ready() -> void:
	# Loop the supplied WAV without changing its shared imported resource.
	if stream is AudioStreamWAV:
		var music := stream.duplicate() as AudioStreamWAV
		music.loop_mode = AudioStreamWAV.LOOP_FORWARD
		music.loop_begin = 0
		# WAV loop endpoints use sample frames, rather than seconds.
		var loop_seconds := maxf(1.0 / music.mix_rate, music.get_length() - loop_end_trim_seconds)
		music.loop_end = roundi(loop_seconds * music.mix_rate)
		stream = music
	play()
