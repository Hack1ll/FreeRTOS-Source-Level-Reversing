# Glossary

이 glossary는 첫 번째 FreeRTOS reading pass에서 자주 만나는 단어들을 모은 작은 지도입니다.

목표는 모든 용어를 엄밀하게 다 정의하는 것이 아닙니다.

처음 읽을 때 헷갈리기 쉬운 말들을 이렇게 연결해두는 것이 목표입니다.

```text
object
    |
    v
list
    |
    v
scheduler
    |
    v
context switch
    |
    v
port layer
```

---

## TCB

TCB는 Task Control Block입니다.

FreeRTOS에서는 `tasks.c`의 `TCB_t`가 task를 표현하는 kernel object입니다.

```text
TCB_t

+-----------------------------+
| pxTopOfStack                |
| xStateListItem              |
| xEventListItem              |
| uxPriority                  |
| pxStack                     |
+-----------------------------+
```

쉽게 말하면:

```text
TCB_t
    = scheduler가 task를 관리하기 위해 보는 task 관리 카드
```

---

## pxCurrentTCB

`pxCurrentTCB`는 현재 실행 중인 task의 TCB를 가리키는 pointer입니다.

```text
pxCurrentTCB
     |
     v
+----------------+
| current TCB_t  |
+----------------+
```

Context switch 중에는 이 pointer의 의미가 바뀝니다.

```text
vTaskSwitchContext() 전
    pxCurrentTCB -> old task

vTaskSwitchContext() 후
    pxCurrentTCB -> next task
```

---

## pxTopOfStack

`pxTopOfStack`은 task의 저장된 context가 있는 stack 위치를 가리킵니다.

```text
TCB_t
  |
  v
pxTopOfStack
  |
  v
saved context on task stack
```

PendSV가 새 task를 restore할 때 이 값을 사용합니다.

```text
pxCurrentTCB->pxTopOfStack
        |
        v
task stack에서 register 복원
```

---

## Stack

Stack은 task가 실행 중 사용하는 메모리 공간입니다.

```text
Task Stack

+-----------------------------+
| local variables             |
| function call frames        |
| saved registers             |
| context switch state        |
+-----------------------------+
```

FreeRTOS에서는 task마다 자기 stack이 있습니다.

```text
Task A Stack
Task B Stack
Task C Stack
```

Context switch 때 현재 task의 CPU 상태는 자기 stack에 저장됩니다.

---

## Context

Context는 task를 나중에 이어서 실행하기 위해 필요한 CPU 실행 상태입니다.

```text
context
    = registers
    + stack pointer
    + PC
    + LR
    + xPSR
    + 실행을 이어가기 위한 상태
```

한 문장으로:

```text
context
    = task가 어디서 멈췄고 어떻게 다시 시작해야 하는지 알려주는 기록
```

---

## Ready list

Ready list는 실행 가능한 task들이 priority별로 들어 있는 list입니다.

```text
Ready List priority 3

+-------------+     +-------------+
| Task A item | --> | Task B item |
+-------------+     +-------------+
```

Scheduler는 ready list를 보고 다음에 실행할 task를 고릅니다.

```text
ready list에 있음
    =
지금 CPU만 받으면 실행 가능함
```

---

## Delayed list

Delayed list는 시간 조건 때문에 잠든 task들이 들어 있는 list입니다.

예를 들어 `vTaskDelay(100)`을 호출한 task는 일정 tick이 지날 때까지 delayed list에 들어갈 수 있습니다.

```text
Task calls vTaskDelay()
    |
    v
Ready List에서 빠짐
    |
    v
Delayed List에 들어감
    |
    v
wake tick이 되면 Ready List로 돌아감
```

`xTaskIncrementTick()`은 tick이 증가할 때 delayed list를 확인합니다.

---

## Event list

Event list는 특정 event를 기다리는 task들이 들어 있는 list입니다.

Queue, semaphore, mutex, event group이 이런 wait list를 사용합니다.

```text
event unavailable
    |
    v
task waits on event list

event becomes available
    |
    v
task moves back to ready list
```

즉 event list는 이런 뜻입니다.

```text
"시간이 아니라 어떤 event를 기다리는 task들의 대기실"
```

---

## xStateListItem

`xStateListItem`은 task의 상태 list에 들어가는 list item입니다.

```text
TCB_t
  |
  +--> xStateListItem
           |
           +--> ready list
           +--> delayed list
           +--> suspended list
```

이 item이 어느 list에 들어가 있는지를 보면 task의 scheduler 상태를 읽을 수 있습니다.

---

## xEventListItem

`xEventListItem`은 event wait list에 들어가는 list item입니다.

```text
TCB_t
  |
  +--> xEventListItem
           |
           +--> queue wait list
           +--> semaphore wait list
           +--> event group wait list
```

즉:

```text
xStateListItem
    = task 상태 list용

xEventListItem
    = event 대기 list용
```

---

## Scheduler

Scheduler는 다음에 어떤 task를 실행할지 고르는 FreeRTOS kernel logic입니다.

