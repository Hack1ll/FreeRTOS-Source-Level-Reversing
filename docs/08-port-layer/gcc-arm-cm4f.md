# GCC ARM Cortex-M4F port

이번 주제는 GCC ARM Cortex-M4F port입니다.

지금까지 FreeRTOS의 공통 구조를 봤습니다.

```text
TCB_t
Ready list
Delayed list
Queue
Semaphore
Mutex
Heap
Scheduler
```

그런데 이런 공통 코드만으로는 CPU를 직접 움직일 수 없습니다.

왜냐하면 CPU마다 register 구조, interrupt 방식, stack 처리 방식이 다르기
때문입니다.

그래서 FreeRTOS에는 port layer가 있습니다.

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c`
- `FreeRTOS-Kernel/portable/GCC/ARM_CM4F/portmacro.h`
- `FreeRTOS-Kernel/tasks.c`

## port란 무엇인가?

FreeRTOS의 common kernel code는 최대한 CPU에 독립적으로 작성되어 있습니다.

```text
FreeRTOS common kernel

+----------------------+
| tasks.c              |
| queue.c              |
| list.c               |
| event_groups.c       |
+----------------------+
```

하지만 실제로 context switch를 하려면 CPU 세부사항을 알아야 합니다.

```text
CPU register를 어떻게 저장하지?
stack pointer는 어떤 register를 쓰지?
interrupt priority는 어떻게 설정하지?
SysTick은 어떻게 켜지?
PendSV는 어떻게 pending 시키지?
```

이런 CPU별 작업을 담당하는 부분이 port입니다.

```text
FreeRTOS common kernel
        |
        v
port layer
        |
        v
specific CPU
```

그림으로 보면:

```text
+--------------------------------+
| FreeRTOS common kernel         |
|--------------------------------|
| tasks.c                        |
| queue.c                        |
| list.c                         |
| CPU 종류를 최대한 몰라도 됨     |
+---------------+----------------+
                |
                v
+--------------------------------+
| GCC ARM Cortex-M4F port        |
|--------------------------------|
| port.c                         |
| portmacro.h                    |
| Cortex-M4F 세부사항 담당       |
+---------------+----------------+
                |
                v
+--------------------------------+
| ARM Cortex-M4F CPU             |
|--------------------------------|
| registers                      |
| SysTick                        |
| PendSV                         |
| interrupt priority             |
+--------------------------------+
```

## 왜 port layer가 필요할까?

예를 들어 scheduler는 이렇게 말합니다.

```text
"다음 task로 바꿔줘."
```

하지만 실제 CPU에서는 이런 일을 해야 합니다.

```text
현재 task register 저장
현재 stack pointer 저장
다음 task stack pointer 읽기
다음 task register 복원
exception return
```

이건 CPU마다 방법이 다릅니다.

ARM Cortex-M, RISC-V, AVR은 register도 다르고 interrupt 구조도 다릅니다.

그래서 FreeRTOS는 이렇게 나눕니다.

```text
공통 scheduler:
    "무엇을 할지 결정"

port layer:
    "이 CPU에서 실제로 어떻게 할지 수행"
```

비유하면:

```text
공통 kernel = 감독
port layer = 각 무대의 기술팀
CPU        = 실제 무대
```

감독은 다음 배우로 교체하라고 말하지만, 무대마다 조명, 문, 장치가 다르기
때문에 실제 전환은 각 무대 기술팀이 합니다.

## portmacro.h는 무엇을 제공할까?

`portmacro.h`는 common kernel code가 CPU 세부사항을 직접 알지 않고도 쓸 수
있는 타입과 매크로를 제공합니다.

```text
FreeRTOS-Kernel/portable/GCC/ARM_CM4F/portmacro.h
```

쉽게 말하면:

```text
portmacro.h
    = common kernel과 CPU-specific code 사이의 약속 모음
```

대표적으로 이런 것들이 들어 있습니다.

```text
portYIELD()
portENTER_CRITICAL()
portEXIT_CRITICAL()
portSET_INTERRUPT_MASK_FROM_ISR()
portCLEAR_INTERRUPT_MASK_FROM_ISR()
StackType_t
BaseType_t
TickType_t
portSTACK_GROWTH
```

그림으로 보면:

```text
+--------------------------------+
| common kernel code             |
|--------------------------------|
| portYIELD()                    |
| portENTER_CRITICAL()           |
| portSET_INTERRUPT_MASK...      |
+---------------+----------------+
                |
                v
