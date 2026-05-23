# FreeRTOS 소스 레벨 리버싱

FreeRTOS 커널 동작을 소스 레벨에서 다시 추적하고 재구성하는 문서입니다.

API 사용법보다 아래 흐름에 집중합니다.

```text
커널 object
    |
    v
list 이동
    |
    v
scheduler 결정
    |
    v
port layer의 context switch
```

## 읽는 순서

처음이라면 아래 순서로 보면 됩니다.

1. [서문](docs/00-preface.md)
2. [읽기 지도](docs/01-reading-map.md)
3. [목차](SUMMARY.md)

첫 번째 패스의 기준은 다음입니다.

```text
FreeRTOS-Kernel commit: a8c9d3515
port: portable/GCC/ARM_CM4F
heap: portable/MemMang/heap_4.c
```

## 이 저장소에 없는 것

이 저장소는 문서 전용입니다.

```text
FreeRTOS upstream source
타사 firmware
상용 binary
exploit proof-of-concept
Ghidra project
복사해 온 source dump
```

FreeRTOS 소스를 옆에 두고 보고 싶다면 로컬에 따로 받으면 됩니다.

```sh
git clone https://github.com/FreeRTOS/FreeRTOS-Kernel.git FreeRTOS-Kernel
cd FreeRTOS-Kernel
git checkout a8c9d3515
```

`FreeRTOS-Kernel/`은 `.gitignore`에 포함되어 있습니다.

## 문서 검사

```sh
tools/check-source-links.sh
```

## 라이선스

이 저장소의 문서와 로컬 도구는 MIT License로 공개됩니다.

FreeRTOS 자체는 이 저장소에 포함되어 있지 않으며, FreeRTOS 커널의 license는
upstream repository를 따릅니다.
