# 핸드 페인팅 질감 리서치와 시험 적용

2026-10-01 · 상태: **시험 모듈만 있다. 게임 씬에는 아직 연결하지 않았다.**

## 0. 출발점 — 이 게임 모델의 제약

- 모든 모델은 `Build`(`scripts/build.gd`)가 박스·원통·구·깎은 판재(`bevel_mesh`)를 코드로 조립해 만든다.
  파츠마다 `Pal.lit()` / `Pal.mech()` 단색 `StandardMaterial3D` 하나가 붙는다.
- **UV 를 펼친 메시도, 칠한 텍스처도 없다.** 보통 핸드 페인팅이라고 하면 "UV 를 펴고 포토샵·3DCoat 에서 텍스처를 칠한다"인데,
  이 방식은 지금 구조와 맞지 않는다.
- 그래서 시험한 기법은 모두 **셰이더 안에서 절차적으로 칠한 느낌을 만드는 것**이다. 메시 쪽 데이터(UV·버텍스 컬러)가 필요 없다.

## 1. 기법 조사

| # | 기법 | 대표 사례 | 이 프로젝트 적합도 | 비용 |
|---|---|---|---|---|
| A | 손으로 칠한 텍스처 + 약한 조명 | WoW, Torchlight, Arcane(극장판) | ✗ 메시 UV·텍스처 작업이 필요. 모델을 블렌더 등으로 옮겨야 한다 | 아트 작업 큼 |
| B | **절차적 붓결 알베도** (늘인 노이즈를 트라이플래너로 투영) | 상용 "stylized hand-painted shader" 류 | ○ 구현함 (STROKE) | 가벼움 |
| C | **칠한 빛 그라디언트** — 윗면 밝고 따뜻, 아랫면 어둡고 차갑게, 발치로 어둡게 | WoW 텍스처의 "탑다운 그라디언트 + AO 베이크" 관행 | ○ 구현함 (B 와 함께) | 거의 없음 |
| D | **붓으로 끊은 셀 음영** — 음영 경계를 붓결 노이즈로 흔들고 2~3 단으로 칠, 그림자에 색조 | Guilty Gear Xrd(버텍스 컬러로 음영 임계값 오프셋), 원신 램프 | ○ 구현함 (PAINTED) | 가벼움 |
| E | **엣지 하이라이트** — 볼록 모서리를 밝게 긁어 형태를 세움 | 손그림 텍스처의 기본 기법 | ○ 화면 공간으로 구현함 (EDGE) | 전체 화면 1 패스 |
| F | **화면 유화 필터** — 쿠와하라(사분면 분산 최소 평균) + 캔버스 결 | Godot 에셋 라이브러리 Kuwahara, 각종 painterly 후처리 | ○ 구현함 (OIL) | 전체 화면 100 탭 정도 |
| G | 붓 맵으로 노멀 회전 (brushed shading) | Blender "Brushed Shading" 애드온 | △ 미구현. D 의 다음 단계 후보 | 가벼움 |
| H | 버텍스 컬러에 칠·AO 저장 | Guilty Gear Xrd | △ 미구현. `bevel_mesh` 는 SurfaceTool 이라 넣을 수 있지만 BoxMesh 등 기본 메시는 불가 | 메시 생성 수정 |
| I | 손그림 브러시 타일 이미지를 트라이플래너로 투영 | 상용 hand-painted 텍스처 팩 | △ B 를 이미지로 바꾼 것. 이미지 한 장을 만들어야 한다 | 가벼움 |

핵심만 정리하면:

- **진짜 핸드 페인팅(A)** 은 빛과 그림자를 텍스처에 직접 칠하고 엔진 조명은 약하게 둔다. 이 효과의 대부분은
  "위가 밝고 아래가 어둡다(C)", "면 안에 붓 얼룩이 있다(B)", "모서리가 밝게 긁혀 있다(E)", "그림자가 회색이 아니라 색이 있다(D)" 네 가지로 쪼갤 수 있고,
  이 넷은 텍스처 없이 셰이더로 흉내낼 수 있다.
- **화면 필터(F)** 는 모델과 상관없이 화면 전체를 그림처럼 만든다. 효과가 가장 확실하지만 작은 디테일(눈·문양·탄)이 뭉개진다.

## 2. 시험 구현

- 모듈: [`scripts/presentation/painted_look.gd`](../scripts/presentation/painted_look.gd) (`PaintedLook`)
  - `PaintedLook.apply(root, preset)` — root 아래 `Pal.lit/mech` 의 **불투명·비발광** 머티리얼만 칠 머티리얼로 바꿔 끼운다. 원본은 메타에 보관해 `NONE` 으로 되돌린다.
    발광(코어·눈)·투명·`Pal.flat` 은 건드리지 않으므로 기존 코드가 `emission_energy_multiplier` 를 만지는 부분과 충돌하지 않는다.
  - `PaintedLook.set_post(cam, preset)` — EDGE / OIL 후처리 사각형을 카메라에 붙인다.
  - 붓결은 **오브젝트 공간** 노이즈라 움직이는 파츠에 붙어 다닌다(화면에서 미끄러지지 않음). 4m 넘는 큰 면(바닥 등)은 붓결을 크고 옅게 바꾼다.
