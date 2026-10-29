# 적 타격감(Hit Feel) 기능 명세서

작성일: 2026-10-28 · 기준 브랜치 `feature/round-skill-hud` · 엔진 Godot 4.7.2 (GDScript)

이 문서는 **플레이어가 적을 때렸을 때** 플레이어가 느끼는 "손맛"을 구성하는 모든 기능을 한곳에 정리한 명세다.
각 항목은 ① 요구사항(무엇이 보장돼야 하는가) ② 현재 구현값(코드에서 읽은 수치) ③ 조정 손잡이 ④ 예외 ⑤ 검증 방법으로 적는다.
수치는 2026-10-28 시점 코드 기준이며, 값을 바꾸면 이 문서의 "현재 값" 열도 함께 고친다.

관련 문서: **[hit-effects.md](hit-effects.md)(타격 이펙트 상세)** · [misfitz-hit-vfx.md](misfitz-hit-vfx.md) · [damage-log.md](damage-log.md) · [moco-vfx-claude.md](moco-vfx-claude.md) · [sword-combo.md](sword-combo.md) · [ground-break.md](ground-break.md) · [parry-camera-screen-effects.md](parry-camera-screen-effects.md)(용어집) · [lancaster-parry-research.md](lancaster-parry-research.md)

---

## 1. 목적과 범위

### 1.1 목적
- 한 번의 타격이 **"맞았다"는 확신**(판정 피드백)과 **"세게 맞았다"는 무게**(강도 피드백)를 0.3초 안에 전달한다.
- 연타·콤보·처치로 이어질수록 피드백이 **누적되어 커지는 느낌**(상승감)을 준다.
- 판정(피해·넉백·경직)은 연출과 분리한다. 연출을 끄거나 바꿔도 전투 결과는 같아야 한다.

### 1.2 범위
| 포함 | 제외 |
|---|---|
| 플레이어 공격(기본총 · 광선검 6단 콤보 · 관통 일격 · 레이저 · 메가 레이저 · 미사일 · E 도약 내려찍기 · 휠윈드 · 패링 반격)이 적·보스·소품에 **닿은 순간** 이후의 모든 피드백 | 플레이어가 맞을 때의 피격 연출(별도) · 적 공격 예고(위험 섬광) · 드론 청소 피드백 · 궁극기 락온 연출 |

### 1.3 설계 원칙 (사용자 확정 사항 포함)
1. **판정 → 연출 한 방향 의존.** 연출 모듈(`MocoFX` · `DamageLog` · `ComboMeter` · `GroundBreak` 등)은 판정 결과를 받아 그리기만 하고, 판정 코드를 되부르지 않는다.
2. **강타(heavy)와 일반을 모든 층에서 구분한다.** VFX 크기·히트스톱·숫자 크기·피격 반응 풀이 모두 같은 분류를 쓴다.
3. **연출 시계는 용도에 맞게 고른다.** 히트스톱으로 멈춰야 할 것(적 몸·검 궤적·왜곡·카메라)은 게임 시간, 멈추면 안 되는 것(피해 숫자·콤보 미터·임팩트 프레임)은 실제 시간.
4. **정적 캐시에 무작위 실수를 키로 넣지 않는다.** 색·크기는 `snappedf` 등으로 몇 단계로 묶는다(`AGENTS.md` 4절).
5. 레퍼런스: 젠레스 존 제로(히트스톱·임팩트 프레임), MISFITZ 콘셉트(타격 별 모양), 땅굴크루(피해 숫자 손맛), mo.co(색·검 궤적).

---

## 2. 용어

| 용어 | 뜻 |
|---|---|
| 타격(hit) | `Enemy.take_hit(dmg, dir, pos, source)` 가 한 번 호출되는 것 |
| source | 피해 원천 문자열. `bullet` · `slash` · `phantom` · `laser` · `missile` · `parry` · 그 밖 |
| 강타(heavy) | `dmg >= 4` **또는** source 가 slash / phantom / missile / parry |
| 원거리 톤 | source 가 `MisfitzHit.RANGED` = bullet · laser · missile → 노란 VFX |
| 히트스톱 | `Engine.time_scale` 을 아주 낮춰 실제 시간으로 n초 동안 거의 멈춤 |
| 피격 반응(HitReact) | 적 몸이 맞고 취하는 자세 5종 |
| 경직(hurt) | 피격 반응 동안 AI 가 멈추는 상태. `stagger`(패링 경직)와 다름 |
| 미니 타격(mini) | 다단히트 중간 타격. 짧은 정지·작은 흔들림 |

