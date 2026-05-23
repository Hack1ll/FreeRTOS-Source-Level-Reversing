# The tick

이번 주제는 FreeRTOS에서 시간이 어떻게 흐르고, 시간이 흐를 때 scheduler가 무엇을
하는지입니다.

핵심은 이것입니다.

```text
FreeRTOS에서 시간은 tick 단위로 흐른다.

tick이 한 번 발생할 때마다 FreeRTOS는
1. 현재 시간을 1 증가시키고
2. delayed list를 확인하고
3. 깨어날 task를 ready list로 옮기고
4. 필요하면 context switch를 요청한다.
```

## tick이란?

FreeRTOS에서 `tick`은 운영체제의 기본 시간 단위입니다.

예를 들어 설정이 이렇게 되어 있다고 해봅시다.

```text
configTICK_RATE_HZ = 1000
```

그러면 1초에 tick이 1000번 발생합니다.

```text
1 tick = 1 ms
```

만약:

```text
configTICK_RATE_HZ = 100
```

이면:

```text
1 tick = 10 ms
```

즉 tick은 FreeRTOS가 시간을 세는 박자입니다.

```text
tick
tick
tick
tick
tick
...
```

## tick은 보통 SysTick interrupt에서 시작된다

Cortex-M에서는 보통 `SysTick`이라는 hardware timer가 주기적으로 interrupt를
발생시킵니다.

```text
Hardware Timer
    |
    | 주기적으로 interrupt 발생
    v
SysTick Interrupt
```

FreeRTOS Cortex-M port에서는 이 interrupt가 대략 이런 흐름으로 들어갑니다.

```text
SysTick interrupt 발생
        |
        v
xPortSysTickHandler()
        |
        v
xTaskIncrementTick()
```

그림으로 보면:

```text
+----------------------+
| Cortex-M SysTick     |
| hardware timer       |
+----------+-----------+
           |
           | interrupt
           v
+----------------------+
| xPortSysTickHandler  |
| port.c               |
+----------+-----------+
           |
           v
+----------------------+
| xTaskIncrementTick   |
| tasks.c              |
+----------------------+
```

## port code와 common scheduler code

여기서 두 층을 구분해야 합니다.

```text
port layer
    = CPU 구조에 의존적인 코드

common kernel code
    = CPU와 상관없는 FreeRTOS 공통 scheduler 코드
```

Cortex-M용 코드는 이런 역할을 합니다.

```text
xPortSysTickHandler()
    = Cortex-M interrupt 규칙에 맞게 진입하는 wrapper
```

공통 scheduler 코드는 이런 역할을 합니다.

```text
xTaskIncrementTick()
    = FreeRTOS의 시간을 증가시키고
      delayed task를 깨우는 공통 로직
```

그림:

```text
+--------------------------------+
| Cortex-M specific              |
|--------------------------------|
| xPortSysTickHandler()          |
| interrupt priority 처리         |
| Cortex-M 규칙 처리              |
+---------------+----------------+
                |
                v
+--------------------------------+
| FreeRTOS common scheduler      |
|--------------------------------|
| xTaskIncrementTick()           |
| xTickCount 증가                 |
| delayed list 확인               |
| ready list 이동                 |
+--------------------------------+
```

즉:

```text
port.c
    = 이 CPU에서 tick interrupt를 어떻게 다룰까?

tasks.c
    = tick이 왔으니 FreeRTOS 시간과 task 상태를 어떻게 바꿀까?
```

## xTickCount

FreeRTOS는 현재 시간을 `xTickCount`로 셉니다.

```text
xTickCount = 현재 tick 값
```

Tick interrupt가 한 번 올 때마다 증가합니다.

```text
tick 발생 전

xTickCount = 100

tick 발생 후

xTickCount = 101
```

흐름:

```text
xTaskIncrementTick()
    |
    v
xTickCount++
```

그림:

```text
Before tick

+----------------+
| xTickCount=100 |
+----------------+

SysTick interrupt

After tick

+----------------+
| xTickCount=101 |
+----------------+
```

## tick이 delayed list를 확인한다

이전에 `vTaskDelay()`를 배웠습니다.

예를 들어 Task A가 이렇게 호출했다고 합시다.

```c
vTaskDelay( 50 );
```

현재 tick이 100이었다면:

```text
wake tick = 150
```

Task A는 delayed list에 들어갑니다.

```text
Delayed List

+------------------+
| Task A           |
| wake tick = 150  |
+------------------+
```

이제 tick이 증가하면서 FreeRTOS는 확인합니다.

```text
현재 tick이 Task A의 wake tick에 도달했나?
```

