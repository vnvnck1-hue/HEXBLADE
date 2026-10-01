# 하스스톤 식 핸드 페인팅 — 관찰 · 적용 · 기술 스택

2026-10-01 · 상태: **게임에 시험 연결함 (K 키 / `--look=hearth`). 기본값은 꺼짐.**
앞선 일반 리서치는 [hand-painted-look.md](hand-painted-look.md).

## 1. 하스스톤은 어떻게 만들어지나 (조사)

- **아트 디렉션**: 초기 단독 아티스트였던 아트 디렉터 Ben Thompson 이 전통 회화 배경으로 스타일을 정했다. WoW·초기 Warcraft/Diablo 계열에
  "만질 수 있는 보드게임" 느낌(물리감·촉감)을 더한 방향.
- **전장(게임 보드)**: Ben Thompson·Jomaro Kindred 가 **2D 그림을 먼저 완성**하고, John Zwicker 가 Maya 에서 기본 형태를 세운 뒤
  **게임 카메라 방향에서 UV 를 투영(projection)** 해 그림을 그대로 3D 위에 씌운다. 모델은 카메라 시점에 맞게 기울이고 변형해 둔다.
  보드 하나에 4~5일, 클릭하면 반응하는 장식·이펙트·애니메이션에 1주 정도. 엔진은 Unity.
- **즉 빛과 그림자는 거의 전부 그림 안에 들어 있다.** 실시간 조명은 보조(그림자 드리우기 정도)다.
- **블리자드 핸드 페인팅 공통 규칙** (polycount·80.lv 의 블리자드 계열 작업 분석):
  저폴리 + 손으로 칠한 디퓨즈 한 장 / 잘고 복잡한 디테일 대신 **큼직하게 뭉친 형태** / **채도 높은 색**, 가장 진한 채도는 시선이 갈 곳에 /
  모든 면에 보색(파랑·노랑·초록·빨강) 색 변화 / AO·캐비티를 바탕으로 깔고 "위에서 내려오는 빛" 그라디언트를 덮은 뒤 덧칠.
- 팬 제작 커스텀 아레나(Florian Neumann): Maya → Marmoset 베이크(노멀·ID) → Substance Painter 에서 긁힘·때를 **손으로** 칠하고 Light Generator 로 음영을 색 맵에 넣음 → 발광 맵 별도.

## 2. 직접 관찰한 것 (Goblins vs Gnomes · Stormwind 전장 원본 이미지)

| 항목 | 관찰 |
|---|---|
| 색감 | 전체가 따뜻한 빛(노랑·크림). 금속도 순회색이 아니라 **올리브·청록 기운의 회색**, 구리 호스는 진한 주황. 가장 어두운 곳도 검정이 아니라 **짙은 갈색·자주**. 파랑 천·청록 발광이 따뜻함을 받쳐 주는 보색 |
| 명암 구조 | 파츠 하나하나가 **위가 밝고 아래가 어둡게** 칠해진 덩어리. 실제 광원과 상관없이 "모든 덩어리 위에 빛" |
| 형태 표현 | **검은 외곽선 없음.** 위를 향한 모서리는 **밝은 선**, 아래를 향한 모서리·틈은 **짙은 갈색 선**으로 형태를 세운다. 모서리는 칠이 벗겨져 들쭉날쭉 |
| 표현 밀도 | 중간. 큰 형태 → 중간 디테일(리벳·판 이음매·볼트) 순서로 읽히고, 면 안은 깨끗하다(잔 노이즈 없음, 부드러운 그라디언트 + 큰 얼룩) |
| 하이라이트 | 빨간 버튼·둥근 금속에 **흰 점 하이라이트**. 반사(스펙큘러)는 이것 말고는 거의 없다 |
| 그림자 | 물체 아래 바닥에 따뜻한 갈색 접촉 그림자 |
| 발광 | 청록·파랑 발광은 밝은 심 + 색 번짐, 경계가 비교적 또렷 |

## 3. 이 게임에 옮긴 방법