---

## 3. 타격 1회의 처리 흐름

```
공격 판정 (player.gd combo_strike / bullet.gd / laser / missile …)
  └ Enemy.take_hit(dmg, dir, pos, source)                      enemy.gd:540
      ├ dmg_hook 보정 (로그라이크 등) · 경직 중 ×2             :547-551
      ├ hp -= dmg · _bar_hit = 1 (체력바 하이라이트)            :557-559
      ├ knock += dir * (3 + dmg)  (parry_committed 면 생략)     :561-562
      ├ wob_v (흔들림 스프링) · punch = 1 (눌림)                 :564-565
      ├ flash_t = 0.06 (흰 섬광 오버레이)                        :566-567
      ├ _hit_spark → HitSpark.spawn → MocoFX.hit → MisfitzHit    :578-595
      │     └ MocoFX.report → ComboMeter.hit + DamageLog(숫자)   moco_fx.gd:343
      ├ Sfx "hit"                                                :568
      └ hp <= 0 ? die() : _hurt()  (HitReact 선택 · 경직 길이)   :569-572
공격 쪽 (호출자) 가 덧붙이는 것
  ├ Main.hitstop(sec)  · Main.shake · Main.kick · camera.fov_punch
  ├ 검 궤적 · 충격파 · Distortion.burst · GroundBreak.burst
  └ 처치면 Main.on_enemy_killed → hitstop 0.07 · shake 0.35 · kill_punch · ComboMeter.kill
```

**보스**(맘모스 · VULCAN · 거미 · 워든 · LANCASTER)는 자체 `take_hit` 에서 피해 확정 직후 `MocoFX.report` 를 직접 부르고(`boss_enemy.gd:898` 등), `fx_point` 로 연출 위치를 겉면으로 옮긴다.

---

## 4. 기능별 명세

### 4.1 피해 판정과 강타 분류

| 항목 | 요구사항 | 현재 값 | 위치 |
|---|---|---|---|
| 강타 분류 | 공격 종류와 피해량 중 하나라도 크면 강타 | `dmg >= 4` 또는 source ∈ {slash, phantom, missile, parry} | `enemy.gd:592, 625` |
| 경직 중 추가 피해 | 패링 경직(`stagger_t > 0`) 중 피해 2배. 숫자·반응도 2배 값 | ×2 | `enemy.gd:549-551` |
| 피해 보정 훅 | 모드가 피해만 바꾸고 넉백·반응은 원래 피해 기준 | `dmg_hook`(체력), `dmg_raw`(연출) | `enemy.gd:10, 546-558` |
| 패링 준비 중 | 패링 공격을 시작한 적은 끝까지 수행: 피해만 받고 넉백·경직 없음 | `parry_committed()` | `enemy.gd:423, 561, 605` |
| 소품 | 가스통 등 `Enemy.prop` 은 숫자·STUN!·처치 수 없음 | | `enemy.gd:594, 495` |

검 판정(`player.gd:1115-1161`): 높이차 1.6 이내, `reach + radius` 안이면서 거리 0.9 미만이거나 반각 `cone` 안이면 적중. `kb` 로 넉백을 단별로 조정(`en.knock = k0 + (en.knock - k0) * kb`). 장갑 적은 피해는 들어가되 `blocked` 로 세어 콤보가 이어지지 않는다.
총알(`bullet.gd:94-140`): 선분을 0.3 단위로 나눠 판정, 높이차 `HIT_DY` 1.35, 피해 1, `fx_point` 가 있으면 겉면에 착탄 연출.

### 4.2 적 피격 반응 (몸)

요구사항: 맞은 **방향·세기·종류**가 적 몸의 움직임으로 드러나야 한다. 같은 반응이 연달아 나오지 않는다. 연타 중에도 끊기지 않고 이어진다.

#### 즉시 반응 (모든 타격 공통)
| 요소 | 현재 값 | 위치 |
|---|---|---|
| 흰 섬광 오버레이 | 0.06초, unshaded 흰색 알파 .85, 몸 모든 메시 `material_overlay` | `enemy.gd:566, 1052` · `pal.gd:159` |
| 눌림(punch) | 스케일 (1+.22p, 1−.16p, 1+.22p), p 는 초당 6 감쇠 | `enemy.gd:184-185` |
| 넉백 | `dir * (3 + dmg)` m/s, 초당 30 감쇠(경직 중 26) | `enemy.gd:562, 259, 516` |
| 흔들림 스프링 | `wob_v += (8 + 2·dmg)`, 스프링 −220·wob −11·wob_v | `enemy.gd:564, 772` |
| 체력바 | 맞은 순간 밝기 +0.6, 잔상(chip)이 0.6초 뒤 따라 내려옴 | `enemy.gd:1115-1159` |
| 효과음 | `hit` 0.06초(노이즈 + 1800Hz), 피치 흔들림 .15, −6dB | `enemy.gd:568` · `sfx.gd:45` |