+--------------------------------+
| portmacro.h                    |
|--------------------------------|
| 이 매크로가 실제 CPU 동작으로   |
| 어떻게 연결되는지 정의          |
+---------------+----------------+
                |
                v
+--------------------------------+
| Cortex-M4F mechanism           |
|--------------------------------|
| PendSV pending                 |
| interrupt mask                 |
| critical section               |
+--------------------------------+
```

## portYIELD() 예시

공통 kernel 입장에서는 `portYIELD()`가 단순한 요청입니다.

```text
"CPU를 양보해라."
"필요하면 context switch를 해라."
```

common code는 Cortex-M의 PendSV register를 직접 몰라도 됩니다.

```text
common kernel code

portYIELD()
```

Cortex-M port에서는 이것이 대략 이런 의미로 연결됩니다.

```text
portYIELD()
    |
    v
PendSV를 pending 상태로 만듦
    |
    v
나중에 PendSV handler가 context switch 수행
```

그림:

```text
+----------------------+
| common kernel        |
|----------------------|
| portYIELD()          |
+----------+-----------+
           |
           v
+----------------------+
| Cortex-M4F port      |
|----------------------|
| PendSV pending       |
+----------+-----------+
           |
           v
+----------------------+
| PendSV handler       |
|----------------------|
| old task 저장         |
| next task 복원        |
+----------------------+
```

즉 common kernel은 이렇게만 생각합니다.

```text
"yield 요청"
```

Cortex-M port는 이렇게 구현합니다.

```text
"PendSV를 pending시켜서 context switch하게 만들기"
```

## interrupt masking 매크로

FreeRTOS는 어떤 중요한 코드를 실행할 때 interrupt에 방해받지 않아야 할 수
있습니다.

예를 들어 tick 처리 중 ready list나 delayed list를 바꾸고 있을 수 있습니다.

```text
delayed list에서 task 제거
ready list에 task 삽입
```

이 중간에 interrupt가 끼어들면 자료구조가 꼬일 수 있습니다.

그래서 port layer는 interrupt mask 기능을 제공합니다.

```text
portSET_INTERRUPT_MASK_FROM_ISR()
portCLEAR_INTERRUPT_MASK_FROM_ISR()
```

그림:

```text
+--------------------------------+
| 중요한 kernel 작업 시작         |
+----------------+---------------+
                 |
                 v
+--------------------------------+
| interrupt mask 설정             |
| 방해받으면 안 되는 interrupt 차단|
+----------------+---------------+
                 |
                 v
+--------------------------------+
| list / scheduler 상태 변경       |
+----------------+---------------+
                 |
                 v
+--------------------------------+
| interrupt mask 복구             |
+--------------------------------+
```

common kernel은 interrupt를 잠깐 막아야 한다는 개념만 씁니다.

구체적으로 Cortex-M4F에서 어떤 register를 어떻게 건드리는지는 port가 담당합니다.

## critical section도 portmacro.h를 통해 사용한다

Critical section은 이 구간은 중간에 끊기면 안 된다는 뜻입니다.

```text
portENTER_CRITICAL()
    |
    v
중요한 코드 실행
    |
    v
portEXIT_CRITICAL()
```

그림:

```text
+--------------------------+
| portENTER_CRITICAL()     |
+------------+-------------+
             |
             v
+--------------------------+
| shared kernel data 수정  |
| ready list, queue 등     |
+------------+-------------+
             |
             v
+--------------------------+
| portEXIT_CRITICAL()      |
+--------------------------+
```

여기서도 common kernel은 CPU 세부사항을 몰라도 됩니다.

```text
tasks.c:
    portENTER_CRITICAL();

portmacro.h / port.c:
    Cortex-M 방식으로 interrupt 제어
