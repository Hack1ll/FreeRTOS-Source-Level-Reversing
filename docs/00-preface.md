# Preface

이 문서는 FreeRTOS kernel source를 처음부터 다시 조립해서 읽어보는 기록입니다.

핵심은 이것입니다.

```text
FreeRTOS는 작지만 진짜 kernel이다.

그래서 task, scheduler, interrupt, context switch, heap 같은 주제를
너무 거대한 코드베이스에 압도되지 않고 볼 수 있다.
```

Linux kernel을 처음 읽으면 여러 벽이 한 번에 옵니다.

```text
boot code
memory manager
scheduler
interrupt subsystem
driver model
architecture-specific code
```

FreeRTOS는 같은 커널 주제를 훨씬 작은 공간에서 보여줍니다.

```text
FreeRTOS에서 볼 수 있는 것

+----------------------+-----------------------------+
| TCB_t                | task를 표현하는 kernel object|
| ready list           | 실행 가능한 task들의 목록    |
| delayed list         | 시간 때문에 잠든 task 목록    |
| SysTick              | kernel time의 박자           |
| PendSV               | 실제 context switch 지점      |
| heap_4               | kernel object 메모리 공급원   |
+----------------------+-----------------------------+
```

즉 FreeRTOS는 작지만 toy는 아닙니다.

```text
작다
    = 처음 읽기 좋다

진짜 kernel이다
    = scheduler와 context switch가 실제로 있다
```

---

## source-level reversing이란?

이 저장소에서 말하는 source-level reversing은 binary exploit을 찾는 작업이
아닙니다.

여기서 하는 일은 이것입니다.

```text
이미 공개되어 있는 FreeRTOS kernel source를
실행 흐름 기준으로 다시 분해하고,
그 조각들을 차례대로 이어 붙여 보는 읽기 방식
```

그림으로 보면:

```text
source files
    |
    v
함수와 구조체를 하나씩 읽음
    |
    v
list 이동과 scheduler 상태 변화를 추적
    |
    v
task가 어떻게 생성되고 실행되는지 재구성
```

즉 질문은 이런 쪽에 가깝습니다.

```text
이 구조체는 왜 필요한가?
이 함수가 끝나면 어떤 list가 바뀌는가?
이 pointer는 다음 context switch에서 어떻게 쓰이는가?
common kernel과 port layer의 책임은 어디서 나뉘는가?
```

---

## 첫 번째 큰 흐름

이 프로젝트의 첫 번째 읽기 흐름은 task가 태어나고 실행되기까지의 길을 따라갑니다.

```text
application creates tasks
    |
    v
tasks enter ready lists
    |
    v
the scheduler starts
    |
    v
SysTick advances kernel time
    |
    v
PendSV switches the current task
```

조금 더 FreeRTOS 이름에 맞춰 쓰면:

```text
xTaskCreate()
    |
    v
TCB_t 생성
    |
    v
ready list에 연결
    |
    v
vTaskStartScheduler()
    |
    v
SysTick / PendSV
    |
    v
task context switch
```

이 흐름을 이해하면 다른 주제도 같은 문법으로 읽을 수 있습니다.

```text
Queue
    = data 조건에 따라 task를 wait/ready list로 이동

Semaphore
    = token 조건에 따라 task를 wait/ready list로 이동

Mutex
    = owner와 priority inheritance까지 포함한 wait/ready 이동

Event Group
    = bit 조건에 따라 task를 wait/ready list로 이동
```

---

## 첫 번째 패스의 범위

FreeRTOS는 여러 architecture port와 여러 heap implementation을 제공합니다.

하지만 처음부터 전부 섞으면 이런 일이 생깁니다.

```text
kernel logic을 보기도 전에
architecture 차이와 configuration 차이에 먼저 지침
```

그래서 첫 번째 패스에서는 범위를 좁힙니다.

```text
기준 commit
    = a8c9d3515

port
    = FreeRTOS-Kernel/portable/GCC/ARM_CM4F/

heap
    = FreeRTOS-Kernel/portable/MemMang/heap_4.c
```

선택한 흐름은 이렇습니다.

```text
common kernel
    tasks.c
    queue.c
    list.c
        |
        v
ARM Cortex-M4F port
    port.c
    portmacro.h
        |
        v
heap_4 allocator
    pvPortMalloc()
    vPortFree()
```

Cortex-M4F를 먼저 보는 이유는 역할 분리가 잘 보이기 때문입니다.

```text
SysTick
    = 시간 박자

PendSV
    = context switch

Cortex-M exception entry/return
    = context 일부 자동 저장/복원
```

---

## 이 문서가 공식 매뉴얼은 아니다

이 문서는 FreeRTOS API를 빠짐없이 설명하는 공식 매뉴얼이 아닙니다.

목표는 API reference가 아니라 읽기 지도입니다.

```text
공식 매뉴얼식 질문
    "이 API의 모든 옵션은 무엇인가?"

이 문서의 질문
    "이 API를 부르면 kernel 내부 상태가 어떻게 바뀌는가?"
```

예를 들어 `xTaskCreate()`를 볼 때도 함수 인자 설명에서 멈추지 않습니다.

```text
xTaskCreate()
    |
    v
TCB_t allocation
    |
    v
stack allocation
    |
    v
initial stack frame
    |
    v
ready list insertion
```

이 프로젝트는 이런 식으로 봅니다.

```text
API
    -> kernel object
    -> list movement
    -> scheduler decision
    -> port-specific CPU action
```

---

## 읽을 때 붙잡을 기준

처음 읽을 때는 모든 macro와 configuration을 외우려고 하지 않아도 됩니다.

대신 계속 같은 질문을 붙잡으면 됩니다.

```text
1. 지금 어떤 object를 보고 있는가?
2. 이 object 안에서 중요한 pointer는 무엇인가?
3. 이 함수가 끝나면 어떤 list가 바뀌는가?
4. task가 ready, delayed, blocked 중 어디로 이동하는가?
5. common code와 port code가 어디서 만나는가?
6. CPU context는 어느 stack에 저장되는가?
```

가장 중요한 그림은 이것입니다.

```text
FreeRTOS kernel을 읽는 큰 축

Object
  |
  v
List
  |
  v
Scheduler
  |
  v
Context switch
  |
  v
Port layer
  |
  v
Hardware
```

한 문장으로 정리하면:

```text
이 프로젝트는 FreeRTOS source를 통해
task가 메모리 위의 object로 만들어지고,
list를 오가며 scheduler의 선택을 받고,
마지막에는 Cortex-M port가 실제 CPU context로 바꿔 실행하는 과정을 따라간다.
```

다음 장에서는 이 전체 흐름을 어떤 순서로 읽을지 지도를 만듭니다.