#### HitReact 5종 (`_hurt`, `enemy.gd:604-758`)
| 반응 | 풀 | 경직 길이 | 자세 요점 |
|---|---|---|---|
| RECOIL 젖힘 | 일반·강타 | 0.3 (강타 0.32) | 맞은 축으로 `e·amp·1.25` 회전, 밀림 0.26 |
| TWIST 비틀림 | 일반·강타 | 0.3 (강타 0.32) | yaw 가 맞은 쪽으로 홱 (`side·e·(0.9+0.9amp)`) |
| CRUMPLE 숙임 | 일반·강타 | 0.38 | 앞으로 숙이고 0.3 가라앉음, 스케일 (1+.16, 1−.24, 1+.16) |
| SPIN 한 바퀴 | 강타만 | 0.5 | yaw 한 바퀴(TAU, ease-out³) + 추가 넉백 3, 잔상 0.05초마다 |
| LAUNCH 띄움 | 강타만 | 0.5 | 0.85m 떠올라 뒤집힘 + 넉백 3, 착지 먼지 + 눌림 |

- 곡선 `_hurt_curve`: 0.03초 만에 극단 → `HURT_HOLD` 0.07초 떨림 정지(진폭 0.08) → 감쇠 스프링 복귀(`exp(−7r/rest)·cos(2π·1.15·r/rest)`).
- 진폭 `hurt_amp = clamp(0.5 + 0.07·dmg, 0.5, 0.95)`.
- 선택: 직전 반응을 풀에서 뺀다(`_pick_react`). 포탑은 SPIN·LAUNCH 제외. `force_react` 로 확인용 고정.
- 연타: 경직 중 다시 맞으면 직전 자세에서 0.05초 블렌드로 이어받음. SPIN/LAUNCH 는 진행 85% 전엔 새 반응으로 안 끊고 `hurt_t ≥ 0.12` 만 보장.
- 걸리지 않는 조건: 착지 전 · 패링 경직 중 · 회피 이동 중 · `parry_committed()` · `_can_hurt()` false.
- 경직이 걸리면 적의 공격은 취소(`_interrupt`: 연사 중단, 패링 탄 준비 취소, 다음 발사까지 0.85초).
- 우선순위: `stagger` > `hurt` > AI.

#### 패링 경직 (`stagger`, `enemy.gd:471-537`) — 참고
넉백 16, 섬광 0.1초, 눌림, 스파크 26개, `clank`, 새로 들어갈 때만 민트 `STUN!`. 경직 동안 몸이 0.18 가라앉고 기울어 흔들리며 0.08~0.16초마다 작은 스파크.

### 4.3 히트스톱 · 시간 제어

요구사항: 타격 순간 **적 몸 · 검 궤적 · 카메라 · 왜곡**이 함께 멈춘다. 다단히트 중간 타격은 아주 짧게, 마무리·처치·강타는 길게. 히트스톱이 겹치면 더 늦게 끝나는 쪽이 남는다. 슬로우모션(궁극기 0.06 등)과 충돌하지 않는다.

| 항목 | 현재 값 | 위치 |
|---|---|---|
| 구현 | `Main.hitstop(sec, scale=0.06)`: `time_scale = min(scale, slowmo·0.5)`, 실제 ms 로 `hitstop_until` 갱신, `_process` 에서 복귀 | `main.gd:1005-1025` |
| 물리 틱 | 항상 60 고정(슬로우모션에서 틱을 올리면 렉) | `main.gd:1016` |
| 완전 정지 | `scale 0.002` (패링 하드 프리셋) | `parry.gd:36-42` |

