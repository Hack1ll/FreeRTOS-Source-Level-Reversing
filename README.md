# FreeRTOS 소스 레벨 리버싱

이 프로젝트는 FreeRTOS API 사용법 문서가 아닙니다.

FreeRTOS 커널 동작을 소스 레벨에서 다시 추적하고 재구성하는 문서입니다.

핵심은 이것입니다.

```text
FreeRTOS에서 task는 어떻게 커널 object가 되는가?

그 task는 어떤 list를 오가며 상태가 바뀌는가?

scheduler는 어떤 기준으로 다음 task를 고르는가?

Cortex-M port layer는 그 결정을 어떻게 실제 CPU context switch로 바꾸는가?
```

즉 이 저장소는 “API를 어떻게 쓰는가”보다 “kernel 안에서 무슨 일이 일어나는가”에
집중합니다.

```text
application API 호출
    |
    v
커널 object 생성
    |
    v
list 이동
    |
    v
scheduler 결정
    |
    v
port별 context switch
```

---

## 이 프로젝트가 보는 것

첫 번째 패스에서는 FreeRTOS의 전체 세계를 한 번에 보지 않습니다.

작고 구체적인 경로 하나를 잡고 따라갑니다.

```text
ListItem_t
    |
    v
TCB_t
    |
    v
ready list / delayed list
    |
    v
task creation
    |
    v
scheduler tick
    |
    v
SysTick / PendSV
    |
    v
queue / semaphore / mutex / event group
    |
    v
heap_4 allocator
    |
    v
GCC ARM Cortex-M4F port layer
```

이 경로를 따라가면 FreeRTOS를 이런 관점으로 볼 수 있습니다.

```text
task 상태
    = enum 값 하나가 아니라 list membership

context switch
    = scheduler 결정 + port layer의 register/stack 복원

동기화 object
    = task를 wait list와 ready list 사이에서 이동시키는 조건

heap
    = TCB_t, stack, Queue_t 같은 커널 object가 태어나는 메모리 기반
```

---

## 범위

기준으로 삼는 범위는 다음입니다.

```text
기준 commit
    = a8c9d3515

port
    = FreeRTOS-Kernel/portable/GCC/ARM_CM4F/

메모리 관리자
    = FreeRTOS-Kernel/portable/MemMang/heap_4.c
```

FreeRTOS는 여러 architecture port와 여러 heap implementation을 제공합니다.

하지만 첫 번째 패스에서는 일부러 범위를 좁힙니다.

```text
목표
    = 모든 port를 훑기

아님

목표
    = 하나의 port와 하나의 heap을 기준으로
      커널 동작의 큰 흐름을 정확히 잡기
```

---

## 이 저장소에 없는 것

이 저장소에는 FreeRTOS upstream source를 포함하지 않습니다.

또한 다음을 포함하지 않습니다.

```text
타사 firmware
상용 binary
exploit proof-of-concept
Ghidra project
복사해 온 source dump
```

여기서 말하는 리버싱은 binary exploit 분석이 아닙니다.

```text
소스 레벨 리버싱
    =
    공개된 FreeRTOS 커널 구조를
    실행 흐름과 자료구조 관점에서 다시 조립해 보는 공부 방식
```

---

## 따라 읽는 방법

처음이라면 여기서 시작하면 됩니다.

1. [서문](docs/00-preface.md)
2. [읽기 지도](docs/01-reading-map.md)
3. [목차](SUMMARY.md)

가장 짧은 기술 경로는 다음입니다.

```text
docs/02-kernel-objects/list.md
    |
    v
docs/02-kernel-objects/tcb.md
    |
    v
docs/03-task-management/task-creation.md
    |
    v
docs/04-scheduler/ready-lists.md
    |
    v
docs/05-context-switch/pendsv.md
    |
    v
docs/06-synchronization/queues.md
    |
    v
docs/07-memory-management/heap_4.md
    |
    v
docs/08-port-layer/gcc-arm-cm4f.md
```

---

## FreeRTOS 소스를 옆에 두고 보고 싶다면

이 저장소 자체는 문서 전용입니다.

로컬에서 소스 참조를 같이 확인하고 싶다면 옆에 upstream 커널을 받아두면
됩니다.

```sh
git clone https://github.com/FreeRTOS/FreeRTOS-Kernel.git FreeRTOS-Kernel
cd FreeRTOS-Kernel
git checkout a8c9d3515
```

`FreeRTOS-Kernel/` 디렉터리는 `.gitignore`에 들어 있습니다.

즉 로컬 companion checkout으로 둘 수 있지만, 이 저장소에는 commit되지
않습니다.

---

## 문서 검사

문서 링크와 제목 형식을 확인하려면:

```sh
tools/check-source-links.sh
```

검사는 다음을 확인합니다.

```text
markdown link 대상
보이는 markdown 제목
선택적 FreeRTOS-Kernel 소스 참조
```

---

## 라이선스

이 저장소의 문서와 로컬 도구는 MIT License로 공개됩니다.

FreeRTOS 자체는 이 저장소에 포함되어 있지 않으며, 이 저장소가 FreeRTOS를
재라이선스하지도 않습니다. FreeRTOS 커널의 license는 upstream repository를
따릅니다.

한 문장으로 정리하면:

```text
이 프로젝트는 FreeRTOS를 "사용하는 법"보다,
FreeRTOS 커널이 task, list, scheduler, port layer를 통해
어떻게 실제 실행 흐름을 만드는지 소스 레벨에서 재구성하는 노트입니다.
```
