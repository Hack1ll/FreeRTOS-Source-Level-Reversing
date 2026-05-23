# SysTick

이번 주제는 SysTick입니다.

SysTick은 FreeRTOS에서 시간이 한 칸 흘렀다는 신호를 주는 심장 박동 같은
역할을 합니다.

핵심은 이것입니다.

```text
SysTick
    = 주기적으로 발생하는 interrupt

FreeRTOS는 SysTick이 올 때마다
1. tick count를 증가시키고
2. delayed task를 깨울지 확인하고
3. 필요하면 context switch를 요청한다.
```

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c`
- `FreeRTOS-Kernel/tasks.c`
- `FreeRTOS-Kernel/portable/GCC/ARM_CM4F/portmacro.h`

## SysTick을 심장 박동처럼 보기

FreeRTOS는 시간을 초, 밀리초 단위로 직접 세기보다 `tick`이라는 단위로 셉니다.

```text
tick
tick
tick
tick
tick
...
```

Cortex-M에서는 보통 hardware timer인 SysTick이 주기적으로 interrupt를
발생시킵니다.

```text
+----------------------+
| Cortex-M SysTick     |
| hardware timer       |
+----------+-----------+
           |
           | interrupt
           v
+----------------------+
| FreeRTOS tick handler|
+----------------------+
```

즉 SysTick은 FreeRTOS에게 이렇게 알려주는 신호입니다.

```text
"시간이 한 칸 지났어."
```

## SysTick이 하는 일 한 줄 요약

SysTick interrupt가 발생하면 FreeRTOS는 대략 이렇게 움직입니다.

```text
SysTick interrupt
    |
    v
xPortSysTickHandler()
    |
    v
xTaskIncrementTick()
    |
    v
xTickCount 증가
    |
    v
delayed list 확인
    |
    v
필요하면 PendSV 요청
```

그림으로 보면:

```text
+-------------------------+
| SysTick interrupt       |
+------------+------------+
             |
             v
+-------------------------+
| xPortSysTickHandler()   |
| Cortex-M용 wrapper      |
+------------+------------+
             |
             v
+-------------------------+
| xTaskIncrementTick()    |
| FreeRTOS 공통 tick 처리 |
+------------+------------+
             |
             v
+-------------------------+
| tick 증가               |
| delayed task 깨우기     |
| switch 필요 판단        |
+-------------------------+
```

## 왜 xPortSysTickHandler()가 필요할까?

본문에서 중요한 함수는 이것입니다.

```text
xPortSysTickHandler()
```

이 함수는 Cortex-M 전용 tick handler입니다.

그런데 실제 FreeRTOS의 공통 시간 처리 로직은 여기에 있습니다.

```text
xTaskIncrementTick()
```

즉 역할이 나뉩니다.

```text
xPortSysTickHandler()
    = Cortex-M interrupt 환경에 맞게 감싸주는 함수

xTaskIncrementTick()
    = FreeRTOS 공통 scheduler tick 처리 함수
```

그림:

```text
+--------------------------------+
| Cortex-M specific              |
|--------------------------------|
| xPortSysTickHandler()          |
| interrupt masking 처리         |
| Cortex-M 규칙 처리             |
+---------------+----------------+
                |
                v
+--------------------------------+
| FreeRTOS common code           |
|--------------------------------|
| xTaskIncrementTick()           |
| xTickCount 증가                |
| delayed list 확인              |
| ready list 이동                |
+--------------------------------+
```

## interrupt mask란?

SysTick handler 안에는 이런 흐름이 나옵니다.

```text
xPortSysTickHandler()
    -> portSET_INTERRUPT_MASK_FROM_ISR()
    -> xTaskIncrementTick()
    -> portCLEAR_INTERRUPT_MASK_FROM_ISR()
```

처음 보면 복잡해 보이지만 의미는 단순합니다.

```text
tick 처리 중에
방해받으면 안 되는 interrupt를 잠깐 막고,
공통 tick 처리가 끝나면 다시 푼다.
```

그림으로 보면:

```text
+--------------------------------+
| xPortSysTickHandler()          |
+--------------------------------+
        |
        v
+--------------------------------+
| interrupt mask 설정            |
| 중요한 구간 보호               |
+--------------------------------+
        |
        v