**공격별 히트스톱 (초)**
| 공격 | 값 | 위치 |
|---|---|---|
| 검 콤보 각 cut | cut 의 `stop`: 1타 .025/.025/.06 · 2타 .05/.07 · 3타 난무 .018, 마무리 .08 · 4타 선풍 .014×7 · 5타 .035/.07 · 6타 낙월 .13 | `sword_combo.gd:111-262, 773` |
| 6타 지연 참격 | 중간 .016, 마지막 .05 | `sword_combo.gd:881` |
| 관통 일격(phantom) | 0.12 (일괄 판정 뒤) | `player.gd:1260` |
| 레이저 | 충전 ≥ .67 → 임팩트 프레임 길이 .034 + (.06 적중 / .02) · 그 외 적중 .06 | `player.gd:1077-1080` |
| 메가 레이저 | 임팩트 프레임 .068 + .05 | `player.gd:1662` |
| E 도약 내려찍기 | 적중 .11 / 헛침 .04 | `leap_slam.gd:322-326` |
| 휠윈드(2단 대시) | .025 | `dash_whirl.gd:201` |
| 2단 대시 PERFECT | .03 | `player.gd:855` |
| 처치 | .07 | `main.gd:842` |
| 처치 연출 OVERLOAD 터짐 | .04 | `enemy.gd:880` |
| 패링 성공 | 프리셋 `Parry.STOP_PRESETS`(기본 HEAVY: light .17 / heavy .28, scale .002, shiver .6) | `parry.gd:36-43` |

기본총(bullet)·미사일은 히트스톱이 없다(연사 리듬 보호).

### 4.4 카메라 피드백 (`camera_rig.gd`)

요구사항: 타격 방향으로 **킥**, 세기만큼 **셰이크**, 강타·마무리에 **FOV 펀치**, 처치에 **끌림+줌인**. 모두 스프링이라 겹쳐도 발산하지 않는다(1/240초 분할 적분).

| 손잡이 | 동작 | 현재 값 |
|---|---|---|
| `shake(a)` | trauma 누적(상한 1), 진폭 trauma²×0.5, 초당 1.8 감쇠 | `:148, 343-349` |
| `kick(v)` | 위치 반동 스프링 k180 d18 | `:152, 250` |
| `fov_punch(deg)` | `fov_v += deg·22·p.punch`(punch .3), 스프링 k160 d14, FOV 20~80 | `:157, 248, 357` |
| `kill_punch(pos)` | 격파 지점 쪽 0.22·kill_pull(.3) 끌림 0.35초, zoom_v −1.4·kill_pull (누적 안 함) | `:162-169` |

**공격별 호출값**
| 공격 | shake | kick | fov_punch | 위치 |
|---|---|---|---|---|
| 기본총 발사 | .05 | −d·.09 | — | `player.gd:976-977` |
| 콤보 공중 사격 | .06 (마지막 .1) | −d·.18 | — | `player.gd:997` |
| 검 적중(일반 cut) | .3 + stop·3 | dir·.45 | −3 − stop·30 | `sword_combo.gd:773-777` |
| 검 적중(mini) | .18 + stop·3 | dir·.15 | — | 〃 |
| 검 막힘 / 헛침 | .25 / .12 | — | — | `:781-784` |
| 검 강타 `_heavy_hit` | .45 | dir·.6 | — | `:904-920` |
| 6타 착지 `_slam_fx` | .5 | — | — | `:889-900` |
| 관통 일격 | .3(통과) → .6(판정) | dir·.9(시작) | +8(시작) → −5(통과) | `player.gd:1217-1262` |
| 레이저 | lerp(.3,.75,k) | −dir·lerp(.4,1.1,k) | lerp(2,6,k) | `player.gd:1074-1076` |
| 메가 레이저 | .6 | — | 9 | `player.gd:1661-1663` |
| E 내려찍기 | .7 | DOWN·.6 | −7 | `leap_slam.gd:321-332` |
| 미사일 폭발 | .08 | — | — | `missile.gd:235` |
| 처치 | .35 + kill_punch | — | — | `main.gd:843-844` |
| 패링 성공 | `parry_impact(−dir, 1.25/.75)`: fov −34k, zoom −1.8k, kick 2.6k, roll ±.012k, shake .22k (+ heavy 면 `parry_cine` 0.45초 줌 .87) | `camera_rig.gd:257-273` |

### 4.5 타격 VFX

#### 4.5.1 타격 버스트 (적 몸 위)
요구사항: 맞은 지점에 공격이 **온 쪽**을 향한 별 모양 버스트. 근접은 보라, 원거리는 노랑. 강타는 1.3배 크게·1.25배 길게. 같은 적 45ms 안 중복 무시, 동시 24개 상한. 노드·재질·캐시를 타격마다 만들지 않는다.