## delayed task 깨우기

현재 상황:

```text
xTickCount = 149

Delayed List
+------------------+
| Task A           |
| wake tick = 150  |
+------------------+
```

Tick interrupt가 발생합니다.

```text
xTickCount = 150
```

이제 Task A를 깨울 수 있습니다.

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
wake tick이 된 task 발견
    |
    v
delayed list에서 제거
    |
    v
ready list에 추가
```

그림:

```text
Before tick 150

Delayed List
+------------------+
| Task A           |
| wake tick = 150  |
+------------------+

Ready List
+------------------+
| Task B           |
+------------------+

SysTick interrupt
xTickCount becomes 150

After

Delayed List
empty

Ready List
+------------------+     +------------------+
| Task B           | --> | Task A           |
+------------------+     +------------------+
```

## tick은 task를 직접 실행하는 게 아니다

중요한 점입니다.

Tick이 Task A를 깨운다는 말은:

```text
Task A를 ready list로 옮긴다
```

라는 뜻입니다. 즉, 바로 실행시킨다는 뜻은 아닙니다.

```text
wake up
    =
ready 상태로 만든다
```

실제로 실행할지는 scheduler가 priority를 보고 결정합니다.

```text
Task A가 깨어남
    |
    v
ready list에 들어감
    |
    v
scheduler가 priority 비교
    |
    v
실행할지 결정
```

## tick이 context switch를 요청할 수 있다

예를 들어 현재 Task B가 실행 중입니다.

```text
Running

+---------------------+
| Task B priority 2   |
+---------------------+
```

Delayed list에는 Task A가 있습니다.

```text
Delayed List

+---------------------+
| Task A priority 3   |
| wake tick = 150     |
+---------------------+
```

Tick이 150이 되면 Task A가 ready list로 돌아옵니다.

```text
Task A priority 3
Task B priority 2
```

Task A가 더 높은 priority입니다. 그러면 FreeRTOS는 이렇게 생각합니다.

```text
"방금 깨어난 Task A가 현재 실행 중인 Task B보다 더 중요하다.
context switch가 필요하다."
```

흐름:

```text
tick 발생
    |
    v
Task A wake
    |
    v
Task A가 current task보다 priority 높음
    |
    v
context switch 요청
```

그림:

```text
Before tick

Running
+-------------------+
| Task B prio 2     |
+-------------------+

Delayed List
+-------------------+
| Task A prio 3     |
| wake tick = 150   |
+-------------------+

tick = 150

After delayed processing

Ready List priority 3
+-------------------+
| Task A            |
+-------------------+

Running
+-------------------+
| Task B prio 2     |
+-------------------+

결론:
Task A가 더 높으므로 switch 필요
```

## Cortex-M에서는 PendSV로 context switch를 미룬다

Cortex-M에서 실제 context switch는 보통 `PendSV` exception에서 처리됩니다.

Tick handler가 직접 모든 register 저장/복원을 다 해버리는 게 아닙니다.

대신 이렇게 합니다.

```text
tick handler
    |
    v
"context switch 필요함"
    |
    v
PendSV를 pending 상태로 만듦
```

흐름:

```text
tick wakes higher-priority task
    |
    v
portYIELD()
    |
    v
PendSV pending
    |
    v
PendSV Handler에서 실제 context switch
```

그림:

```text
+----------------------+
| SysTick Handler      |
|----------------------|
| xTickCount 증가       |
| delayed task 깨움     |
| switch 필요 판단      |
+----------+-----------+
           |
           | portYIELD()
           v
+----------------------+
| PendSV pending       |
+----------+-----------+
           |
           v
+----------------------+
| PendSV Handler       |
|----------------------|
| 현재 task context 저장|
| 다음 task context 복원|
+----------------------+
```

## 왜 PendSV를 따로 쓸까?

Cortex-M에서는 interrupt마다 priority가 있습니다.

SysTick은 시간 관리 interrupt입니다. PendSV는 context switch를 위해 낮은 priority로
설정해두는 경우가 많습니다.

이렇게 하면 역할이 나뉩니다.

```text
SysTick handler:
    "tick 처리만 하고, switch가 필요하다고 표시"

PendSV handler:
    "안전한 시점에 실제 context switch 수행"
```

즉:

```text
SysTick
    = 시간 증가, task 깨우기

PendSV
    = 실제 register 저장/복원
```

그림:

```text
+----------------------------+
| SysTick                    |
|----------------------------|
| 시간 관련 작업              |
| xTaskIncrementTick()       |
| 필요하면 PendSV 요청        |
+----------------------------+