```

## StackType_t 같은 타입도 port가 정한다

CPU마다 자연스럽게 다루는 word 크기나 stack 단위가 다를 수 있습니다.

그래서 FreeRTOS는 stack type도 port에서 정의합니다.

```text
StackType_t
TickType_t
BaseType_t
UBaseType_t
```

그림:

```text
common code

+----------------------+
| StackType_t stack[]  |
| TickType_t tick      |
+----------------------+

        |
        v

portmacro.h

+----------------------+
| 이 CPU에서 StackType_t|
| 는 어떤 크기인가?     |
+----------------------+
```

즉 common kernel은 추상 타입을 쓰고, port가 실제 타입을 정합니다.

## port.c는 무엇을 구현할까?

`port.c`는 실제 Cortex-M4F용 동작을 구현합니다.

```text
FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c
```

대표적으로 이런 것들이 있습니다.

```text
1. initial stack frame construction
2. scheduler startup
3. SysTick setup and handling
4. PendSV context switching
5. interrupt priority validation
6. interrupt masking rules
```

하나씩 쉽게 봅시다.

## 1. Initial stack frame construction

새 task는 한 번도 실행된 적이 없습니다.

그런데 FreeRTOS는 새 task도 stack에서 context restore하는 방식으로 시작하고
싶습니다.

그래서 `port.c`가 새 task stack을 이렇게 꾸며줍니다.

```text
New Task Stack

+-----------------------------+
| fake initial context        |
|-----------------------------|
| PC = task function          |
| R0 = task parameter         |
| initial xPSR                |
| other register slots        |
+-----------------------------+
```

이 일을 하는 대표 함수가:

```text
pxPortInitialiseStack()
```

입니다.

그림:

```text
xTaskCreate()
    |
    v
pxPortInitialiseStack()
    |
    v
새 task stack에 fake context 생성
    |
    v
나중에 PendSV restore 시 task 함수 시작
```

## 2. Scheduler startup

Scheduler를 시작한다는 것은 이제 FreeRTOS가 task들을 실제로 실행하기 시작한다는
뜻입니다.

```text
vTaskStartScheduler()
    |
    v
port layer가 첫 task 실행 준비
```

Cortex-M port는 첫 task의 stack context를 복원해서 task 실행을 시작해야 합니다.

```text
scheduler start
    |
    v
pxCurrentTCB가 첫 task를 가리킴
    |
    v
첫 task의 stack에서 context 복원
    |
    v
첫 task running
```

그림:

```text
+--------------------------+
| vTaskStartScheduler()    |
+------------+-------------+
             |
             v
+--------------------------+
| port.c startup code      |
+------------+-------------+
             |
             v
+--------------------------+
| first task stack restore |
+------------+-------------+
             |
             v
+--------------------------+
| first task running       |
+--------------------------+
```

## 3. SysTick setup and handling

Cortex-M에는 SysTick timer가 있습니다.

FreeRTOS는 이것을 kernel tick으로 사용합니다.

```text
SysTick
    = FreeRTOS 시간 박자
```

`port.c`는 SysTick을 설정하고 handler를 제공합니다.

```text
xPortSysTickHandler()
    |
    v
xTaskIncrementTick()
    |
    v
필요하면 PendSV 요청
```

그림:

```text
+----------------------+
| SysTick hardware     |
+----------+-----------+
           |
           | interrupt
           v
+----------------------+
| xPortSysTickHandler  |
+----------+-----------+
           |
           v
+----------------------+
| xTaskIncrementTick   |
+----------+-----------+
           |
           v
+----------------------+
| tick 증가             |
| delayed task 깨우기   |
| switch 필요 판단      |
+----------------------+
```

## 4. PendSV context switching

PendSV는 실제 task 전환을 담당합니다.

```text
xPortPendSVHandler()
```

큰 흐름은 이렇습니다.

```text
PendSV
    |
    v
현재 task register 저장
    |
    v
현재 TCB의 pxTopOfStack 갱신
    |
    v
vTaskSwitchContext() 호출
    |
    v
pxCurrentTCB가 다음 task로 바뀜
    |
    v
다음 task stack에서 register 복원
    |
    v
