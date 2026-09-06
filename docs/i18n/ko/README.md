<!-- zhc-i18n 源: README.md 基线: 0202d9e1d203271d 时间: 2026-09-06 -->

# zhc — 모국어로 창찌(Cangjie) 프로그래밍하기

Language / Language / Langue / Sprache / Idioma / 언어 / 言語 / Язык：[中文](../../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Español](../es/README.md) · **한국어** · [日本語](../ja/README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

**zhc**는 창찌 프로그래밍 언어의 모국어 학습 프레임워크입니다. 방언 소스 코드
(중국어 `.zc`, 한국어 `.kc`, 프랑스어 `.fc` 등)를 표준 창찌 코드로 트랜스파일하고,
컴파일러의 영어 진단 메시지를 선택한 언어의 학습용 메시지로 되돌려 줍니다
(오류 코드 → 메시지 테이블 → 타입 현지화 → 수정 예시). 방언은 `ZHCLANG`
환경 변수로 선택하며(기본값 `zh`), 모든 동작은 **언어 팩**이 주도합니다.

## 빠른 시작 (약 10분)

**1. 창찌 SDK 설치** (유일한 외부 의존성): cangjie-lang.cn/download에서
**1.0.5** 버전을 내려받아 압축을 풀고 함께 제공되는 `envsetup.sh`를 실행해
`cjc`와 `cjpm`을 `PATH`에 넣으세요. 확인:

```bash
cjc --version    # Cangjie Compiler: 1.0.5 (cjnative)
```

**2. zhc 빌드** (네트워크 불필요, 서드파티 의존성 없음):

```bash
cd zhc
cjpm build       # target/release/bin/main 생성
```

**3. 첫 프로그램 실행** (저장소에 포함된 한국어 방언 예제):

```bash
export ZHC_LANG_PACKS=$PWD        # 저장소 루트 기준: zhc/
zhc run examples/ko-hello.kc
# ✅ Compilation OK: replaced 7 dialect identifier(s).
# 안녕하세요, 한국!
# 숫자: 42
```

## 모국어로 작성하기

`zhc/lang-packs/<코드>/` 아래에 언어 팩이 있는 언어라면 무엇이든 사용할 수
있습니다 — `zh`/`en`(완전 수준), `ru`/`ja`/`ko`/`fr`/`es`/`de`(표준 수준)와 `ar`(RTL 데모)이 포함되어
있습니다. 예를 들어 한국어(`ZHCLANG=ko`, 확장자 `.kc`):

```kc
메인() {
    두다 이름: 문자열 = "Cangjie"
    출력("안녕하세요, ${이름}!")
}
```

실행: `ZHCLANG=ko zhc run hello.kc`. 프랑스어 방언도 동일하게 동작합니다
(`principal/soit/Chaine/afficher`, 확장자 `.fc`).

## 서드파티 라이브러리 번역

라이브러리 API 매핑은 공유 번역 저장소에 있으며 소스 트리에 포함되지 않습니다
— 필요한 언어와 라이브러리만 내려받으세요:

```bash
zhc share list                     # 공유 레지스트리 탐색
zhc share fetch csv4cj --lang ko   # 내 언어로 매핑 하나만 다운로드
zhc share publish 내_매핑.toml      # 직접 번역한 결과 공유하기
```

내려받은 매핑은 체크섬 + 품질 게이트(형식, 공식 이름 검사, 예약어 충돌)를
통과한 뒤 `~/.zhc/lang-packs/<언어>/crates/`에 설치됩니다. 번역이 없는
경우 중국어로 우아하게 대체되며, 어느 쪽이든 프로그램은 정상 동작합니다.

## 용어 (한국어 문서 전체에서 통일해서 사용)

| 한국어 | 코드/문서 표기 | 비고 |
|---|---|---|
| 방언 | `.zc` `.kc` `.fc` … | 모국어로 쓴 창찌 코드 |
| 언어 팩 | `lang-packs/<코드>/` | 키워드/별칭 테이블 + 진단 + UI 문안 |
| 매핑 | `crates/<언어>/<라이브러리>.toml` | 모국어 이름 = 공식 API 이름 |
| 트랜스파일 | `zhc run` / `zhc check` | 방언 → 표준 창찌 |
| 공유 저장소 | `zhc share …` | 번역 중앙 레지스트리 |
| 기준선 | `zh@<체크섬>` | zh 원본의 동기화 지문(fingerprint) |

## 더 읽을거리

- 튜토리얼 (정본, 중국어): [중국어로 Cangjie 프로그래밍 — 정본 교재](../../../docs/中文仓颉程序设计/README.md)
- 언어 팩 개발과 기여: [언어 팩 개발 가이드](../../../docs/语言包开发.md)
- 현지화 범위와 동기화 메커니즘: [docs/i18n/README.md](../README.md)
- 튜토리얼 한국어 가이드: [튜토리얼 안내(0과)](tutorial-00.md)
- 문제 해결: `zhc doctor` — 여섯 항목 환경 자가 점검(컴파일러, 빌드 도구, 언어팩, 쓰기 가능 디렉터리, 공유 소스, cjlint)과 모국어 수정 안내를 제공합니다.