+----------------------------+
| PendSV                     |
|----------------------------|
| context switch 전용         |
| CPU register 저장/복원      |
+----------------------------+
```

이렇게 하면 interrupt 처리 구조가 분리됩니다.

## 전체 흐름: tick에서 context switch까지

```text
SysTick interrupt 발생
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
깨어날 task가 있나?
        |
   +----+----+
   |         |
  No        Yes
   |         |
   v         v
return   task를 ready list로 이동
             |
             v
      현재 task보다 priority 높나?
             |
        +----+----+
        |         |
       No        Yes
        |         |
        v         v
      return   portYIELD()
                  |
                  v
             PendSV pending
                  |
                  v
          실제 context switch
```

## time slicing도 tick과 관련 있다

이번에는 priority가 같은 task 여러 개가 있다고 합시다.

```text
Priority 2 Ready List

+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+
```

이 task들은 priority가 같기 때문에, 한 task만 계속 실행하면 불공평할 수 있습니다.

FreeRTOS에서 time slicing이 켜져 있으면 tick마다 같은 priority task들 사이에서
순서를 바꿀 수 있습니다.

```text
tick 1 -> Task A
tick 2 -> Task B
tick 3 -> Task C
tick 4 -> Task A
```

그림:

```text
Priority 2 Ready List

Tick 1

pxIndex
  |
  v
+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+

Tick 2

                pxIndex
                  |
                  v
+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+

Tick 3

                              pxIndex
                                |
                                v
+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+
```

즉 tick은 시간 지연만 처리하는 게 아닙니다.

```text
tick은 같은 priority task 사이의 실행 기회 분배에도 관여한다.
```

## delayed wake와 time slicing 비교

Tick이 하는 중요한 일은 크게 두 가지로 보면 됩니다.

```text
1. 시간이 된 task 깨우기
2. 같은 priority task 사이에서 순서 바꾸기
```

그림:

```text
SysTick
   |
   +--> xTickCount 증가
   |
   +--> delayed list 확인
   |       |
   |       +--> wake tick 도달 task를 ready list로 이동
   |
   +--> time slicing 확인
           |
           +--> 같은 priority ready task가 여러 개면 교대 가능
```

## tick과 ready list의 관계

Tick은 delayed list에서 ready list로 task를 옮깁니다.

```text
Delayed List
    |
    | wake tick 도달
    v
Ready List
```

그림:

```text
Before

Delayed List
+------------------+
| Task A           |
| wake tick = 200  |
+------------------+

Ready List priority 3
empty

tick reaches 200

After

Delayed List
empty

Ready List priority 3
+------------------+
| Task A           |
+------------------+
```

그리고 ready list에 들어온 task가 현재 task보다 priority가 높으면 context switch가
요청됩니다.

```text
Ready List에 새 high-priority task 등장
        |
        v
portYIELD()
        |
        v
PendSV
```

## tick과 vTaskDelay()는 짝이다

`vTaskDelay()`는 task를 delayed list에 넣습니다.

```text
vTaskDelay()
    |
    v
Ready List -> Delayed List
```

Tick은 시간이 되면 다시 ready list로 보냅니다.

```text
xTaskIncrementTick()
    |
    v
Delayed List -> Ready List
```

둘을 합치면:

```text
Task A running
     |
     | vTaskDelay(100)
     v
Delayed List
     |
     | tick이 100번 지나감
     v
Ready List
     |
     | scheduler가 선택
     v
Task A running again
```

그림:

```text
+---------+
| Task A  |
| Running |
+----+----+
     |
     | vTaskDelay(100)
     v
+----------------+
| Delayed List   |
| wake tick=200  |
+----+-----------+
     |
     | xTaskIncrementTick()
     | tick reaches 200
     v
+----------------+
| Ready List     |
| Task A         |
+----+-----------+
     |
     | scheduler chooses
     v
+---------+
| Task A  |
| Running |
+---------+
```

## tick handler가 모든 task를 검사하지 않는 이유

FreeRTOS는 delayed task들을 wake tick 순서로 delayed list에 넣습니다.

```text
Delayed List

+------------------+     +------------------+     +------------------+
| Task A           | --> | Task B           | --> | Task C           |
| wake tick = 120  |     | wake tick = 150  |     | wake tick = 220  |
+------------------+     +------------------+     +------------------+
```

현재 tick이 121이면:

```text
Task A는 깨움
Task B는 아직 아님
```

Delayed list가 정렬되어 있으므로, 뒤쪽 task들은 더 늦게 깨어납니다.

```text
Task B가 아직 wake tick이 안 됐다
    |
    v