+--------------------------------+
| xTaskIncrementTick() 실행      |
| tick count 증가                |
| delayed task 확인              |
+--------------------------------+
        |
        v
+--------------------------------+
| interrupt mask 해제            |
+--------------------------------+
```

쉽게 말하면:

```text
portSET_INTERRUPT_MASK_FROM_ISR()
    = ISR 안에서 잠깐 보호막 치기

portCLEAR_INTERRUPT_MASK_FROM_ISR()
    = 보호막 해제하기
```

## xTaskIncrementTick()은 무엇을 하나?

`xTaskIncrementTick()`은 FreeRTOS 공통 코드입니다.

이 함수의 핵심 역할은 다음과 같습니다.

```text
xTaskIncrementTick()
    |
    v
xTickCount 증가
    |
    v
delayed list 확인
    |
    v
깨어날 시간이 된 task를 ready list로 이동
    |
    v
context switch가 필요한지 알려줌
```

그림:

```text
+----------------------------+
| xTaskIncrementTick()       |
+------------+---------------+
             |
             v
+----------------------------+
| xTickCount++               |
+------------+---------------+
             |
             v
+----------------------------+
| delayed list 확인          |
+------------+---------------+
             |
             v
+----------------------------+
| wake tick 도달 task 찾기   |
+------------+---------------+
             |
             v
+----------------------------+
| ready list로 이동          |
+------------+---------------+
             |
             v
+----------------------------+
| switch 필요 여부 return    |
+----------------------------+
```

## delayed task를 깨우는 예시

Task A가 `vTaskDelay(50)`으로 잠들었다고 해봅시다.

현재 tick이 100이었다면:

```text
wake tick = 150
```

Task A는 delayed list에 있습니다.

```text
Delayed List

+----------------------+
| Task A               |
| wake tick = 150      |
+----------------------+
```

tick이 계속 증가합니다.

```text
xTickCount = 148
xTickCount = 149
xTickCount = 150
```

tick이 150이 되면 `xTaskIncrementTick()`이 Task A를 깨웁니다.

```text
Before

Delayed List
+----------------------+
| Task A               |
| wake tick = 150      |
+----------------------+

Ready List
empty


SysTick 발생
xTickCount = 150


After

Delayed List
empty

Ready List
+----------------------+
| Task A               |
+----------------------+
```

즉 SysTick은 잠든 task를 깨울 기회를 만듭니다.

```text
SysTick
    |
    v
xTaskIncrementTick()
    |
    v
Delayed List -> Ready List
```

## SysTick이 직접 task를 바꾸는 것은 아니다

중요한 포인트입니다.

SysTick은 context switch가 필요하다는 사실을 알 수 있습니다.

하지만 SysTick이 직접 CPU register를 저장하고, 다른 task stack을 복원하는 것은
아닙니다.

대신 이렇게 합니다.

```text
SysTick:
    "context switch가 필요하네."

portYIELD():
    "PendSV를 pending 상태로 만들자."

PendSV:
    "실제 context switch는 내가 할게."
```

그림:

```text
+--------------------------+
| SysTick handler          |
|--------------------------|
| tick 증가                |
| delayed task 깨움        |
| switch 필요 판단         |
+------------+-------------+
             |
             | portYIELD()
             v
+--------------------------+
| PendSV pending           |
+------------+-------------+
             |
             v
+--------------------------+
| PendSV handler           |
|--------------------------|
| old task context 저장    |
| next task 선택           |
| new task context 복원    |
+--------------------------+
```

## portYIELD()는 무엇인가?

`portYIELD()`는 간단히 말하면:

```text
"지금 task를 바꿔야 하니 PendSV를 실행해줘."
```

라는 요청입니다.

Cortex-M에서는 실제 context switch를 PendSV에서 처리하는 구조가 일반적입니다.

```text
xTaskIncrementTick()
    |
    v
switch 필요함
    |
    v
portYIELD()
    |
    v
PendSV pending
```

즉:

```text
portYIELD()
    = PendSV를 예약하는 요청
```

## 왜 PendSV에 맡길까?

SysTick은 시간 처리용 interrupt입니다.

```text
SysTick
    = 시간 증가
    = delayed task 처리