```text
Ready lists
    |
    v
highest priority ready task 선택
    |
    v
pxCurrentTCB 갱신
```

Common scheduler code는 “누구를 실행할지”를 결정합니다.

실제로 CPU register를 저장하고 복원하는 일은 port layer가 합니다.

---

## SysTick

SysTick은 Cortex-M의 periodic timer interrupt입니다.

FreeRTOS에서는 kernel time을 전진시키는 heartbeat처럼 볼 수 있습니다.

```text
SysTick
    |
    v
xTaskIncrementTick()
    |
    v
xTickCount 증가
    |
    v
delayed task 깨우기
    |
    v
필요하면 PendSV 요청
```

SysTick은 직접 context switch를 끝까지 수행하지 않고, 필요하면 PendSV를 요청합니다.

---

## PendSV

PendSV는 Cortex-M에서 FreeRTOS context switch를 실제로 수행하는 exception입니다.

```text
PendSV
    |
    +--> old task context 저장
    |
    +--> vTaskSwitchContext()
    |
    +--> next task context 복원
```

즉:

```text
vTaskSwitchContext()
    = 다음 TCB 선택

PendSV
    = 그 TCB의 stack을 복원해 실제 CPU 실행으로 바꿈
```

---

## Port layer

Port layer는 FreeRTOS common kernel을 특정 CPU에서 실제로 동작하게 만드는 계층입니다.

```text
FreeRTOS common kernel
        |
        v
port layer
        |
        v
specific CPU
```

GCC ARM Cortex-M4F port에서는 주로 다음 파일을 봅니다.

```text
FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c
FreeRTOS-Kernel/portable/GCC/ARM_CM4F/portmacro.h
```

Port layer는 이런 일을 담당합니다.

```text
initial stack frame
SysTick handling
PendSV context switch
interrupt masking
critical section
```

---

## Queue

Queue는 data를 저장하면서 task를 재우고 깨울 수 있는 synchronization object입니다.

```text
Queue
    = data buffer
    + receive wait list
    + send wait list
```

그림:

```text
+------------------------------------------------+
| Queue                                          |
|------------------------------------------------|
| data buffer                                    |
| tasks waiting to receive                       |
| tasks waiting to send                          |
+------------------------------------------------+
```

Queue는 semaphore와 mutex 구현의 기반으로도 쓰입니다.

---

## Semaphore

Semaphore는 token을 주고받는 synchronization object입니다.

```text
take semaphore
    -> token 소비
    -> token 없으면 wait 가능

give semaphore
    -> token 제공
    -> 기다리던 task를 깨울 수 있음
```

FreeRTOS semaphore는 queue mechanics 위에서 만들어집니다.

```text
Semaphore
    = payload보다 token state가 중요한 queue-like object
```

---

## Mutex

Mutex는 ownership이 있는 semaphore-like object입니다.

핵심 차이는 owner입니다.

```text
Mutex

+----------------+
| locked         |
| owner = Task A |
+----------------+
```

Mutex는 priority inheritance와 연결됩니다.

```text
high-priority task waits for mutex
        |
        v
owner task may inherit higher priority
```

---

## Event group

Event group은 bit 조건을 기다리는 synchronization object입니다.

```text
Event Group bits

+---+---+---+---+
| 3 | 2 | 1 | 0 |
+---+---+---+---+
```

Task는 이런 조건을 기다릴 수 있습니다.

```text
ANY
    = 기다리는 bit 중 하나라도 set되면 만족

ALL
    = 기다리는 bit가 모두 set되어야 만족
```

Queue와 달리 하나의 bit update가 여러 task를 깨울 수 있습니다.

---

## Heap

Heap은 동적으로 kernel object를 만들 때 쓰는 메모리 공간입니다.

```text
xTaskCreate()
    -> TCB_t allocation
    -> stack allocation

xQueueCreate()
    -> Queue_t allocation
    -> storage allocation
```

즉 heap은 task와 queue 같은 object가 태어나는 기반입니다.

---

## heap_4

`heap_4.c`는 FreeRTOS portable memory manager 중 하나입니다.

특징은 다음입니다.

```text
heap_4.c
    = allocation 가능
    = free 가능
    = free list 사용
    = adjacent free block coalescing 지원
```

중요한 구조체는 `BlockLink_t`입니다.

```text
BlockLink_t
    = free block header
    = next free block pointer + block size
```

---

## 최종 그림

첫 번째 reading pass의 용어들은 이렇게 연결됩니다.

```text
Heap
  |
  v
TCB_t / Queue_t
  |
  v
ListItem_t
  |
  v
Ready / delayed / event lists
  |
  v
Scheduler
  |
  v
SysTick / PendSV
  |
  v
Port layer
  |
  v
CPU execution
```

한 문장으로 정리하면:

```text
FreeRTOS를 처음 읽을 때 가장 중요한 단어들은
대부분 "object가 어떤 list에 있고, scheduler와 port layer가 그 object를 어떻게 실행 상태로 바꾸는가"로 연결된다.
```
