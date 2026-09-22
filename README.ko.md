# OhMyWorm 🐛

[English version](README.md)

macOS용 작은 데스크톱 펫입니다. 지렁이 한 마리가 화면 가장자리를
돌아다닙니다. 움직임은 작은 순환 신경망이 정합니다. 밥 주고, 만지고,
스킨을 바꿔 주세요. 창도, 설정도, 계정도 없습니다.

## 배경

예쁜꼬마선충(*C. elegans*) 커넥톰에서 영감을 받았습니다.

손으로 설계한 11→6→2 신경망이 먹이와 벽, 배고픔을 감지해 다음 걸음을
정합니다.

## 기능

- **데스크톱 펫** — 클릭을 무시하는 투명 오버레이 위에 삽니다. 벌레 몸통을
  뺀 모든 클릭은 아래 앱으로 전달됩니다
- **신경망 이동** — 작은 신경망이 감각 입력으로 방향을 정합니다. 가장자리를
  선호하고, 입력이 같으면 경로는 항상 같습니다
- **엔진 3종** — 라이트(미니 신경망), 미디엄(커넥톰 가중치), 리얼(302뉴런+근육+먹이추적
  풀엔진). 메뉴에서 변경
- **꼭 필요한 만큼만** — 스탯 2개(포만감, 기분)와 할 일 3가지:
  - 🍎 **밥주기** — 근처에 먹이를 떨어뜨리면 벌레가 찾아가서 먹습니다
  - ❤️ **만지기** — 벌레를 클릭하거나 드래그로 들어 옮기세요
  - 🎨 **스킨** — 4가지 생김새(기본, 베리, 허니, 고스트). 껐다 켜도
    유지됩니다
- **시스템 연동** — CPU가 바쁘면 빨라지고, 배터리가 줄면 작아지고, 충전기
  빼면 느려집니다
- **가벼움** — M4 Pro, Release 기준 CPU 5% 안팎, 메모리 30MB

## 요구 사항

- macOS 14 이상 (Apple Silicon 권장)
- 직접 빌드하려면 Xcode 16 이상

## 빌드 & 실행

```sh
# 빌드
xcodebuild -project OhMyWorm.xcodeproj -scheme OhMyWorm -configuration Release build

# 실행 (Finder에서 직접 열어도 됩니다)
open ~/Library/Developer/Xcode/DerivedData/OhMyWorm-*/Build/Products/Release/OhMyWorm.app

# 테스트
xcodebuild -project OhMyWorm.xcodeproj -scheme OhMyWorm -configuration Debug test
```

메뉴바에 삽니다. 🐛를 찾으세요. dock에도 없고 창도 열지 않습니다.

## 사용법

| 동작 | 방법 |
| --- | --- |
| 밥주기 | 🐛 메뉴 → 밥주기, 또는 벌레 우클릭 → 밥주기 |
| 만지기 | 벌레 좌클릭, 또는 드래그로 들어 옮기기 |
| 스킨 변경 | 🐛 메뉴 → 스킨 변경 |
| 엔진 변경 | 🐛 메뉴 → 엔진 변경 |
| 일시정지 / 계속 | 🐛 메뉴 → 일시정지 |
| 종료 | 🐛 메뉴 → 종료 |

벌레를 우클릭해도 같은 메뉴가 열립니다. 맨 위에 스탯(포만감, 기분)이
보입니다.

## 프로젝트 구조

```text
App/
  OhMyWormApp.swift      에이전트 진입점, 상태바 아이콘
  Pet/
    PetController.swift  게임 루프, 입력, 액션
    PetModel.swift         순수 게임 상태 (UI 없음, 테스트됨)
    MiniBrain.swift        라이트: 손설계 11→6→2 신경망
    MediumBrain.swift      미디엄: 커넥톰 가중치
    Real/                  리얼: 실제 302뉴런 엔진 + 어댑터
    LocomotionEngine.swift 엔진 프로토콜 + 선택
    DesktopPanel.swift   벌레를 따라다니는 클릭-스루 오버레이
    WormView.swift       Canvas 렌더링
    PetMenu.swift        하나뿐인 메뉴
Tests/OhMyWormTests/    유닛 테스트 30개 (엔진, 모델, 컨트롤러, vitals)
docs/architecture.md    설계 노트 (영문)
```

자세한 설계는 [docs/architecture.md](docs/architecture.md)에 있습니다.

## 참고

- 지금은 메인 디스플레이만 지원합니다.
- UI는 한국어만 나옵니다. 다른 나라 말로 옮기는 걸 도와주시면 좋겠습니다.

## 만든 과정

`muse-spark-1.3` AI 모델과 함께 바이브 코딩으로 만들었습니다. 사람이 옆에서
지시하고 테스트했습니다.

## 라이선스

아직 못 정했습니다. 첫 공개 전에 붙입니다. 아마 MIT.