| 항목 | 현재 값 | 위치 |
|---|---|---|
| 진입 | `HitSpark.spawn(at, dir, k, enemy, heavy, source)` → `MocoFX.hit` → 스타일 misfitz 면 `MisfitzHit.make` | `hit_spark.gd:21` · `moco_fx.gd:138` |
| 크기 k | source 별: slash/phantom 1.8 · missile 1.5 · parry 2.0 · laser .8 · 그 외 1.0, 하한 `1 + .08·dmg` | `enemy.gd:586-593` |
| 위치 | 판정점을 공격 온 쪽 표면으로 폭×0.4 옮기고 카메라 쪽 0.25m 당김(보스는 `fx_point` 그대로) | `moco_fx.gd:44-45, 157` |
| MISFITZ 시간표 | 0~.033 팝(0.55→1.12배) · ~.10 정점(잔상 2겹·뒤 덩어리·광선 4·픽셀 11) · ~.17 골 파임 · ~.30 소멸(윤곽 파편 3) | `misfitz_hit.gd:17-24, 133-213` |
| 반경 | 몸 폭 × 0.4 (강타 0.52), 폭은 0.8~2.2 로 자름 | `misfitz_hit.gd:22-23, 61` |
| 강타 | 시간 ×1.25 · 크기 ×1.3 · 잔상 3겹 · 픽셀 16 | 〃 |
| 팔레트 | purple(근접): 면 f8d2fa · 테 ff2ee8 · 베벨 c214d6 / yellow(원거리): fff4c4 · ffd21e · e88a00 | `misfitz_hit.gd:30-43` |
| moco 스타일(대안) | 6각/8각 별 + 쐐기 3/4 + 민트 마름모, 70/150/220ms · 강타 70/160/300ms | `moco_fx.gd:38-43, 152-195` |
| 예전(`--vfx=old`) | ToonGunFX 방추 조합(비행접시 .09s · 방추 · 잔물결 · 불똥 4~6) | `hit_spark.gd:53-69` |
| 허수아비 확인 | **8** 스타일 전환 · **Shift+8** 0.2배속 | |

#### 4.5.2 착탄 (기본총)
`GunFX.impact_body(fx_at, fwd, body_color)` (`gun_fx.gd:155-164`): ToonGunFX 별 .07s · 고리 .15s · 연기 2 · 왕관 .32s(9프레임) · 파편 2~3 + 불똥 4k + 몸체색 부스러기 1~3k. 보스·스트림 씬은 `ToonGunFX.view_k` 1.6 으로 키움(카메라가 멀어 작게 보이던 것).

#### 4.5.3 검 궤적 · 충격파 · 왜곡
| 요소 | 현재 값 | 위치 |
|---|---|---|
| 검 궤적 | 호 메시(0.45~2.7m, 150°), mo.co 분기: 흰 앞날 → 마젠타 → 짙은 꼬리, 두께 .19/.29(강타), 잔광 .07/.13초 | `fx.gd:91-140, 552` |
| 칼끝 섬광 | 적중 시 `FX.flash(tip, .4, .035)` + `Distortion.burst(tip, 1.3, .22, .8)` | `sword_combo.gd:817-819` |
| 바닥 원 | 반경 1.9 마젠타 α.1, 0.2초 | `fx.gd:493-533` |
| 충격파 | `FX.shockwave(pos, col, size, dur .35, thick .08)`, 0.2→size cubic-out | `fx.gd:679` |
| 왜곡 | `Distortion.burst(pos, r, dur, str)`: 굴절 22px(800px 기준) · 색수차 2.5 · 게임 시간(히트스톱에 멈춤) | `distortion_fx.gd:39-72, 122` |
| 강타 추가 `_heavy_hit` | 충격파 3.0 · 스파크 16 · `GroundBreak 0.55` · 왜곡 (3.2, .3, 1.2) · `land` 피치 .7 | `sword_combo.gd:904-920` |
| 6타 착지 `_slam_fx` | 충격파 2 · 스파크 26 · 왜곡 (4.6, .38, 1.4) | `:889-900` |
| 지연 참격 마지막 | 왜곡 (3.0, .3, 1.2) · 충격파 · 화면 섬광 .18 | `:883-886` |
| 관통 일격 판정 | 화면 섬광 .35 | `player.gd:1262` |
| 임팩트 프레임 | 흑백 쐐기 1~2프레임: laser 17+17ms(반전) · mega 34+34 · 패링 heavy 17+17 / light 17 | `impact_frame.gd:97-115` |