모델은 코드 조립 프리미티브라 그림을 투영할 UV 가 없다. 대신 **파츠마다 메시 경계 상자(AABB)를 셰이더에 넘겨**
셰이더가 "이 파츠의 위·아래·모서리·귀퉁이"를 알게 했다. 그러면 하스스톤의 칠 규칙을 파츠 단위로 재현할 수 있다.

| 관찰 | 구현 (`PaintedLook.HEARTH_SHADER`) |
|---|---|
| 덩어리마다 위 밝고 아래 어둡게 | 파츠 AABB 안에서 **월드 위쪽 기준** 세로 그라디언트. 아래는 명도↓·채도↑·자줏빛 |
| 윗모서리 밝은 선 / 아랫모서리 짙은 선 | 면의 두 축이 AABB 경계에 가까우면 모서리 띠. 이웃 면이 위를 향하면 크림색, 아래면 짙은 갈색 |
| 벗겨진 모서리 | 띠 폭을 노이즈로 들쭉날쭉하게 |
| 리벳 (중간 밀도 디테일) | 30cm 넘는 상자형 평면의 네 귀퉁이에 볼트 머리(어두운 테 + 위쪽 밝음) |
| 깨끗한 면 + 보색 얼룩 | 큰 노이즈로 명도 ±7%, 보색 얼룩 소량 |
| 따뜻한 빛 · 채도 높은 그림자 | 감마 공간에서 칠(선형 공간 연산은 과포화됨) · 실시간 조명은 넓고 부드럽게, 그림자는 자줏빛 |
| 흰 점 하이라이트 | 아주 좁은 스펙큘러 한 점 |
| 외곽선 없음 | 외곽선 대신 모서리 명암 (O 키 카툰과는 따로 켜고 끔) |
| 지형 | 맵 벽(한 메시에 합쳐진 블록)은 월드 좌표 얼룩 + 윗면 밝게·옆면 어둡게, **윗모서리 밝은 선은 화면 공간 패스를 지형에만** 건다. 남보라 지형·바닥을 자두·갈색 쪽으로 옮김 |
| 따뜻한 조명 | 주광 노랑, 환경광 자줏빛, 채도 +10% (켤 때만, 끄면 원래 값) |

게임 연결: `Main._ready` 에서 `PaintedLook.attach(self, env, sun)` 한 줄, K 키 한 줄. 웨이브로 나중에 생기는 적과 파편은 `SceneTree.node_added` 로 잡아 바꾼다.
발광·투명 머티리얼과 `Pal.flat` 은 건드리지 않아 기존 발광 연출·피격 섬광·락온 표시와 충돌하지 않는다.

비교 이미지 (`output/painted-look-20261001/`):
- `hearth_close.png` / `hearth_wide.png` — 현재 · 카툰 · HEARTH · HEARTH+따뜻한 조명
- `game_hearth_before_after.png` — 실제 섹터 런 자동 플레이 화면 (왼쪽 현재 / 오른쪽 HEARTH)
- `sheet_close.png` / `sheet_wide.png` — 앞서 만든 다른 룩까지 8종

## 4. 한계 — 지금 방식으로 닿지 않는 부분

1. **그림 자체의 정보량.** 하스스톤은 사람이 형태마다 판단해서 칠한다(어디에 긁힘, 어디에 때, 어디에 가장 진한 채도). 절차적 셰이더는 규칙만 반복하므로
   가까이서 보면 "칠한 규칙"이지 "칠한 그림"은 아니다.
2. **실루엣.** 하스스톤 기계는 둥글고 과장된 덩어리(두꺼운 베벨, 큰 볼트, 굵은 호스)인데 우리 모델은 날렵한 상자 조합이다. 질감보다 형태 차이가 더 크다.
3. **팔레트.** 하스스톤은 따뜻한 나무·양피지·금 위에서 논다. 이 게임은 어두운 남보라 SF 아레나라, 색 보정만으로는 하스스톤 색감까지 가지 않는다(정체성 문제라 일부러 절반만 옮겼다).
4. 원경(게임 카메라)에서는 모서리 선·리벳이 작아진다. 쿼터뷰 거리 기준으로 `edge_w`·리벳 크기를 더 키울 여지가 있다.

## 5. 제대로 하려면 필요한 기술 스택