다음 task 실행
```

그림:

```text
+------------------------------------------------+
| xPortPendSVHandler()                           |
|------------------------------------------------|
| old task context 저장                           |
| old TCB.pxTopOfStack 갱신                       |
| vTaskSwitchContext()                            |
| new TCB.pxTopOfStack 읽기                       |
| new task context 복원                           |
+------------------------------------------------+
```

여기서 common scheduler와 port가 만납니다.

```text
PendSV handler
    -> CPU register 저장/복원

vTaskSwitchContext()
    -> 다음 TCB 선택
```

## 5. interrupt priority validation

Cortex-M에서는 interrupt priority 규칙이 중요합니다.

FreeRTOS API를 ISR에서 호출할 때, 모든 interrupt가 다 FreeRTOS API를 호출할 수
있는 것은 아닙니다.

특정 priority 규칙을 지켜야 합니다.

```text
너무 높은 priority interrupt에서
FreeRTOS FromISR API를 호출하면 위험할 수 있음
```

그래서 `port.c`에는 interrupt priority 설정이 올바른지 확인하는 코드가
있습니다.

```text
interrupt priority validation
    =
    FreeRTOS API를 안전한 interrupt priority에서 호출하는지 확인
```

그림:

```text
ISR calls FreeRTOS API
        |
        v
+-------------------------------+
| interrupt priority가 안전한가? |
+-----------+-------------------+
            |
      +-----+-----+
      |           |
     Yes          No
      |           |
      v           v
  계속 진행    assert / error
```

## 6. interrupt masking rules

Cortex-M에서 interrupt를 완전히 다 막을 수도 있고, 특정 priority 이하만 막을
수도 있습니다.

FreeRTOS는 kernel 자료구조를 보호하기 위해 이 규칙을 사용합니다.

```text
portSET_INTERRUPT_MASK_FROM_ISR()
portCLEAR_INTERRUPT_MASK_FROM_ISR()
```

그림:

```text
ISR context
    |
    v
mask lower-priority interrupts
    |
    v
kernel critical update
    |
    v
restore interrupt mask
```

이런 세부사항은 common code가 아니라 `port.c`와 `portmacro.h`가 담당합니다.

## common kernel과 port의 관계

전체 관계를 한 장으로 보면 이렇습니다.

```text
+------------------------------------------------+
| FreeRTOS common kernel                         |
|------------------------------------------------|
| tasks.c                                        |
| queue.c                                        |
| list.c                                         |
|                                                |
| uses:                                          |
| - portYIELD()                                  |
| - portENTER_CRITICAL()                         |
| - portSET_INTERRUPT_MASK_FROM_ISR()            |
| - StackType_t                                  |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| portmacro.h                                    |
|------------------------------------------------|
| common kernel이 쓸 타입과 매크로 정의           |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| port.c                                         |
|------------------------------------------------|
| Cortex-M4F용 실제 구현                          |
| - SysTick                                      |
| - PendSV                                       |
| - initial stack frame                          |
| - interrupt masking                            |
| - scheduler startup                            |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| ARM Cortex-M4F hardware                         |
|------------------------------------------------|
| registers                                      |
| exception model                                |
| SysTick                                        |
| PendSV                                         |
| NVIC interrupt priority                        |
+------------------------------------------------+
```

## 왜 Cortex-M4F port를 먼저 공부하기 좋을까?

Cortex-M은 FreeRTOS context switch를 공부하기 좋습니다.

이유는 SysTick과 PendSV가 역할을 잘 나눠주기 때문입니다.

```text
SysTick
    = 시간 박자

PendSV
    = context switch
```

그림:

```text
SysTick
   |
   v
xTaskIncrementTick()
   |
   v
switch 필요하면 PendSV 요청
   |
   v
PendSV
   |
   v
실제 context switch
```

또 Cortex-M hardware가 exception 진입/복귀 때 context 일부를 자동으로 저장하고
복원해줍니다.

```text
Cortex-M exception entry
    -> 일부 register 자동 저장

Cortex-M exception return
    -> 일부 register 자동 복원
```

그래서 port code가 너무 거대하지 않고, context switch 구조가 비교적 잘
보입니다.

## Cortex-M4F port를 공부하면 보이는 큰 루프

```text
task 생성
    |
    v
pxPortInitialiseStack()
    |
    v
초기 stack frame 준비
    |
    v