- 비교 씬: [`_capture/painted_look_show.gd`](../_capture/painted_look_show.gd), 실행 `painted_look.cmd`
  - 1~6 룩 전환 · Space 회전 정지 · C 원경/근경
  - 캡처: `powershell -File tools\godot.ps1 wait --resolution 1280x720 -s _capture/painted_look_show.gd -- --shots=<공백 없는 경로>`

| 키 | 룩 | 내용 |
|---|---|---|
| 1 | 현재 (기본) | 지금 게임 그대로 |
| 2 | 현재 (O 키 카툰) | 지금 셀 음영 + 외곽선 |
| 3 | STROKE | B + C. 조명 계산은 엔진 기본 그대로 |
| 4 | PAINTED | STROKE + D(붓으로 흔든 3단 음영, 보라 그림자 색조, 붓 하이라이트) + 외곽선 |
| 5 | EDGE | PAINTED + E(볼록 모서리 위쪽 면을 같은 색의 밝은 획으로) |
| 6 | OIL | STROKE + F(쿠와하라 반경 4 + 캔버스 결) |

비교 이미지: [`output/painted-look-20261001/sheet_close.png`](../output/painted-look-20261001/sheet_close.png) (근경),
[`sheet_wide.png`](../output/painted-look-20261001/sheet_wide.png) (게임 카메라와 비슷한 원경). 룩별 원본 PNG 도 같은 폴더에 있다.

## 3. 관찰

- **근경에서는 차이가 확실하다.** PAINTED 는 크림 장갑에 붓 얼룩이 생기고 그림자가 보랏빛으로 바뀌어 "칠한" 느낌이 가장 잘 난다.
  EDGE 는 어두운 관절·다리 모서리에 밝은 칠 벗겨짐처럼 보인다. 크림색 파츠에선 거의 보이지 않는다.
- **게임 카메라 거리(원경)에서는 잔 붓결이 거의 안 보인다.** 쿼터뷰에서 읽히는 것은 톤(그라디언트·그림자 색조)과 OIL 의 뭉갬 정도다.
  게임에 넣는다면 `stroke_scale` 을 낮추고(붓결을 크게) `brush` 를 올리는 쪽으로 다시 맞춰야 한다.
- OIL 은 원경에서도 그림 느낌이 나지만 크롤러 눈, 탄피 같은 작은 형태가 뭉개진다. HUD 는 캔버스라 영향 없음.
- 비용: STROKE/PAINTED 는 픽셀당 노이즈 15 회 정도로 가볍다. EDGE 는 깊이·노멀 8 방향 샘플, OIL 은 화면 100 탭 — 둘 다 전체 화면 패스다.

## 4. 넣는다면 (제안, 미적용)

1. 고른 프리셋을 `Pal.lit()` / `Pal.mech()` 가 바로 칠 머티리얼을 돌려주게 하거나, 씬 구성 후 `PaintedLook.apply(world, …)` 한 번 호출.
   O 키 카툰처럼 토글 키로 켜고 끌 수 있게 하는 것을 권한다.
2. 원경 기준으로 `stroke_scale`·`brush`·`shadow_tint` 재조정.
3. 더 나가려면 G(붓 맵 노멀 회전)로 음영 경계 자체를 붓 모양으로, 또는 I(손그림 브러시 타일 한 장)로 붓결 품질을 올린다.

## 출처

- [Guilty Gear Xrd GDC 발표 자료 (Junya C. Motomura)](https://www.ggxrd.com/Motomura_Junya_GuiltyGearXrd.pdf) — 버텍스 컬러로 음영 임계값·AO 를 칠하는 방식
- [Unity3D-PGMGuiltyShader](https://github.com/pakillottk/Unity3D-PGMGuiltyShader) — 위 방식의 구현 예
- [polycount: World of Warcraft - normal maps?](https://polycount.com/discussion/114888/world-of-warcraft-normal-maps) · [80.lv: WoW 디오라마 텍스처링](https://80.lv/articles/002mrs-crafting-a-wow-diorama-textures-painting-lighting) — 탑다운 그라디언트·AO 베이크 후 덧칠, 조명은 약하게
- [Brushed Shading (Blender 애드온)](https://superhivemarket.com/products/brushedshading) — 붓 맵으로 노멀을 회전해 음영을 붓칠처럼
- [On Crafting Painterly Shaders — Maxime Heckel](https://blog.maximeheckel.com/posts/on-crafting-painterly-shaders/) — 쿠와하라 계열 painterly 후처리
- [Kuwahara Shader — Godot Asset Library](https://godotengine.org/asset-library/asset/1183)
- [How to Make a Triplanar Shader in Godot — Febucci](https://blog.febucci.com/2025/10/how-to-make-a-triplanar-shader-in-godot/)
- [URP Painterly Shader — Mia Zhang](https://www.cabbageblame.me/projects/urp-painterly-shader/)
- [Why Arcane looks so good — RedShark News](https://www.redsharknews.com/why-netflixs-arcane-looks-so-good-how-fortiche-ramped-up-the-animation-pipeline) — 직접 칠한 텍스처 + 스펙큘러 억제