```

PendSV는 context switch 전용 exception입니다.

```text
PendSV
    = CPU register 저장
    = TCB 전환
    = CPU register 복원
```

역할을 나누면 코드가 깔끔해집니다.

```text
SysTick:
    시간 처리만 한다.
    필요하면 switch 요청만 한다.

PendSV:
    실제 task 전환을 한다.
```

그림:

```text
+----------------------+
| SysTick              |
|----------------------|
| 시간 관리             |
| xTickCount 증가       |
| delayed task 깨우기   |
+----------+-----------+
           |
           | switch request
           v
+----------------------+
| PendSV               |
|----------------------|
| context switch       |
| stack 저장/복원       |
+----------------------+
```

## 전체 흐름을 단계별로 보기

현재 Task B가 실행 중이라고 합시다.

```text
Running

+----------------------+
| Task B priority 2    |
+----------------------+
```

Delayed list에는 Task A가 있습니다.

```text
Delayed List

+----------------------+
| Task A priority 3    |
| wake tick = 100      |
+----------------------+
```

이제 SysTick이 발생해서 tick이 100이 됩니다.

```text
SysTick interrupt
    |
    v
xTickCount = 100
```

`xTaskIncrementTick()`은 Task A를 ready list로 옮깁니다.

```text
Ready List priority 3

+----------------------+
| Task A               |
+----------------------+
```

Task A의 priority가 현재 실행 중인 Task B보다 높습니다.

```text
Task A priority 3
Task B priority 2
```

그래서 switch가 필요합니다.

```text
xTaskIncrementTick()
    |
    v
"switch needed" 반환
```

그러면 port layer가 `portYIELD()`를 호출합니다.

```text
portYIELD()
    |
    v
PendSV pending
```

그 뒤 PendSV가 실제 전환을 합니다.

```text
PendSV
    |
    v
Task B 저장
    |
    v
Task A 복원
    |
    v
Task A 실행
```

전체 그림:

```text
Before SysTick

Running
+-------------------+
| Task B prio 2     |
+-------------------+

Delayed List
+-------------------+
| Task A prio 3     |
| wake tick = 100   |
+-------------------+


SysTick occurs


xTaskIncrementTick()

Delayed List
empty

Ready List prio 3
+-------------------+
| Task A            |
+-------------------+


Task A가 더 높은 priority
        |
        v
portYIELD()
        |
        v
PendSV pending
        |
        v
Task B -> Task A
```

## SysTick handler 안의 구조

본문의 흐름을 그림으로 자세히 보면:

```text
xPortSysTickHandler()
    |
    v
portSET_INTERRUPT_MASK_FROM_ISR()
    |
    v
xTaskIncrementTick()
    |
    v
portCLEAR_INTERRUPT_MASK_FROM_ISR()
    |
    v
필요하면 portYIELD()
```

조금 더 구조화하면:

```text
+------------------------------------------------+
| xPortSysTickHandler()                          |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 1. interrupt mask 설정                          |
|    중요한 tick 처리 중 방해를 줄임              |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 2. xTaskIncrementTick()                         |
|    FreeRTOS 공통 tick 처리                      |
|    - xTickCount 증가                            |
|    - delayed list 확인                          |
|    - ready list 이동                            |
|    - switch 필요 여부 반환                      |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 3. interrupt mask 해제                          |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 4. switch 필요하면 portYIELD()                  |
|    PendSV pending                               |
+------------------------------------------------+
```

## tasks.c가 CPU 구조를 몰라도 되는 이유

`tasks.c`는 FreeRTOS의 공통 scheduler 코드입니다.

만약 `tasks.c`가 Cortex-M의 interrupt priority, masking 규칙, PendSV 설정 등을
직접 알아야 한다면, 다른 CPU로 옮기기 어려워집니다.

그래서 FreeRTOS는 이렇게 나눕니다.

```text
port.c
    = Cortex-M의 interrupt 규칙 처리

tasks.c
    = FreeRTOS 공통 tick 처리
```

그림:

```text
+--------------------------------+
| port.c                         |
| Cortex-M specific              |
|--------------------------------|
| xPortSysTickHandler()          |
| interrupt mask 설정/해제        |
| PendSV 요청                    |
+---------------+----------------+
                |
                v