#### 4.5.4 바닥 파괴 (`GroundBreak`, [ground-break.md](ground-break.md))
강한 공격이 바닥을 깨뜨린다. 기본 스타일 **crumble**(구멍 + 가장자리 판 + 파편), 수명 2.7초, 조각 상한 460 · 연출 30 · 초당 5회. 세기: E 내려찍기 1.0 · 검 강타 0.55 · 미사일 0.3. 효과음 `clank` 저음(피치 .42~.55). 흐르는 씬(WorldFlow)에서는 생략. 돌진·휠윈드가 지나간 자리는 작은 흔적(`trail_mark`, 1.7초, 초당 14).

### 4.6 피해 숫자 (`DamageLog`, [damage-log.md](damage-log.md))

요구사항: 적 **머리 위**(체력바 높이)에 피해량이 크게 튀어나와 0.85~1.2초 읽힌다. 연타는 합산·쌓기로 "413" 덩어리가 되지 않는다. 연속 타격이 이어질수록 색이 달아오른다. **실제 시간**으로 진행(히트스톱에 멈추지 않음). 소품은 숫자 없음.

| 항목 | 현재 값 |
|---|---|
| 크기 | 일반 34 · 강타 54 · 상태 34 px (1280×800 기준, ARCO 글꼴) |
| 수명 | 일반 .95 · 강타 1.2 (BOUNCE .85 / 1.0), 68%(55%)까지 불투명 |
| 팝·눌림 | 1.55 / 강타 1.8배 → .13초, 세로 1.45배 → .08초, 강타 첫 .1초 흰빛 |
| 외곽선 | 글자 × .26(최소 4px) 불투명 남보라 `#1B0B38` + 그림자 |
| 합산 | 같은 대상 0.06초 안 피해는 한 숫자로 더하고 다시 튐(`MERGE`) |
| 프리셋 | **BOUNCE 기본**(70° 부채꼴 470 → 중력 1550 포물선, 쌓지 않음) / STACK(머리 위 기둥, 글자 × .68 간격, 대상당 6) — J 키 · `--dmglog=` |
| 상한 | 24개, 화면 가장자리 안으로 붙임 |
| 연속 타격 열기 | 0.75초 안 연타, 14타에서 최대: 크림 → 연노랑 → 노랑 → 주황 → 붉은 분홍, 외곽선 와인, 주황 후광 α.22, 크기 ×1.1, 팝 +.12(상한 1.9), 첫 .2초 떨림 1.5px |
| 상태 글자 | `STUN!` 민트, 숫자 기둥 위 −44px, 1.1초 (패링 경직에 **새로** 들어갈 때만) |

### 4.7 콤보 미터 (`ComboMeter`, 화면 왼쪽)

요구사항: 모든 피해 확정(`MocoFX.report` 첫 줄, `--vfx=old` 여도)을 세어 타수·랭크·배율·점수를 보여 준다. **게임 시간** 1.2초 창(히트스톱 중 거의 안 줄어 연타 중 끊기지 않음). 연출은 실제 시간.

| 항목 | 현재 값 | 위치 |
|---|---|---|
| 창 | `WINDOW` 1.2초, 2타부터 표시 | `combo_meter.gd:10-12` |
| 점수 | 타격 `round(dmg·10·mult)`, 처치 `150·mult`, 배율 `1 + .5·floor(n/10)` 최대 4 | `:106-127, 174` |
| 랭크 7단계 | 5 NICE · 15 GOOD · 30 GREAT · 50 AWESOME · 80 STYLISH · 120 INSANE · 180 LEGENDARY(무지개) | `:26-34` |
| hit 연출 | 숫자 팝 .55 / big .85 · 기울기 · 흔들림 9/16 · 색 어긋남 · 속도선 2/3 · big 충격 고리 .32초 | `:137-160` |
| kill | 팝 .7 · 흔들림 14 · 민트 고리 .36초 | `:178-181` |
| 끝 | FINISH! 정산 → `Main.score`, `cfinish` 효과음(피치 1 + .06·rank) | `:235-240` |
| 끊김 | 플레이어 피격 → BREAK, 점수 50% 만, 붉은 고리 · 조각 14 · `cbreak` | `:195-207` · `main.gd:901` |
| 랭크업 | 흔들림 20 · 고리 2 · `crank`(피치 1 + .08·rank) | `:250-259` |

