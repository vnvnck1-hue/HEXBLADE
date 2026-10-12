class_name ResCache
## 씬을 바꿔도 남는 리소스 보관소.
## load() 는 마지막 사용자가 사라지면 리소스를 풀어 버려, 섹터를 옮길 때마다 같은 GLB·텍스처·음성을 디스크에서 다시 읽었다
## (메카 GLB 약 180ms · 배경 W01 묶음 약 200ms). 여기 한 번 담아 두면 프로그램이 끝날 때까지 붙잡는다.
## 씬마다 여러 번 쓰는 무거운 에셋에만 쓴다 (전부 담으면 메모리만 늘어난다).

static var _held := {}
static var _pending := {}      ## 백그라운드로 읽는 중인 경로


## path 의 리소스 (처음 한 번만 디스크에서 읽는다). 백그라운드로 읽는 중이면 끝날 때까지 기다린다.
static func get_res(path: String) -> Resource:
	var r: Resource = _held.get(path)
	if r == null:
		if _pending.has(path):
			_pending.erase(path)
			r = ResourceLoader.load_threaded_get(path)
		if r == null:
			r = load(path)
		if r != null:
			_held[path] = r
	return r


## 무거운 에셋을 미리 백그라운드 스레드로 읽어 둔다 (로비에서: 첫 게임 진입이 GLB 를 디스크에서 읽느라 멈추지 않게).
## 다 읽기 전에 get_res 를 부르면 그 자리에서 마저 기다린다. 다 읽은 결과는 get_res 로 꺼낼 때까지 로더가 붙잡고 있다.
static func warm(paths: Array) -> void:
	for path: String in paths:
		if _held.has(path) or _pending.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending[path] = true


static func scene(path: String) -> PackedScene:
	return get_res(path) as PackedScene


## path 의 씬을 새로 만든다
static func instantiate(path: String) -> Node:
	var ps := scene(path)
	return ps.instantiate() if ps else null


static func texture(path: String) -> Texture2D:
	return get_res(path) as Texture2D


static var _shaders := {}


## 같은 코드의 셰이더는 하나만 만든다. Shader.new() + code 는 매번 GPU 셰이더를 다시 컴파일해
## 씬을 불러올 때마다 (예: 총 연출 셰이더 묶음 약 70ms) 시간이 들었다. 셰이더 값은 재질(ShaderMaterial)에 있으므로 나눠 써도 된다.
## 코드에 바뀌는 숫자를 끼워 넣으면 종류마다 하나씩 쌓이니, 바뀌는 값은 uniform 으로 넘긴다.
static func shader(code: String) -> Shader:
	var sh: Shader = _shaders.get(code)
	if sh == null:
		sh = Shader.new()
		sh.code = code
		_shaders[code] = sh
	return sh
