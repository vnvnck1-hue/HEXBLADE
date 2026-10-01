# HEXBLADE 사운드와 BGM 제작 리서치

작성일·정보 확인일: 2026-10-01 KST · 1차 조사 · 음악 제작과 게임 적용 전 단계

이 문서는 사용자가 지정한 [Moebius FM](https://www.youtube.com/@moebiusfm)의 음악적 방향을 정리하고, 그 계열의 음악을 HEXBLADE의 로비·전투·보스전에 맞게 제작하는 방법을 비교한다. 현재 권고는 **몽환적인 Synthwave를 기본 정서로 삼고, 전투에서 리듬과 저음의 추진력을 더하는 것**이다. 제작은 **Suno와 Stable Audio의 후보곡 비교 → DAW 편집 → 게임 안에서 반복 청취** 순서가 현실적이다. DAW는 오디오와 악기 트랙을 편집하는 음악 제작 프로그램이다.

이 권고는 공개 자료와 프로젝트 구조를 바탕으로 한 제작 가설이다. 도구별 음질 순위를 실험으로 확정한 결과는 아니다. 지금 결정할 것은 서비스의 최종 구매나 전체 OST 목록이 아니라, 어떤 음악을 어떤 기준으로 청취할지다.

## 조사 범위와 근거의 한계

- **확인한 것:** 채널 영상의 검색 색인에 보존된 공식 설명과 트랙 목록, 창작자 프로필, 장르 관련 제작자 자료, 도구의 공식 기능·가격·약관, 게임의 현재 오디오 코드.
- **확인하지 못한 것:** 원음 직접 청취, BPM·조성·주파수·라우드니스 측정, Moebius FM의 실제 DAW 세션과 음악 생성 도구. YouTube 채널 및 영상 본문 직접 가져오기가 실패해 색인된 설명을 활용했다.
- 따라서 아래 음색 설계·BPM·코드 진행·게임별 배치는 **우리 게임을 위한 제안**이다. 특정 Moebius FM 곡을 채보하거나 측정한 결과로 읽으면 안 된다.
- 가격은 확인일의 공개 표시값이다. 연간 결제 환산액과 월 결제액을 구별했고, 확인되지 않은 가격은 비워 두었다. 회사 명의 사용 조건을 개인 플랜 조건과 동일하게 간주하지 않는다.

사용자가 가장 좋아하는 영상·구간은 아직 지정되지 않았다. 우선 채널의 공통 설명을 기준으로 잡되, 나중에 선호곡 2~3개가 정해지면 장르 비중과 공격성을 다시 조정한다.

## 1 Moebius FM은 어떤 음악인가

### 채널에서 직접 확인되는 방향

공식 영상 설명은 Synthwave, Retrowave, Outrun, Cyberpunk, Chillwave를 나열한다. 복고 신시사이저, 맥동하는 베이스, 몽환적인 멜로디, 밤 운전·집중·휴식·향수를 함께 강조한다. 따라서 검색용으로 가장 넓고 정확한 출발점은 **Synthwave / Retrowave**이고, 원하는 감정에 접근하는 보조어는 **dreamy, atmospheric, nostalgic, late-night**다. [공식 영상 설명과 트랙 목록](https://www.youtube.com/watch?v=HpyVBF03vI8)

세부적으로 **Dreamwave / Chillsynth에 가까운 부드러운 방향을 먼저 시험**할 것을 제안한다. 이는 채널 전체를 청취해 확정한 하위 장르 판정이 아니라, 공식 설명의 몽환성·휴식성에서 도출한 가설이다. 레트로 신스 레이블 NewRetroWave는 Chillsynth를 느긋하고 공간감 있는 신스 중심의 흐름으로 설명하며, 로파이 팝 성향의 Chillwave와 구별한다. [Chillsynth 소개와 제작자 인터뷰](https://newretrowave.com/2020/11/12/meet-the-latest-synth-micro-genre-chillsynth/)

### 용어별 의미와 우리 게임에서의 용도

장르 경계는 고정 규격이 아니다. 특히 유튜브의 긴 장르 나열은 발견을 돕는 태그이기도 하므로, 모든 태그가 모든 수록곡에 똑같이 적용된다고 해석하지 않는다.

| 용어 | 제작 관점에서 이해할 특징 | HEXBLADE에서의 제안 |
|---|---|---|
| Synthwave | 1980년대 신스 음악의 어법을 현대적으로 재구성. 드럼머신·반복 신스·공간감 | 전체 음악의 기본 언어 |
| Retrowave | Synthwave와 겹치는 복고 지향 명칭. 엄격히 분리된 작곡 규칙은 아님 | 검색과 시안 설명에 함께 사용 |
| Dreamwave / Chillsynth | 부드러운 패드, 몽환성, 여유 있는 반복. 둘을 완전한 동의어로 단정하지 않음 | 로비·귀환·캐릭터 정서의 우선 후보 |
| Chillwave | 로파이 팝·몽환적 처리와 연관. 채널에서는 넓은 분위기 태그로도 사용 | `instrumental`과 악기 묘사를 함께 넣어 방향 제한 |
| Outrun | 전진감·야간 주행 감각을 지시하는 데 유용한 Synthwave 계열 표현 | 일반 전투와 이동의 추진력 |
| Vaporwave | 재맥락화된 샘플·늘어진 시간감·낡은 매체의 분위기와 연관 | 전투 전체보다 메뉴·기억·회복 구간의 질감 후보 |
| Darksynth | 어둡고 거친 신스·왜곡·강한 타격을 지시하는 표현 | 보스에서 제한적으로 확장할 후보. 채널 전체의 장르로 확정하지 않음 |
| Cyberpunk | 미래 도시·기계·디스토피아의 미학. 이 단어만으로 리듬과 악기가 정해지지 않음 | 장르 뒤에 붙이는 세계관 수식어 |

Synthwave의 역사·기본 제작 어법은 [Native Instruments 제작 튜토리얼](https://blog.native-instruments.com/synthwave/), Chillwave와 Chillsynth의 차이는 [NewRetroWave의 현장 설명](https://newretrowave.com/2020/11/12/meet-the-latest-synth-micro-genre-chillsynth/)을 참고했다. 표의 게임 배치는 이 문서의 제안이다.

핵심은 **복고적인 전자 악기의 따뜻함과 미래적인 고독감을 함께 유지하는 것**이다. 처음부터 `aggressive cyberpunk EDM`을 중심으로 입력하면, 사용자가 좋아한 몽환성이 약해지는 후보가 나올 수 있다. 이 여부를 초기 비교 시청에서 확인한다.

### 첫 비교 청취에 쓸 실제 구간

다음 시간은 공식 설명에 기재된 트랙 시작점이다. 아직 해당 구간의 악기나 정서를 직접 분석한 것은 아니다. 같은 영상 안의 세 구간으로 시작하면, 서로 다른 채널의 마스터링 차이에 영향을 덜 받으며 취향을 설명할 수 있다.

| 참조 구간 | 설명에 기재된 곡명 | 다음 청취 때 기록할 항목 |
|---|---|---|
| [00:00](https://www.youtube.com/watch?v=HpyVBF03vI8&t=0s) | Startup Sequence | 도입 길이, 첫 리듬 진입, 로비에 필요한 여유 |
| [05:30](https://www.youtube.com/watch?v=HpyVBF03vI8&t=330s) | Memory Not Found | 멜로디 존재감, 베이스 반복, 가장 마음에 드는 음색 |
| [21:01](https://www.youtube.com/watch?v=HpyVBF03vI8&t=1261s) | Ghosts of Data | 질감과 밀도 차이, 오래 들을 때의 피로 |

각 구간에서 45~60초를 골라 `좋은 요소 3개 / 덜 원하는 요소 1개 / 게임에서 어울리는 장면`을 기록한다. 제목에 있는 연도나 시각 이미지로 실제 녹음 시대·장비를 추정하지 않는다.

### Moebius FM도 AI로 만드는가

현재 근거로는 **음악 제작 도구를 확정할 수 없다.** 창작자의 Ko-fi 소개는 AI를 활용해 SF 애니메이션 아트를 만든다고 명시하지만, 이것은 이미지에 관한 설명이다. 음악까지 같은 방식으로 만든다는 증거는 아니다. [창작자 Ko-fi](https://ko-fi.com/moebiusfm)

MusicBrainz에는 `ai generated`, `suno`, `suno ai` 태그가 있지만 이는 커뮤니티 등록 정보다. 창작자의 공식 제작 설명을 대신하지 못한다. 따라서 “이 채널은 Suno로 만들었으니 같은 도구를 쓰면 된다”는 결론은 채택하지 않는다. [MusicBrainz 등록 정보](https://musicbrainz.org/artist/17ba2b94-8dd2-4c84-b2bc-75eeff0373ee?all=1)

## 2 원하는 사운드를 제작 언어로 바꾸기

아래는 특정 곡의 복제가 아니라 **독자적인 HEXBLADE 시안을 위한 레시피**다. 수치는 시험 출발점이며 장르의 필수 조건이 아니다.

| 구성 요소 | 첫 시안의 설정 제안 | 게임에서 확인할 문제 |
|---|---|---|
| 드럼 | 단단한 킥, 짧은 스네어, 절제된 하이햇. 스네어 잔향은 짧게 끊기 | 총성과 스네어가 겹쳐 공격 피드백이 흐려지지 않는가 |
| 베이스 | 짧은 톱니파·사각파 계열, 8분음표 중심 반복, 필요한 곳만 16분음표 | 킥·폭발·부스터와 저음이 한 덩어리가 되지 않는가 |
| 코드와 패드 | 디튠한 아날로그풍 신스, 코러스, 느린 필터 변화, 긴 여운 | 전투 경고음을 덮을 만큼 넓고 두껍지 않은가 |
| 멜로디 | 짧은 3~5음 모티프, 긴 쉼표, 부드러운 어택 | 반복 청취 때 피로하거나 보컬처럼 주의를 빼앗지 않는가 |
| 아르페지오 | 코드를 음별로 풀어 반복. 8분·16분 패턴을 강도에 따라 추가 | 고음 반복이 미사일 락온·패링 신호와 혼동되지 않는가 |
| 질감 | 약한 테이프 포화·피치 흔들림·노이즈. 배경 레이어에만 제한 적용 | 의도적인 질감과 생성 오류·음질 저하를 구별할 수 있는가 |
| 공간 | 패드는 넓게, 킥·서브베이스는 중앙에 두는 시안 | 모노 재생과 작은 스피커에서도 핵심이 남는가 |

시작용 코드 진행은 `Am–F–C–G`처럼 단순하게 두고, 사람이 만든 짧은 모티프를 로비·전투·보스에서 악기와 리듬만 바꿔 재사용할 수 있다. 이는 채널 곡의 채보 결과가 아니다. 동일한 멜로디 자산을 변주하면 무작위로 생성한 여러 곡보다 게임의 정체성을 유지하기 쉽다는 제작 판단이다.

신스 음색 제작은 디지털 플러그인으로도 가능하다. Ableton의 Synthwave 팩은 아날로그·디지털 드럼머신 샘플, Wavetable 신스, 베이스·패드·리드·SF 효과음을 함께 사용하는 사례다. 하드웨어 빈티지 악기 구입을 시작 조건으로 삼을 필요는 없다. [Ableton Synthwave 팩](https://www.ableton.com/en/packs/synthwave/)

## 3 현대적인 제작 방법 비교

여기서 말하는 현대적 방법은 현재 도구가 지원하는 작업 방식이다. 각 방식의 시장 점유율이나 업계 사용률을 조사한 것은 아니다.

**스템**은 드럼·베이스·패드 등 악기군별로 나눈 오디오 파일이고, **MIDI**는 음높이·길이·세기 등의 연주 데이터다. MIDI에는 완성된 악기 음색이 들어 있지 않으므로 가상악기로 소리를 입힌다. AI가 완성곡에서 추출한 스템과 MIDI는 원래 제작 세션의 트랙·악보와 같다고 보장되지 않는다.

| 방식 | 실제 작업 | 장점 | 주된 비용과 한계 |
|---|---|---|---|
| DAW에서 직접 작곡 | MIDI로 음·리듬 작성 → 가상악기로 음색 설계 → 편곡·믹스 | 멜로디·템포·스템·반복 구간을 정밀하게 통제 | 음악 제작 시간과 숙련도 |
| 작곡가와 협업 | 레퍼런스와 큐 목록 전달 → 시안 → 변주·스템 납품 | 전체 OST의 통일성과 장면별 수정에 유리 | 별도 견적. 편곡 수정·OST 발매·스템 범위를 계약에 명시 |
| 라이선스 샘플 활용 | 드럼·질감 루프에 직접 만든 코드·멜로디 결합 | 빠르게 일정 수준의 음색 확보 | 루프의 반복 인상, 샘플별 사용 조건 |
| AI 전체곡 생성 | 설명 입력 → 여러 후보 생성 → 선택 | 취향과 분위기 탐색이 빠름 | 정확한 마디·곡 구조·반복·동일 주제의 변주가 보장되지 않음 |
| AI와 DAW 결합 | AI 초안 → 좋은 구간 선택 → 드럼·베이스 교체 → 루프·변주 제작 | 속도와 편집 통제의 균형 | 스템 분리 오류와 후반 편집 시간을 고려해야 함 |
| 로컬 AI | 모델 설치 → 고정된 입력·시드로 반복 생성 → DAW 편집 | 로컬 파일 관리와 대량 실험에 유리 | GPU·설치·모델별 라이선스·버전 관리 |

**우리 프로젝트에는 AI와 DAW 결합을 우선 권고한다.** 음악 한 곡을 멋지게 만드는 것과, 같은 전투를 20분 해도 편하게 들리는 루프를 만드는 것은 서로 다른 작업이다. AI가 만든 전체 믹스를 바로 채택하기보다 전투·경고음과 함께 들으며 편집하는 단계가 필요하다.

### 최소 도구 구성

- **편집 중심:** REAPER. 공개 가격은 할인 라이선스 US$60, 상업 라이선스 US$225이며 60일 평가를 제공한다. 할인 상업 이용은 연 매출 US$20,000 이하 등 자격 조건이 있다. 회사 업무라면 개인 취미 사용 조건을 적용하지 않는다. [공식 구매 조건](https://www.reaper.fm/purchase.php)
- **추가 비용 없는 신스 후보:** Surge XT. 오픈소스 신스이며 다양한 발진기·필터·코러스·딜레이·리버브를 제공한다. 우리 레시피의 베이스·패드·리드를 시험하기에 충분한 후보로 판단한다. [공식 기능](https://surge-synthesizer.github.io/)
- **빈티지 음색을 더 빠르게 잡는 선택지:** TAL-U-NO-LX 같은 전용 신스. 처음부터 구입하기보다 무료 후보로 부족한 음색이 무엇인지 확인한 뒤 선택한다. [공식 제품](https://tal-software.com/products/tal-u-no-lx)

이미 익숙한 DAW가 있다면 그것을 우선 사용한다. 도구 교체보다 루프 편집·악기별 내보내기·레벨 조정이 가능하다는 점이 더 중요하다.

## 4 AI 도구별 조사

다음 평가는 **공개 기능과 게임 제작 적합성에 대한 판단**이다. 같은 프롬프트로 음원을 생성해 비교한 실측 순위가 아니다. 모든 후보에 대해 이 장르를 지원한다는 사실과 사용자가 좋아할 결과가 나온다는 사실을 구분해야 한다.

| 도구 | 이번 작업에서 시험할 역할 | 내보내기와 편집의 확인 사항 | 선택 판단 |
|---|---|---|---|
| Suno | 완성곡에 가까운 취향 시안 | 유료 스템 분리, Premier의 Studio, 다운로드 수 제한 | 접근하기 쉬운 1차 후보 |
| Stable Audio 3.0 | 연주 BGM·패드·사운드 질감 | 로컬 모델과 API, 부분 수정·연장, 모델별 배포 조건 | Suno와 함께 비교할 1차 후보 |
| ACE-Step 1.5 | 로컬 반복 실험·변형 | 공개 모델, MIT 표시, 로컬 실행 환경 필요 | 로컬 제작이 필요할 때 후보 |
| Eleven Music | 구간별 구성 제어 | WAV·스템 기능은 플랜별, Studio Games 제한 | 게임 계약 범위 확인 후 후보 |
| AIVA | MIDI·작곡 구조 확보 | MIDI 편집·내보내기, 상업 범위는 플랜별 | 음표를 직접 다듬으려면 후보 |
| Beatoven.ai | 배경음악 공급 | MP3/WAV, 게임 동기화 사용 허용, 비독점 | OST 단독 발매가 중요하지 않을 때 후보 |
| Google Lyria | API 기반 저비용 시안 | Gemini와 Cloud의 모델·포맷·약관 구분 필요 | 기술 실험용 보조 후보 |
| Udio | 서비스 내부 음악 탐색 | 공식 도움말에 오디오·비디오·스템 다운로드 중단 | 현재 게임 납품용에서는 제외 |

각 행의 출처와 조건은 바로 아래에 정리했다.

### Suno

확인일 가격표는 유료 모델로 v6·v6-wild, 무료 모델로 v6-mini를 표시한다. 연간 결제 시 월 환산액은 Pro US$8, Premier US$24이며 세금은 별도다. 각각 월 2,500·10,000 크레딧과 일반 곡 다운로드 20·60회를 표시한다. **이 숫자는 생성 횟수와 다운로드 횟수를 구별해서 읽어야 한다.** 월 단위 결제를 한다면 결제 화면의 금액을 다시 확인한다. [공식 가격표](https://suno.com/pricing)

Pro도 Auto Split과 특정 악기 분리를 사용할 수 있다. Premier는 Studio와 Advanced Split을 제공한다. Studio는 WAV 전체곡·선택 구간·멀티트랙 내보내기와 스템에서 MIDI 추출을 안내한다. 추출 MIDI는 원래의 완벽한 악보라는 보장이 없으므로 사람이 수정할 작업물로 취급한다. [스템 도움말](https://help.suno.com/en/articles/13925185), [Studio 내보내기](https://help.suno.com/en/articles/13925249)

**2026년 9월 변경을 반영해야 한다.** 현재 약관상 상업 이용에는 공식 경로의 허용된 다운로드가 필요하다. 무료 결과물은 비상업 용도이고, 다른 이용자와의 Remix는 별도 제한이 있다. 공식 공지는 Premier의 Studio 스템·샘플 다운로드에는 제한이 없다고 설명한다. 일반 곡의 60회와 Studio 예외를 섞어 “모든 다운로드 무제한”으로 설명하면 안 된다. [변경 공지](https://www.suno.com/blog/suno-updates-tos), [현재 약관](https://suno.com/terms)

**제안:** 먼저 짧은 후보들을 서비스 안에서 비교하고 채택 후보만 내려받는다. 게임용 최종 후보는 유료 이용과 공식 다운로드 증빙이 명확한 상태에서 제작·확보한다. 무료 생성곡의 사후 업그레이드 권리는 이전 도움말과 최근 공지의 표현이 다를 수 있으므로 자동 소급을 가정하지 않는다.

### Stable Audio 3.0

공식 발표는 연주 음악·효과음용 모델군, Small 계열과 Medium의 공개 가중치, Large의 API 접근, 부분 수정과 연장을 안내한다. Medium은 최대 6분 20초를 안내한다. 라이선스된 데이터로 학습했다는 설명은 공급자의 공식 설명이며, 이 조사가 데이터 전체를 감사한 것은 아니다. [모델 발표](https://stability.ai/news-updates/meet-stable-audio-3-the-model-family-built-for-artistic-experimentation-with-open-weight-models)

API 가격표의 Stable Audio 3.0은 요청당 26크레딧, 1크레딧은 US$0.01이므로 표시 기준 **US$0.26/요청**이다. 웹 앱 구독·로컬 실행 비용과 다른 가격이다. [API 가격표](https://platform.stability.ai/pricing)

로컬 Community License는 조직과 관계사의 매출 조건을 확인해야 한다. 약관은 상업 이용 등록, 연 매출 US$1M 기준, 산출물과 모델 배포의 구분을 둔다. 회사에서 쓰는 모델을 “내 프로젝트 매출이 아직 0이므로 무료”라고 단정하지 않는다. 회사 조건이 맞지 않으면 Enterprise 계약을 검토한다. 산출물 권리와 비침해 보증도 같은 개념이 아니다. [Community License](https://stability.ai/community-license-agreement), [적용 모델 목록](https://stability.ai/core-models)

**제안:** 보컬이 필요 없는 BGM, 긴 패드, 기계·생체 질감에 우선 시험한다. 프롬프트는 장르·악기·정서·구조를 명시하고, 음악과 효과음 생성을 구분한다. 완성 믹스에서 깨끗한 스템을 뽑아 주는 기능과 악기 하나의 새 소리를 생성하는 기능은 구별한다. [공식 프롬프트 가이드](https://stability.ai/guides/stable-audio-3-prompt-guide)

### ACE-Step 1.5

공식 저장소와 모델 카드가 로컬 음악 생성과 편집 기능을 공개하며 MIT 라이선스를 표시한다. 모델 카드는 상업 사용 가능 및 학습 데이터 구성에 대한 개발팀의 설명을 제공한다. 이는 서비스 월 구독 없이 로컬 실험할 후보라는 근거이며, 타인 곡과 유사한 모든 산출물이 자동으로 안전하다는 뜻은 아니다. [공식 저장소](https://github.com/ace-step/ACE-Step-1.5), [모델 카드](https://huggingface.co/ACE-Step/Ace-Step1.5)

현재 저장소는 XL 모델을 포함하고, XL에 오프로딩 시 12GB 이상 VRAM·20GB 이상 권장을 표시한다. 작은 모델과 XL 요구 사양을 섞지 않는다. 이 PC의 모델별 속도·메모리 사용량은 시험하지 않았다.

**제안:** 초기 취향 선택은 웹 도구로 진행하고, 후보가 많이 필요하거나 로컬 보관·자동화가 중요해지면 비교한다. 설치 시간을 지불하면서까지 쓸지는 채택 가능한 시안 비율로 판단한다.

### Eleven Music

Music v2와 API는 자연어 기반 곡 생성, 구간별 구성·수정, 플랜별 스템과 내보내기를 안내한다. 따라서 장면의 길이와 구성을 제어할 후보로 가치가 있다. [공식 Music](https://elevenlabs.io/music), [공식 API 소개](https://elevenlabs.io/eleven-music-api)

하지만 모델별 약관에서 **Studio Games는 수익화되고 둘 이상의 플랫폼으로 제공되는 비디오게임**으로 정의한다. Self-Serve와 Enterprise Music Lite의 매체 권리에서 Studio Games를 제외하고, Enterprise Music에는 전 매체 이용을 표시한다. “인디 게임이면 무조건 일반 유료 플랜으로 된다”는 결론을 내릴 수 없다. 개인용 플랜과 조직의 직원 수 조건도 따로 있다. [모델별 약관과 권리 표](https://elevenlabs.io/eleven-music-model-specific-terms)

**제안:** 게임의 배포 플랫폼·수익화·계약 주체에 맞는 권리가 확인된 경우에 비교한다. 제품 페이지와 약관의 생성 분량 표가 다르게 보이는 부분도 있어 이 문서에서는 정확한 기업 견적을 산정하지 않는다. Music의 제한을 별도 Sound Effects 제품에 그대로 적용하거나, 반대로 SFX 조건을 Music에 적용하지 않는다.

### AIVA

오디오·MIDI 영향 입력, 생성곡 편집, MIDI 내보내기를 제공한다. 개인용 연간 결제 표시에서 Standard는 월 환산 €11, Pro는 €33이며 VAT 별도다. Standard 수익화는 지정된 소셜 플랫폼에 한정되고 Pro는 제한 없는 수익화와 권리 양도를 안내한다. **상업 게임용으로 Standard를 선택하는 것은 적절하지 않다.** [가격·기능](https://www.aiva.ai/)

약관은 직원 3명 이상이면서 전년도 매출 US$300k 초과인 사업체를 Enterprise로 정의하고 별도 계약을 요구한다. Pro의 권리 양도 표현도 모든 국가에서 AI 결과의 법적 저작권 성립을 보증하는 것으로 확대 해석하지 않는다. [AIVA 약관](https://www.aiva.ai/legal/1)

**제안:** Moebius FM의 완성 음색을 즉시 얻는 도구보다는, 수정 가능한 음표·화성 골격을 얻고 DAW에서 직접 음색을 입히는 경로로 비교한다.

### Beatoven.ai

공식 사이트는 게임을 사용처에 포함하고 MP3/WAV 다운로드를 안내한다. 약관은 게임 등 콘텐츠와 결합해 사용하는 비독점 라이선스를 부여하며, 가능한 경우 크레딧 표기를 요구한다. 단독 음악 파일 판매·스트리밍 배포는 제한한다. 그래서 **게임 안에서 재생하는 BGM과 별도 OST 앨범 판매는 다른 판단**이다. [제품 FAQ](https://www.beatoven.ai/), [약관 6장](https://www.beatoven.ai/tos)

공식 가격 링크는 이번 접근에서 404로 확인돼 정확한 현행 비용을 인용하지 않았다. 일부 기존 공식 페이지에 스템 다운로드 안내가 있지만, 현행 모델·플랜별 제공 여부는 구매 전 확인할 항목으로 남긴다.

**제안:** 배경용 음악 공급에는 비교할 수 있다. 독점적인 게임 주제곡과 OST 사업까지 계획한다면 권리 범위 때문에 우선순위를 낮춘다.

### Google Lyria

Gemini API 문서는 Lyria 3.5의 수분 길이 음악과 44.1kHz 스테레오 MP3 출력을 안내한다. 가격표는 곡당 US$0.08, Lyria 3의 30초 클립은 US$0.04를 표시한다. 낮은 표시 비용은 다양한 방향의 초안을 시험하기에 매력적이다. 다만 자동 루프·스템 납품 여부를 이 가격에서 추정하지 않는다. [생성 문서](https://ai.google.dev/gemini-api/docs/music-generation), [가격표](https://ai.google.dev/gemini-api/docs/pricing)

Google Cloud의 Lyria 3 문서는 해당 Preview의 상업·프로덕션 이용을 약관 조건 아래 허용한다고 설명한다. 이는 Gemini 앱의 모든 이용 형태나 Lyria 3.5 계약을 검증한 근거가 아니다. 채택 시 **어느 제품의 어떤 모델을 쓰는지** 확정해 그 약관을 확인한다. [Cloud Lyria 3 문서](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/lyria/lyria-3)

**제안:** API를 활용한 시안 비교용 보조 후보. MP3를 WAV로 변환해도 원래 없던 음질이 복원되는 것은 아니므로, 최종 편집 소스로서의 한계도 평가한다.

### Udio

공식 도움말은 UMG 제휴 이후 **오디오·비디오·스템 다운로드가 중단**됐다고 명시한다. 도움말 표기일은 2026-02-17이며 이번 조사 시점에도 같은 안내를 확인했다. [Udio 공식 안내](https://help.udio.com/en/articles/12683565-changes-associated-with-the-universal-music-group-umg-partnership)

**판단:** 현재 게임에 넣을 파일을 확보하는 주 제작 도구로 추천하지 않는다. 서비스 내부 청취 품질과 게임 에셋 납품 가능성은 별개다. 이전의 다운로드 가능 시절 리뷰를 현재 기능으로 인용하지 않는다.

## 5 HEXBLADE에 적용할 음악 방향

### 현재 프로젝트에서 확인한 상태

공통 효과음은 [scripts/sfx.gd](../scripts/sfx.gd)에 있으며, 22,050Hz·16비트·모노 WAV를 코드로 합성한다. 16개의 AudioStreamPlayer 풀에서 빈 플레이어를 찾고, 모두 사용 중이면 새 재생 요청은 반환값 null로 끝난다. 사격·피격·충전·대시·패링·승패 신호 등이 존재한다. [main.gd](../scripts/main.gd)와 [lobby.gd](../scripts/lobby.gd)는 각자 Sfx를 생성한다.

맘모스 죽음 연출에는 전용 오디오 모듈도 있다. 조사한 scripts·scenes·project.godot 범위에서 별도 BGM 관리자, 음악 클립 전환, Music/SFX 버스 분리는 확인되지 않았다. 따라서 BGM을 추가할 때는 현재 합성 SFX의 음색만 바꾸는 것과 음악 재생 체계를 마련하는 것을 따로 계획해야 한다.

### 장면별 음악 큐 제안

아래 BPM과 시간은 모두 설계 제안이다. 구출·회복의 일부 장면은 내러티브 문서 단계이며 현재 구현된 기능으로 간주하지 않는다.

| 장면 | 정서와 음악 방향 | 첫 시험 BPM | 필요한 납품 형태 |
|---|---|---:|---|
| 로비·격납고 | Dreamwave / Chillsynth, 고요한 기계와 남아 있는 온기 | 84~96 | 60~120초 반복, 드럼 없는 버전 |
| 섹터 준비·이동 | Atmospheric Synthwave, 기대와 긴장 | 100~112 | 저강도 루프, 전투 전환 구간 |
| 일반 전투 | Outrun 성향, 일정한 추진력과 선명한 박자 | 112~124 | 동일 템포의 저·중·고강도 변주 |
| MAMMOTH | 무게 있는 신스 베이스, 추격감, 압박 | 112~128 | 등장·본전·위기·종료 큐 |
| VULCAN | 금속성 리듬과 열기, 제한된 왜곡 | 120~132 | 페이즈 변주와 종료음 |
| 심연 성소 | Dark Ambient와 신스의 결합, 불안한 유기적 질감 | 88~108 또는 무박 | 드론·박자 레이어 분리 |
| 구출·회복·귀환 | 로비 모티프의 부드러운 재등장 | 76~92 | 짧은 감정 큐와 조용한 반복 |
| 승리·실패 | 테마를 요약한 짧은 음악 신호 | 곡과 연계 | 2~5초 종료 스팅어 |

모든 장면을 서로 다른 장르로 만들기보다는 같은 신스·모티프·공간감을 유지하고 강도만 바꿔 본다. 보스에서도 멜로디의 정서를 남기면 메카 액션과 파일럿 서사를 함께 표현할 수 있다는 제안이다.

### 게임용 음악을 만드는 두 방식

**가로 전환**은 탐색곡에서 전투곡으로 넘어가는 방식이다. 다음 마디나 정해 둔 구간에 맞춰 전환하면 갑작스러운 단절을 줄일 수 있다. **세로 레이어**는 같은 음악 위에 드럼·베이스·위기 패턴을 추가하는 방식이다. 후자는 같은 BPM·조성·마디 수·시작점으로 제작해야 한다.

AI에 `low`, `medium`, `high` 세 곡을 따로 요청하면 서로 다른 화성과 길이가 나올 수 있다. 처음에는 **한 곡에서 만든 동일 길이 변주 3개**를 우선한다. 완성 믹스에서 분리한 스템은 다른 악기 잔재가 섞일 수 있으므로, 반복해서 끄고 켤 중요한 드럼·베이스는 MIDI나 직접 제작한 소리로 교체하는 방안도 둔다.

Godot는 클립·전환 규칙을 다루는 AudioStreamInteractive와 여러 스트림을 동기 재생하는 AudioStreamSynchronized를 제공한다. 이 구조가 첫 검토 대상이며, 당장 외부 오디오 미들웨어를 도입할 필요가 있는지는 시안으로 판단한다. 문서는 stable 문서 기준이며 실제 적용 때 프로젝트 고정 버전 4.7.2에서 동작을 확인한다. [Interactive](https://docs.godotengine.org/en/stable/classes/class_audiostreaminteractive.html), [Synchronized](https://docs.godotengine.org/en/stable/classes/class_audiostreamsynchronized.html)

## 6 효과음과 음악의 공존

BGM은 세계의 정서를 만들고, 효과음은 행동과 위험을 전달한다. 따라서 중요한 경고가 음악에 묻히면 음악의 단독 청취 만족도와 관계없이 수정해야 한다.

| 소리 그룹 | 제작 방향 제안 | AI를 쓸 부분 |
|---|---|---|
| 기본총·검 | 짧은 시작음 + 몸통 타격 + 에너지 잔향의 층으로 구성 | 원재료 질감 후보. 최종 시작 시점과 길이는 직접 편집 |
| 패링 예고·판정 신호 | 다른 소리와 구별되는 고정 음색과 길이 | 자동 생성보다 일관된 합성·편집을 우선 |
| 충전·빔·부스터 | 시작·유지 루프·종료를 분리하고 강도에 따라 변형 | 기계음·플라스마 질감 |
| 생체 변이·적 | 젖은 조직·금속 마찰·불규칙 진동을 조합 | 특수한 질감의 후보 생성 |
| 환경 | 격납고 환기·전력·멀리 들리는 기계, 심연의 공기 | 긴 배경음과 루프 후보 |
| UI | 세계관과 맞는 짧고 절제된 확인·취소·보상음 | 직접 합성과 소수 변주 |

Stable Audio의 SFX 모델, ElevenLabs Sound Effects를 효과음 원재료 후보로 검토할 수 있다. ElevenLabs SFX 문서는 최대 30초와 루프 생성, 비루프 효과의 48kHz WAV를 안내한다. 실제 채택 시 SFX 제품의 이용 조건을 따로 확인한다. [Stable Audio 제품군](https://stability.ai/stable-audio), [ElevenLabs SFX 문서](https://elevenlabs.io/docs/overview/capabilities/sound-effects)

게임 내 믹스 구조는 `Master / Music / SFX / UI / Ambience` 분리를 제안한다. 패링·치명적 위험 신호가 날 때 음악을 잠시 낮추는 덕킹을 시험하고, 사격마다 전체 음악이 출렁이지 않도록 조정한다. 음악 내부 킥과 베이스의 사이드체인 압축과 게임 이벤트에 의한 덕킹은 다른 층의 작업이다. [Godot 오디오 버스](https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html)

현재 효과음 풀에서 재생 요청이 누락될 수 있으므로, 향후 중요한 위험 신호에 우선순위나 예약 재생 채널을 둘 필요가 있는지 점검한다. 이번 문서 작업에서는 코드를 변경하지 않았다.

## 7 바로 시험할 프롬프트

다음 프롬프트는 우리 게임용으로 작성한 신규 시안 지시문이다. Moebius FM의 이름이나 음원을 입력하는 대신 장르·악기·감정·구조를 기술한다. 아티스트 이름을 제한하는 서비스에서도 옮겨 쓰기 쉽다. 영어 사용은 도구 간 비교를 위한 선택이며, 반드시 한국어보다 우수하다고 검증한 것은 아니다.

Audio-to-audio나 참조 업로드를 활용할 때는 직접 만든 짧은 모티프 또는 해당 용도의 권한을 확보한 음원을 쓴다. Moebius FM을 청취 레퍼런스로 삼는 것만으로 생성 서비스에 원곡을 업로드할 권한까지 확보되는 것은 아니다. Suno와 AIVA도 업로드 입력에 필요한 권리를 사용자에게 요구한다. [Suno 약관](https://suno.com/terms), [AIVA 약관](https://www.aiva.ai/legal/1)

### 공통 음색 기준

```text
Instrumental atmospheric synthwave with a dreamy retro-futuristic mood.
Warm detuned analog-style pads, rounded pulsing synth bass, restrained drum
machine groove, sparse memorable melodic motifs, gentle chorus and tape color.
Melancholic but hopeful, spacious and focused, suitable for a sci-fi action game.
No singing, no spoken voice, no choir. Keep space for gameplay sound effects.
```

### 로비 시안

```text
Instrumental dreamwave and chillsynth, 90 BPM, 4/4, A minor.
A quiet futuristic hangar after midnight, a feeling of solitude and recovery.
Warm pads, soft plucked synth melody, rounded bass, light electronic drums.
A short original recurring motif, gradual changes, restrained high frequencies.
Aim for a steady 32-bar section with a short intro and no dramatic final cadence.
No vocals, no aggressive drop, no heavy distorted bass.
```

### 일반 전투 시안

```text
Instrumental melodic outrun synthwave, 120 BPM, 4/4, A minor.
Focused forward momentum for a fast isometric mech shooter.
Tight drum machine hits, pulsing eighth-note bass, restrained sixteenth-note arps,
warm background pads, a sparse heroic-but-melancholic synth motif.
Maintain a stable groove with minimal breakdowns and no tempo changes.
Keep the lead and cymbals restrained so weapon sounds remain clear.
No vocals, no choir, no long build-up, no festival EDM drop.
```

### 보스 시안

```text
Instrumental dark melodic synthwave, 124 BPM, 4/4, A minor.
A massive biomechanical war machine approaches through an industrial arena.
Heavy controlled synth bass, metallic percussion accents, tense arpeggios,
wide dark pads and a restrained emotional lead motif.
Escalate through percussion and harmony while keeping a stable rhythmic grid.
No vocals, no continuous noise wall, no abrupt tempo changes.
```

### 부스터 효과음 원재료

```text
Sound effect: a compact sci-fi mech thruster sustaining a steady blue-plasma hum,
with controlled air turbulence and a subtle metallic vibration.
Isolated sound, dry, constant intensity. No music, no voices, no explosion.
```

BPM·조성·32마디·루프 요구는 생성 성공을 보장하지 않는다. 독립적인 negative prompt 필드가 없는 도구에는 금지 요소를 짧은 자연어 문장으로 적고, 결과에 보컬이 섞이면 폐기하거나 수정한다. 가짜 보컬처럼 들리는 패드도 전투 시안에서는 별도로 평가한다.

## 8 제작 실험과 채택 기준

### 첫 실험은 12개 시안으로 제한

Suno와 Stable Audio에서 **로비·일반 전투·보스 각 2개**, 합계 12개 후보를 만든다. 이는 다음 단계 제안이며 이번 조사에서는 생성·결제하지 않았다. 동일한 의미의 지시문을 쓰고 도구별 입력 형식만 조정한다. 채널의 선호 구간이 정해지면 프롬프트부터 갱신한다.

처음에는 완성 OST를 한꺼번에 만들지 않는다. 후보 중 좋은 45~60초를 골라 비슷한 체감 음량으로 맞춘 뒤, 같은 게임 영상 또는 같은 전투 조건에서 비교한다. 원본 생성 길이와 비교용 발췌 길이를 구별한다.

| 평가 항목 | 제안 배점 | 판단 방법 |
|---|---:|---|
| 원하는 정서와 음색 | 30 | 사용자의 참조곡과 나란히 듣고 설명한 취향에 맞는가 |
| 전투 정보 전달 | 25 | 패링·피격·락온 신호가 들리는가 |
| 반복 피로 | 20 | 같은 구간을 10분 들었을 때 멜로디·하이햇이 거슬리는가 |
| 편집 가능성 | 15 | 박자가 안정적인가, 루프 경계를 만들 수 있는가, 분리 파일이 쓸 만한가 |
| 변주와 통일성 | 10 | 로비·전투·보스로 확장해도 같은 게임으로 느껴지는가 |

게임 사용 권리와 공식 다운로드 가능 여부는 점수 항목이 아니라 **채택 전 필수 조건**이다. 충분히 좋은 음원이 없으면 도구를 바로 늘리기 전에 요구 음색을 더 구체화한다.

### 비용을 계산하는 방식

구독료뿐 아니라 `생성 + 내려받기 + 스템 분리 + 편집 시간 + 계약 비용`을 기록한다. 요청 수가 많아도 쓸 수 있는 곡이 적으면 저렴한 제작이 아니다. 채택 가능한 루프 1분당 비용과 수정 시간을 비교한다.

- Stable Audio API에서 표시 단가로 6회 요청하면 산술상 US$1.56이다. 반복 생성·실패·추가 편집 호출·세금 등을 제외한 단순 예시다.
- Suno의 연간 결제 월 환산액 US$8/US$24를 한 달 시험 결제 비용이라고 쓰지 않는다. 첫 구매는 결제 화면의 기간·금액·다운로드 수를 기준으로 한다.
- 로컬 모델은 구독료가 없어도 설치·GPU·전력·작업 시간이 든다. 회사 라이선스 자격도 함께 계산한다.
- 작곡가 견적은 여기서 추정하지 않는다. 큐 개수, 반복 시간, 변주 수, 스템·MIDI 납품, 수정 횟수가 정해져야 비교할 수 있다.

### 최종 게임 파일의 제작 제안

1. 원본 생성 파일과 선택 구간을 별도 보존한다. 곡 ID·생성일·다운로드일·모델·플랜·프롬프트·라이선스 문서를 기록한다.
2. DAW에서 BPM과 첫 박을 확인하고 16·32·64마디 등 실제 음악 구간에 맞춰 루프를 만든다. 끝부분의 리버브 꼬리를 시작에 자연스럽게 연결한다.
3. 변주·스템은 같은 시작점·길이·샘플레이트로 내보낸다. 단순히 파일 길이만 같다고 화성과 박자가 맞는 것은 아니다.
4. 편집 마스터는 가능하면 원본 품질의 WAV로 보관하고, 게임 배포용 압축은 Godot에서 반복 경계·용량·재생 부하를 확인하며 선택한다. 48kHz/24비트는 작업 규격 후보이지 모든 AI 출력이 그 품질이라는 뜻이 아니다.
5. 모든 레이어를 합쳤을 때 클리핑이 없는지, 모노·이어폰·작은 스피커에서도 중요한 소리가 남는지 확인한다. LUFS는 체감 음량을 비교하는 측정치로 활용하되, 스트리밍용 수치 하나를 게임 전체의 정답으로 고정하지 않는다.
6. 실제 게임에서 전환·일시정지·재시작·보스 사망·씬 이동을 확인한다. 효과음과 음악 볼륨을 따로 조절할 수 있게 하는 것은 구현 단계의 요구사항으로 남긴다.

예를 들어 120 BPM·4/4·32마디는 `32 × 4 × 60 ÷ 120 = 64초`다. 이 관계를 써서 루프 길이를 점검할 수 있지만, AI가 입력 BPM을 정확히 지켰는지는 별도로 확인한다.

## 9 현재 결정과 남은 확인

**이 문서의 권고:** 로비는 Dreamwave/Chillsynth 방향, 전투는 같은 음색을 유지한 Outrun/Synthwave 방향부터 비교한다. Suno와 Stable Audio에서 시안을 확보한 뒤 DAW에서 편집하는 경로를 우선한다. 회사 라이선스 조건이 맞지 않는 후보는 다른 계약이나 도구로 바꾼다. 로컬 생성이 중요해지면 ACE-Step을 추가 비교한다.

최종 선택 전에 필요한 것은 사용자가 특히 좋아하는 참조 구간, 계약 주체와 배포 플랫폼, 시안의 실제 청취 결과다. 이 자료 없이 “가장 비슷한 AI”, “완성곡 품질 1위”, “이 프롬프트면 같은 음악이 나온다”는 결론은 내리지 않는다.

이번 작업의 산출물은 리서치·분석 문서다. 음원 생성·원곡 다운로드·구독 구매·모델 설치·게임 코드 수정은 하지 않았다. 문서의 제작 제안은 아직 채택되거나 구현된 사양이 아니다.