Task C는 볼 필요가 적다
```

그래서 tick 처리 비용을 줄일 수 있습니다.

## tick 전체 그림

```text
                     +----------------------+
                     | Hardware SysTick     |
                     +----------+-----------+
                                |
                                | interrupt
                                v
                     +----------------------+
                     | xPortSysTickHandler  |
                     | Cortex-M port layer  |
                     +----------+-----------+
                                |
                                v
                     +----------------------+
                     | xTaskIncrementTick   |
                     | common scheduler     |
                     +----------+-----------+
                                |
       +------------------------+-------------------------+
       |                        |                         |
       v                        v                         v
+--------------+      +-------------------+      +-------------------+
| xTickCount++ |      | delayed list 확인 |      | time slicing 확인 |
+--------------+      +--------+----------+      +---------+---------+
                              |                           |
                              v                           v
                    +-------------------+       +--------------------+
                    | expired task를    |       | same-priority task |
                    | ready list로 이동 |       | rotation 가능      |
                    +--------+----------+       +---------+----------+
                             |                            |
                             +-------------+--------------+
                                           |
                                           v
                                +---------------------+
                                | switch 필요하면     |
                                | portYIELD()         |
                                +----------+----------+
                                           |
                                           v
                                +---------------------+
                                | PendSV pending      |
                                +----------+----------+
                                           |
                                           v
                                +---------------------+
                                | context switch      |
                                +---------------------+
```

## 예시로 보기

현재 상태:

```text
xTickCount = 99

Running:
+-------------------+
| Task B priority 2 |
+-------------------+

Delayed List:
+-------------------+
| Task A priority 3 |
| wake tick = 100   |
+-------------------+
```

Tick interrupt 발생:

```text
xTickCount = 100
```

FreeRTOS가 delayed list를 확인합니다.

```text
Task A wake tick = 100
현재 tick = 100

Task A를 깨울 수 있음
```

Task A를 ready list로 옮깁니다.

```text
Ready List priority 3:
+-------------------+
| Task A            |
+-------------------+
```

이제 priority를 비교합니다.

```text
Task A priority 3
Task B priority 2
```

Task A가 더 높습니다.

```text
context switch 필요
```

Cortex-M에서는:

```text
portYIELD()
    |
    v
PendSV pending
    |
    v
PendSV handler에서 Task B -> Task A switch
```

결과:

```text
Running:
+-------------------+
| Task A priority 3 |
+-------------------+
```

## SysTick과 PendSV의 역할 차이

```text
SysTick
    = 시간이 흘렀음을 알리는 interrupt

xTaskIncrementTick()
    = FreeRTOS의 시간 관리 함수

PendSV
    = 실제 context switch 담당 exception
```

표처럼 보면:

```text
+----------------------+--------------------------------+
| SysTick              | 시간 증가, delayed task 깨우기  |
+----------------------+--------------------------------+
| xTaskIncrementTick() | scheduler의 tick 처리 로직      |
+----------------------+--------------------------------+
| PendSV               | CPU context 저장/복원           |
+----------------------+--------------------------------+
```

## 최종 요약

```text
tick
    = FreeRTOS의 시간 단위

SysTick interrupt
    = Cortex-M에서 tick을 발생시키는 hardware interrupt

xPortSysTickHandler()
    = Cortex-M port layer의 tick handler

xTaskIncrementTick()
    = FreeRTOS 공통 tick 처리 함수
    = xTickCount 증가
    = delayed list 확인
    = wake tick이 된 task를 ready list로 이동

portYIELD()
    = context switch가 필요하다고 port layer에 요청

PendSV
    = Cortex-M에서 실제 context switch를 수행하는 exception

time slicing
    = 같은 priority task들이 tick마다 번갈아 실행될 수 있게 하는 동작
```

## 가장 중요한 그림

```text
SysTick interrupt
        |
        v
xPortSysTickHandler()
        |
        v
xTaskIncrementTick()
        |
        +--> xTickCount 증가
        |
        +--> delayed list 확인
        |       |
        |       +--> 깨어날 task를 ready list로 이동
        |
        +--> time slicing 처리
        |
        +--> switch 필요하면 portYIELD()
                        |
                        v
                  PendSV pending
                        |
                        v
                 context switch
```

한 문장으로 정리하면:

```text
FreeRTOS의 tick은 시간이 흘렀다는 신호이고,
tick handler는 delayed task를 ready list로 옮기며,
필요하면 PendSV를 통해 context switch를 요청한다.
```

더 짧게 말하면:

```text
tick은 FreeRTOS에서
시간 관리 + task 깨우기 + scheduling 기회
를 만드는 박자다.
```