+--------------------------------+
| tasks.c                        |
| architecture-neutral           |
|--------------------------------|
| xTaskIncrementTick()           |
| xTickCount 증가                |
| delayed list 처리              |
| ready list 이동                |
+--------------------------------+
```

이 구조 덕분에 FreeRTOS는 여러 CPU에서 같은 scheduler 로직을 재사용할 수
있습니다.

## SysTick과 PendSV는 FreeRTOS Cortex-M의 랜드마크

Cortex-M source를 읽을 때 SysTick과 PendSV는 중요한 단서가 됩니다.

왜냐하면 FreeRTOS Cortex-M port에서는 보통 이런 패턴이 보이기 때문입니다.

```text
SysTick handler
    |
    v
xTaskIncrementTick()
    |
    v
switch 필요하면 PendSV pending

PendSV handler
    |
    v
실제 context switch
```

즉 source code를 보든 build 결과를 보든, 이 흐름은 FreeRTOS Cortex-M port를
알아보는 중요한 구조입니다.

```text
SysTick = 시간 박자
PendSV  = task 전환
```

## SysTick은 scheduling 기회를 만든다

SysTick은 단순히 시간을 증가시키는 것만이 아닙니다.

SysTick이 발생할 때마다 이런 일이 생길 수 있습니다.

```text
1. delay 중이던 task가 깨어남
2. 더 높은 priority task가 ready가 됨
3. 같은 priority task 간 time slicing이 필요해짐
4. context switch 요청이 발생함
```

즉 SysTick은 FreeRTOS에서 주기적인 scheduling 기회입니다.

```text
SysTick
    =
    시간 증가
    +
    task 깨우기
    +
    context switch 요청 가능성
```

## 한 장으로 전체 정리

```text
                    SysTick interrupt
                            |
                            v
+------------------------------------------------+
| xPortSysTickHandler()                          |
| Cortex-M port wrapper                          |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| portSET_INTERRUPT_MASK_FROM_ISR()              |
| ISR 안에서 중요한 구간 보호                    |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| xTaskIncrementTick()                           |
| FreeRTOS common tick logic                     |
|------------------------------------------------|
| xTickCount 증가                                |
| delayed list 확인                              |
| expired task를 ready list로 이동               |
| switch 필요 여부 반환                          |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| portCLEAR_INTERRUPT_MASK_FROM_ISR()            |
| interrupt mask 복구                            |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| switch가 필요하면 portYIELD()                  |
| PendSV pending                                 |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| PendSV handler                                 |
| 실제 context switch 수행                       |
+------------------------------------------------+
```

## 최종 요약

```text
SysTick
    = Cortex-M에서 주기적으로 발생하는 timer interrupt
    = FreeRTOS의 heartbeat

xPortSysTickHandler()
    = Cortex-M port layer의 SysTick handler
    = interrupt masking 규칙을 적용하고
      xTaskIncrementTick()을 호출

portSET_INTERRUPT_MASK_FROM_ISR()
    = tick 처리 중 필요한 interrupt 보호막 설정

xTaskIncrementTick()
    = FreeRTOS 공통 tick 처리 함수
    = xTickCount 증가
    = delayed list 확인
    = 깨어날 task를 ready list로 이동
    = context switch 필요 여부를 알려줌

portCLEAR_INTERRUPT_MASK_FROM_ISR()
    = interrupt mask 복구

portYIELD()
    = PendSV를 pending 상태로 만들어
      context switch를 요청

PendSV
    = 실제 task 전환을 수행하는 exception
```

가장 중요한 그림은 이것입니다.

```text
SysTick
   |
   v
xPortSysTickHandler()
   |
   v
interrupt mask 설정
   |
   v
xTaskIncrementTick()
   |
   +--> xTickCount 증가
   |
   +--> delayed task 깨움
   |
   +--> switch 필요 여부 판단
   |
   v
interrupt mask 해제
   |
   v
필요하면 portYIELD()
   |
   v
PendSV pending
   |
   v
실제 context switch
```

한 문장으로 정리하면:

```text
SysTick은 FreeRTOS의 시간 박자이고,
xTaskIncrementTick()으로 커널 시간을 전진시키며,
필요하면 portYIELD()를 통해 PendSV에게 context switch를 요청한다.
```