ready list에 들어감
    |
    v
SysTick 발생
    |
    v
xTaskIncrementTick()
    |
    v
필요하면 PendSV 요청
    |
    v
PendSV
    |
    v
vTaskSwitchContext()
    |
    v
pxCurrentTCB 변경
    |
    v
새 task stack 복원
    |
    v
task 실행
```

그림:

```text
+-----------------------------+
| xTaskCreate()               |
+-------------+---------------+
              |
              v
+-----------------------------+
| pxPortInitialiseStack()     |
| fake initial frame 생성     |
+-------------+---------------+
              |
              v
+-----------------------------+
| Ready List                  |
+-------------+---------------+
              |
              v
+-----------------------------+
| SysTick                     |
| tick 증가                   |
+-------------+---------------+
              |
              v
+-----------------------------+
| PendSV                      |
| context switch              |
+-------------+---------------+
              |
              v
+-----------------------------+
| Task running                |
+-----------------------------+
```

## port를 공부할 때의 핵심 질문

Cortex-M4F port를 읽을 때는 이 질문들을 잡고 보면 됩니다.

```text
1. common code가 port에게 무엇을 요청하는가?
2. portYIELD()는 Cortex-M에서 무엇으로 바뀌는가?
3. SysTick handler는 xTaskIncrementTick()을 어떻게 호출하는가?
4. PendSV handler는 pxCurrentTCB를 어떻게 사용해서 stack을 바꾸는가?
5. pxPortInitialiseStack()은 새 task stack을 어떻게 준비하는가?
6. interrupt mask와 critical section은 어떻게 구현되는가?
```

이 질문을 기준으로 보면 `port.c`와 `portmacro.h`가 덜 어렵습니다.

## 다른 port를 볼 때도 도움이 된다

Cortex-M4F port를 이해하면 다른 FreeRTOS port를 볼 때 완전히 새롭게 느껴지지
않습니다.

공통 질문은 같습니다.

```text
이 CPU에서는 yield를 어떻게 구현하지?
이 CPU에서는 tick interrupt가 무엇이지?
이 CPU에서는 context switch interrupt가 무엇이지?
register는 어디에 저장하지?
stack pointer는 어떻게 바꾸지?
critical section은 어떻게 만들지?
```

CPU별 답이 다를 뿐입니다.

```text
Cortex-M:
    SysTick + PendSV

다른 CPU:
    다른 timer interrupt
    다른 trap/interrupt mechanism
    다른 register save/restore 방식
```

즉 Cortex-M4F port는 첫 번째 기준점이 됩니다.

## 최종 요약

```text
GCC ARM Cortex-M4F port
    = FreeRTOS common kernel을 Cortex-M4F CPU 위에서 실제로 동작하게 하는 계층

portmacro.h
    = common code가 사용하는 타입과 매크로를 정의
    = portYIELD, critical section, interrupt mask, stack type 등

port.c
    = Cortex-M4F-specific 구현
    = initial stack frame
    = scheduler startup
    = SysTick handler
    = PendSV context switch
    = interrupt priority validation
    = interrupt masking

common kernel
    = 어떤 task를 실행할지 결정
    = list, queue, scheduler logic 관리

port layer
    = CPU register, stack pointer, interrupt, exception 처리

Cortex-M이 첫 port로 좋은 이유
    = SysTick과 PendSV 역할이 명확함
    = exception hardware가 context 일부를 자동 저장/복원함
    = scheduler path가 비교적 잘 보임
```

가장 중요한 그림은 이것입니다.

```text
common kernel code
        |
        v
portmacro.h macros
        |
        v
port.c implementation
        |
        v
Cortex-M4F hardware


예:

tasks.c
    |
    | portYIELD()
    v
portmacro.h
    |
    v
PendSV pending
    |
    v
port.c PendSV handler
    |
    v
context switch
```

한 문장으로 정리하면:

```text
FreeRTOS의 common kernel은 CPU 독립적인 scheduler와 자료구조를 담당하고,
GCC ARM Cortex-M4F port는 그 결정을 Cortex-M4F의 SysTick, PendSV,
interrupt masking, stack/register 조작으로 실제 CPU 동작으로 바꿔주는 계층이다.
```