예전 처치 콤보 숫자(오른쪽 HUD · CalmHud 콤보 칸)는 숨김. 처치 연쇄 점수(`100·combo·mult`, slash 2 / phantom 3 / parry 3)는 `Main.on_enemy_killed` 에 그대로.

### 4.8 처치 피드백

| 요소 | 현재 값 | 위치 |
|---|---|---|
| 공통 | hitstop .07 · shake .35 · `kill_punch` · `ComboMeter.kill` · 부스터 +0.12 · 드론용 잔해 생성 | `main.gd:827-844` |
| 죽음 연출 선택 | slash/phantom → **SLICED**(0.08초 잘린 채 정지 → 떨어짐, 1.25초) · laser → OVERLOAD 55 / BURST 25 / SHUTDOWN 20% · parry → OVERLOAD 50 / BURST 50% · 그 외 4종 무작위 | `enemy.gd:843-852` |
| 잔해 | `Debris.burst(power, lift, push)`: 조각 상한 220, 수평 power×.5~1.2, 튕김 .38, 수명 1.6~2.5초 + `boom` | `debris.gd:27-179` · `enemy.gd:1042` |
| 보스 | 쇼타임 컷인 / MAMMOTH 전복 연출(별도 문서) | |

### 4.9 사운드 (`sfx.gd`, 전부 코드 합성)

| 상황 | 이름 | 구성 | 호출 예 |
|---|---|---|---|
| 적 피격 | `hit` | 0.06s 노이즈 + 1800Hz | `enemy.gd:568` (−6dB) |
| 검 휘두름 | `slash` | 0.18s | `player.gd:923` |
| 막힘·패링 경직·바닥 파괴 | `clank` | 0.24s 820/1310/2170Hz | `enemy.gd:503`, `ground_break.gd:216` |
| 처치 폭발 | `boom` | 0.55s 110→38Hz | `enemy.gd:1047` |
| 패링 성공 | `parry` | 1.1s 4배음 + 150→42Hz | `parry.gd` (+3/+1dB) |
| 콤보 랭크업 / 정산 / 끊김 | `crank` / `cfinish` / `cbreak` | 0.4 / 0.45 / 0.5s | `combo_meter.gd` |
| 탄피 | `tink` | 0.09s | `gun_fx.gd:360` |

재생 풀 24, 피치 흔들림은 호출마다 지정. **`boost`·`beam` 은 loop 라 단발 타격음으로 쓰지 말 것.**

### 4.10 보스·소품·특수 적 예외

| 대상 | 다른 점 |
|---|---|
| 보스 (`is_boss`) | 넉백·HitReact 없음, 자체 피격 처리, `fx_point` 겉면 연출, 숫자는 맞은 자리 +1.4m, 콤보 마무리 뒤 `BOSS_REST` 0.7초, 궁극기 미사일 몰아주기 |
| 소품 (`prop`) | 숫자·STUN!·처치 수·콤보 처치 점수 없음(타격 콤보는 셈), 봇 표적 제외 |
| 패링 준비 중 적 | 피해만, 넉백·경직 없음, 흰 준비 발광 유지 |
| 장갑 적 | 피해는 들어가나 `blocked` → 콤보 연결 실패, 막힘 스파크 + `clank`, shake .25 |
| 벌레 적 | `BugEnemy` 자체 피격 모션(체액 얼룩 · 움찔), 공통 take_hit 경로는 같음 |
| LANCASTER | 자체 `parry_feel()` light/heavy 로 패링 연출 세기 분기 |

---

## 5. 공격별 타격감 요약표

| 공격 | 피해 | source / 톤 | 강타 | 히트스톱 | 카메라 | 고유 연출 |
|---|---|---|---|---|---|---|
| 기본총 | 1 | bullet / 노랑 | ✗ | — | kick .09, shake .05 | 착탄 왕관·연기·부스러기 |
| 검 1~5타 | 2~6 | slash / 보라 | ✓ | .014~.08 | shake .3+, fov, kick .45 | 궤적·칼끝 섬광·왜곡 |
| 검 6타 낙월 | 14 + 2×6 | slash | ✓ | .13 (+지연 .016/.05) | shake .5 | 착지 충격파·칼자국 6·화면 섬광 |
| 관통 일격 | 20 | phantom / 보라 | ✓ | .12 | shake .6, fov +8/−5 | 일괄 판정·화면 섬광 .35 |
| 레이저 | 3~10 | laser / 노랑 | 4+ 면 ✓ | .06~.094 | shake .3~.75, fov 2~6 | 임팩트 프레임(충전 ≥ .67) |
| 메가 레이저 | 2/틱 | laser | ✗ | .118 | shake .6, fov 9 | 임팩트 프레임 34+34ms·암전 |
| 미사일 | — | missile / 노랑 | ✓ | — | shake .08 | 폭발·바닥 파괴 .3 |
| E 내려찍기 | 8 + 기절 1초 | slash | ✓ | .11 | shake .7, fov −7, kick ↓.6 | 바닥 파괴 1.0·왜곡 |
| 휠윈드 | 3/바퀴 | slash | ✗ (dmg 3) | .025 | — | 회오리 끌림·왜곡 |
| 패링 반격 | 적별 | parry / 보라 | ✓ | 프리셋 .17/.28 | parry_impact·cine | 별빛·임팩트 프레임·줌 블러 |