| 단계 | 하스스톤/블리자드 | 이 프로젝트에 맞는 선택 | 비고 |
|---|---|---|---|
| 모델링 | Maya / 3ds Max, 저폴리 + 두꺼운 베벨 | **Blender** (무료) — 지금 코드 모델을 glTF 로 내보내 다듬거나 새로 만들기 | Godot 은 glTF 를 바로 읽는다. 지금의 "코드로 조립" 원칙을 일부 포기해야 함 |
| UV | 수동 UV / 보드는 카메라 투영 UV | Blender UV 펼치기, 쿼터뷰 고정 소품은 카메라 투영도 가능 | 텍셀 밀도 낮게(캐릭터 512~1024) — 큰 붓질이 오히려 하스스톤답다 |
| 베이크 | AO · 캐비티 · 탑다운 그라디언트 | Blender 베이크(AO·포인터니스=곡률) 또는 Marmoset Toolbag | 칠의 밑바탕 |
| 페인팅 | Photoshop + 3D 페인팅(3DCoat·BodyPaint), 최근엔 Substance Painter | **3DCoat**(핸드 페인팅 강함) · **Substance Painter**(레이어·생성기) · **ArmorPaint**(오픈소스) · Blender 텍스처 페인트 · Krita/Photoshop 보정 | 사람이 칠하는 단계. 디퓨즈 한 장에 빛을 넣는다 |
| 엔진 머티리얼 | Unity, 거의 언릿 + 보조 조명 | Godot `ShaderMaterial` — 텍스처 × 약한 조명(지금 HEARTH 의 light() 그대로 재사용) + 발광 맵 | 이미 만든 셰이더에 텍스처만 꽂으면 된다 |
| 이펙트 | 손으로 그린 시트 + 스크롤 텍스처 메시 | 이미 있는 `ToonGunFX`(손그림 플립북) 방향을 확장 | 질감과 이펙트가 같은 "손그림" 언어여야 어울린다 |
| 반자동 대안 | — | ① 지금 절차적 셰이더(HEARTH) 유지 · 형태만 둥글게 ② HEARTH 결과를 Blender 에서 텍스처로 구워 사람이 덧칠 ③ 생성형 이미지로 손그림 브러시 타일을 만들어 트라이플래너 투영 | ②가 비용 대비 품질이 가장 좋다 |

**권장 순서**: (1) 지금 HEARTH 로 방향 확인 → (2) 플레이어 기체 하나만 Blender 로 옮겨 베벨을 두껍게, UV 펴고 3DCoat/Substance 로 한 장 칠해 비교 →
(3) 만족하면 적·소품으로 확대하고 맵 바닥은 칠한 타일 텍스처로 교체.

## 출처

- [Inven Global — Ben Thompson 인터뷰](https://www.invenglobal.com/articles/1554/how-hearthstones-art-director-ben-thompson-breathed-life-into-hearthstone)
- [Hearthstone Wiki — Design and development](https://hearthstone.fandom.com/wiki/Design_and_development_of_Hearthstone) · [Battlefield](https://hearthstone.fandom.com/wiki/Battlefield) · [John Zwicker](https://hearthstone.fandom.com/wiki/John_Zwicker)
- [80.lv — Making a Custom Arena for Hearthstone (Florian Neumann)](https://80.lv/articles/making-a-custom-arena-for-hearthstone)
- [polycount — Focusing on Blizzard's hand painted style](https://polycount.com/discussion/120605/focusing-on-blizzards-hand-painted-style) · [How to achieve Blizzard style](https://polycount.com/discussion/87043/how-to-achieve-blizzard-style)
- [80.lv — Matt McDaid, Mastering the Stylized Art of Blizzard](https://80.lv/articles/matt-mcdaid-mastering-the-stylized-art)
- [80.lv — Studying Hand-Painted Texturing Workflow](https://80.lv/articles/studying-hand-painted-texturing-workflow-for-stylized-art)
- [Unity 포럼 — Hearthstone inspired unlit multilayer shader](https://forum.unity.com/threads/released-ultimate-unlit-ui-hearthstone-inspired-multilayer-shader.316310/)