---

## 6. 끄기·전환 손잡이 (검증·비교용)

| 인자 / 키 | 효과 |
|---|---|
| `--vfx=old` | 예전 피격 섬광(방추)·Label 숫자, 콤보 미터는 그대로 |
| `--hitfx=moco` / 허수아비 **8** · **Shift+8** | 타격 버스트 스타일 · 0.2배속 보기 |
| `--dmglog=stack\|bounce` / **J** | 피해 숫자 프리셋 |
| `--ground=id` / 허수아비 **=** · **Shift+=** | 바닥 파괴 스타일 |
| `--parrystop=id` / 보스방 **P** · **Shift+P** | 패링 히트스톱 프리셋 |
| `Enemy.force_react` | 피격 반응 고정(캡처용) |
| 허수아비 **F2** | UI 전부 숨김(숫자·콤보 포함) |

---

## 7. 검증

- 테스트: `tests/hit_react_check.gd`(반응 5종·연타 이어받기) · `tests/moco_vfx_check.gd`(버스트 생성·상한·숫자 합산·강타 분류·소품 제외·STUN 1회·궤적) · `tests/combo_meter_check.gd`(20항목) · `tests/parry_timing_check.gd` · `tests/ground_break_check.gd` · `tests/leap_slam_check.gd` · `tests/dash_moves_check.gd`. 전체는 `launchers\dev\run_tests.cmd`.
- 캡처 시트: `_capture/hit_react_show.gd` · `misfitz_hit_show.gd` · `damage_log_show.gd` · `combo_meter_show.gd` · `ground_break_show.gd` → `output/*-2026100x/`(`.gdignore`).
- 봇: `powershell -File tools\godot.ps1 wait --fixed-fps 60 res://scenes/training.tscn -- --bot --seconds=40` 으로 ERROR 0 확인.
- 누수: `_capture/leak_probe.gd` 로 `spark` 캐시 0 · 고아 노드 0 유지.
- 체감 판단(히트스톱 길이·숫자 가독성·소리 균형)은 측정으로 끝나지 않으므로 허수아비 씬에서 사용자 확인이 필요하다.

---

## 8. 알려진 불일치 · 미결

1. **`"heavy": true` 를 가진 cut 이 현재 콤보에 없다.** `_heavy_hit`(바닥 파괴 .55 · 충격파 · kick .6)은 코드에 있으나 `_storm()` 6단 어디서도 켜지 않아 실제로는 호출되지 않는다. 강타 분류(VFX·숫자·반응)는 `dmg ≥ 4` 로만 작동 중. 6타 낙월에 켤지 결정 필요.
2. 주석·문서 어긋남: `moco_fx.gd:8` "숫자 최대 20" → 실제 `DamageLog.MAX` 24. `moco-vfx-claude.md` 의 STUN! 700ms → 실제 `LIFE_STATUS` 1.1초. `GroundBreak` 스타일은 6종 + off(문서 "5종").
3. 검 콤보의 실제 박자는 설계 프레임의 2배(`Player.BLADE_SPEED` 0.5). cut 의 `stop` 값은 그대로라 상대적으로 히트스톱 비중이 작아졌다.
4. 기본총 판정 탄도(0.95m)와 시각 총구(약 0.75m)의 0.2m 차는 미해결(`mech_player` 기록).
5. 파티클 캐시 `spark_pm` · `ramp` · `spray` 의 재로딩 증가는 별도 과제([performance.md](performance.md)).
6. 패링 효과음 후보 5차(`output/parry-sound-candidates-20261002/v5/`)는 사용자 선택 대기, 현재 `parry` 합성음 그대로.
