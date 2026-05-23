# Cortex-M overview

이번 내용은 FreeRTOS가 Cortex-M CPU 위에서 context switch를 어떻게 나눠서
처리하는지 보는 부분입니다.

핵심은 이것입니다.

```text
Cortex-M은 interrupt/exception이 발생하면
CPU 상태 일부를 자동으로 stack에 저장해준다.

FreeRTOS는 나머지 상태를 PendSV에서 추가로 저장한다.

그래서 Cortex-M에서 FreeRTOS context switch를 공부하기가 비교적 좋다.
```

## context switch를 다시 떠올리기

Context switch는 이런 일입니다.

```text
Task A 실행 중
    |
    v
Task A를 멈춤
    |
    v
Task A의 CPU 상태 저장
    |
    v
Task B의 CPU 상태 복원
    |
    v
Task B 실행
```

그림으로 보면:

```text
+---------+       context switch       +---------+
| Task A  | -------------------------> | Task B  |
| running |                            | running |
+---------+                            +---------+
```

이때 중요한 질문은 이것입니다.

```text
Task A가 어디까지 실행했는지 어떻게 기억하지?
Task B는 어디서부터 다시 시작하지?
```

답은 task stack에 CPU 상태를 저장해두는 것입니다.

## CPU 상태란 무엇인가?

CPU는 task를 실행할 때 register를 사용합니다.

아주 단순하게 보면:

```text
+----------------------+
| CPU Registers        |
|----------------------|
| R0                   |
| R1                   |
| R2                   |
| R3                   |
| ...                  |
| PC                   |
| LR                   |
| xPSR                 |
+----------------------+
```

여기서 특히 중요한 것은 `PC`입니다.

```text
PC = Program Counter
   = CPU가 다음에 실행할 명령어 주소
```

즉 task를 멈췄다가 다시 실행하려면 이런 정보들이 필요합니다.

```text
어느 명령어까지 실행했는지
함수 호출 상태가 어떤지
지역 변수와 stack 상태가 어떤지
register 값이 무엇인지
```

이런 것들이 task의 context입니다.

```text
context = task를 나중에 이어서 실행하기 위한 CPU 실행 상태
```

## Cortex-M은 일부 context를 자동 저장한다

Cortex-M의 좋은 점은 exception이 발생하면 hardware가 CPU 상태 일부를 자동으로
stack에 저장해준다는 점입니다.

예를 들어 SysTick interrupt나 PendSV exception이 발생하면 CPU가 자동으로 이런
일을 합니다.

```text
exception entry
    |
    v
CPU가 일부 register를 현재 task stack에 자동 저장
```

그림:

```text
Before exception

+----------------+
| CPU Registers  |
+----------------+
        |
        | exception 발생
        v

+----------------+
| Task Stack     |
|----------------|
| auto-saved     |
| exception frame|
+----------------+
```

이 자동 저장된 부분을 보통 exception frame이라고 생각하면 됩니다.

```text
exception frame
    = Cortex-M hardware가 exception 진입 시 자동으로 stack에 쌓는 CPU 상태 일부
```

## 하지만 전부 저장해주지는 않는다

Cortex-M hardware가 모든 register를 자동으로 저장해주는 것은 아닙니다.

그래서 FreeRTOS port code가 나머지를 직접 저장합니다.

큰 그림은 이렇게 나뉩니다.

```text
Context 저장

+-----------------------------+
| Cortex-M hardware           |
|-----------------------------|
| exception entry 때          |
| 일부 register 자동 저장     |
+-----------------------------+

+-----------------------------+
| FreeRTOS PendSV handler     |
|-----------------------------|
| 나머지 register를 software로 |
| 직접 저장                   |
+-----------------------------+
```

즉 context는 두 조각으로 저장됩니다.

```text
1. hardware가 자동 저장한 부분
2. FreeRTOS가 직접 저장한 부분
```

## 두 조각으로 나뉜 context

그림으로 보면 task stack은 이런 느낌이 됩니다.

```text
Task A Stack

+--------------------------------+
| FreeRTOS가 저장한 register들   |
| software-saved context         |
+--------------------------------+
| Cortex-M이 자동 저장한 frame   |
| hardware exception frame       |
+--------------------------------+
```

더 단순하게:

```text
Task stack
    |
    +--> hardware saved part
    |
    +--> software saved part
```

전체 구조:

```text
+------------------------------+
|          Task Stack          |
|------------------------------|
|                              |
| software-saved registers     |
| by FreeRTOS PendSV           |
|                              |
|------------------------------|
| hardware exception frame     |
| by Cortex-M exception entry  |
|                              |
+------------------------------+
```

이 덕분에 FreeRTOS는 task stack을 이렇게 볼 수 있습니다.

```text
task stack
    = 이 task가 멈춘 지점을 기억하는 저장소
```

## 왜 task stack이 멈춘 위치 기록이 되는가?

Task A가 실행 중이라고 해봅시다.

```text
Task A running

+----------------+
| CPU Registers  |
+----------------+
```

Context switch가 필요해집니다.

```text
SysTick 또는 yield
    |
    v
PendSV 발생
```

그러면 Task A의 CPU 상태가 Task A stack에 저장됩니다.

```text
+----------------+
| CPU Registers  |
+-------+--------+
        |
        v
+-------------------------+
| Task A Stack            |
|-------------------------|
| saved context           |
+-------------------------+
```

그리고 TCB A가 이 stack 위치를 기억합니다.

```text
+-------------------------+
| TCB A                   |
|-------------------------|
| pxTopOfStack ----------+|
+------------------------||
                         ||
                         vv
                 +----------------+
                 | Task A Stack   |
                 | saved context  |
                 +----------------+
```

나중에 Task A가 다시 선택되면 이 stack에서 context를 복원합니다.

```text
TCB A.pxTopOfStack
        |
        v
Task A stack
        |
        v
CPU registers restore
        |
        v
Task A resumes
```

즉:

```text
stack에 context를 저장한다
    =
task가 어디서 멈췄는지 저장한다
```

## Cortex-M에서 중요한 exception 두 개

FreeRTOS scheduler 경로에서 중요한 Cortex-M exception은 보통 두 개입니다.

```text
SysTick
    = 시간 흐름을 만드는 interrupt

PendSV
    = context switch를 실제로 수행하는 exception
```

역할을 나눠보면:

```text
+----------------------+
| SysTick              |
|----------------------|
| tick 증가             |
| delayed task 깨우기   |
| switch 필요 여부 판단 |
+----------------------+

+----------------------+
| PendSV               |
|----------------------|
| old task context 저장 |
| next task 선택        |
| new task context 복원 |
+----------------------+
```

## SysTick은 시간을 전진시킨다

SysTick은 주기적으로 발생합니다.

```text
tick
tick
tick
tick
...
```

Cortex-M에서 SysTick interrupt가 발생하면 FreeRTOS는 대략 이렇게 처리합니다.

```text
SysTick
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
```

그림:

```text
+----------------------+
| SysTick Interrupt    |
+----------+-----------+
           |
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
| xTickCount++         |
| delayed task wake    |
+----------------------+
```

## SysTick은 context switch가 필요하다고 요청할 수 있다

예를 들어 Task A가 delay 중이었다고 합시다.

```text
Delayed List

+----------------------+
| Task A priority 3    |
| wake tick = 100      |
+----------------------+
```

현재 실행 중인 task는 Task B입니다.

```text
Running

+----------------------+
| Task B priority 2    |
+----------------------+
```

SysTick이 발생해서 tick이 100이 되었습니다.

```text
xTickCount = 100
```

그러면 Task A가 깨어납니다.

```text
Task A
    delayed list -> ready list
```

그런데 Task A의 priority가 Task B보다 높습니다.

```text
Task A priority 3
Task B priority 2
```

그러면 context switch가 필요합니다.

하지만 SysTick이 직접 register 저장/복원을 다 하지 않습니다.

대신 이렇게 요청합니다.

```text
SysTick
    |
    v
"PendSV야, context switch 해줘"
```

그림:

```text
+----------------------+
| SysTick              |
|----------------------|
| Task A를 ready로 이동 |
| switch 필요 판단      |
+----------+-----------+
           |
           v
+----------------------+
| PendSV pending       |
+----------------------+
```

## PendSV는 실제 context switch를 한다

PendSV는 context switch 전용으로 사용됩니다.

흐름은 대략 이렇습니다.

```text
PendSV
    |
    v
old task context 저장
    |
    v
vTaskSwitchContext() 호출
    |
    v
pxCurrentTCB를 new task로 변경
    |
    v
new task context 복원
```

그림:

```text
+-----------------------------+
| PendSV Handler              |
+-----------------------------+
| 1. 현재 task register 저장   |
|                             |
| 2. 현재 task의              |
|    TCB.pxTopOfStack 갱신     |
|                             |
| 3. vTaskSwitchContext()     |
|    다음 task 선택            |
|                             |
| 4. 새 task의                |
|    TCB.pxTopOfStack 읽기     |
|                             |
| 5. 새 task register 복원     |
+-----------------------------+
```

## SysTick과 PendSV의 관계

전체 흐름은 이렇게 보면 됩니다.

```text
SysTick
    |
    v
시간 증가
    |
    v
delayed task 깨움
    |
    v
더 높은 priority task가 ready가 됨
    |
    v
PendSV 요청
    |
    v
PendSV가 실제 context switch
```

그림:

```text
+----------------------+
| SysTick              |
|----------------------|
| xTickCount 증가       |
| delayed list 확인     |
| switch 필요 판단      |
+----------+-----------+
           |
           | request
           v
+----------------------+
| PendSV               |
|----------------------|
| save old task         |
| choose next task      |
| restore new task      |
+----------------------+
```

## 왜 SysTick이 직접 switch하지 않고 PendSV에 맡길까?

이유는 역할 분리입니다.

SysTick은 시간 관련 interrupt입니다.

```text
SysTick의 역할
    = 시간이 지났음을 알림
    = tick count 증가
    = delayed task 처리
```

PendSV는 context switch 전용입니다.

```text
PendSV의 역할
    = CPU 상태 저장/복원
    = 실제 task 전환
```

이렇게 나누면 구조가 깔끔합니다.

```text
SysTick:
    "시간이 지났고, switch가 필요해."

PendSV:
    "알겠어. 실제 register 저장/복원은 내가 할게."
```

비유하면:

```text
SysTick = 알람 시계
PendSV  = 실제 교대 근무를 바꾸는 관리자
```

알람 시계가 울린다고 직접 사람이 바뀌는 것은 아닙니다. 알람은 "바꿀 시간이 됐다"는
신호이고, 실제 교대는 PendSV가 합니다.

## 왜 PendSV는 낮은 priority로 두는가?

PendSV는 보통 낮은 interrupt priority로 설정됩니다.

이유는 간단히 말하면:

```text
더 급한 interrupt들이 먼저 처리되고,
context switch는 안전한 시점에 하도록 하기 위해서
```

예를 들어 더 중요한 interrupt가 처리 중일 때 바로 task switch를 해버리면 복잡해질
수 있습니다.

그래서 보통 구조는 이렇게 잡습니다.

```text
긴급한 interrupt
    먼저 처리

SysTick
    시간 처리

PendSV
    가장 나중에 context switch
```

그림:

```text
높은 priority interrupt
        |
        v
SysTick
        |
        v
PendSV
        |
        v
task context switch
```

핵심은 이것입니다.

```text
PendSV는 context switch를 미뤄두고,
낮은 priority에서 안전하게 처리하기 좋은 exception이다.
```

## task stack을 저장 파일처럼 보기

Cortex-M + FreeRTOS에서는 task stack이 매우 중요합니다.

각 task는 자기 stack을 가지고 있습니다.

```text
+----------------+     +----------------+     +----------------+
| Task A Stack   |     | Task B Stack   |     | Task C Stack   |
+----------------+     +----------------+     +----------------+
```

Context switch 때 현재 task의 CPU 상태가 자기 stack에 저장됩니다.

```text
Task A가 멈춤

CPU registers
      |
      v
Task A Stack
```

Task B를 실행할 때는 Task B stack에서 CPU 상태를 복원합니다.

```text
Task B Stack
      |
      v
CPU registers
```

즉 task stack은 이런 역할입니다.

```text
Task stack
    = 이 task의 실행 상태 저장 파일
```

## 전체 context switch 그림

Task A에서 Task B로 전환되는 전체 모습을 보겠습니다.

```text
[1] Task A running

+----------------+
| CPU            |
| running Task A |
+----------------+

pxCurrentTCB
     |
     v
+----------------+
| TCB A          |
+----------------+
```

```text
[2] SysTick 발생

+----------------+
| SysTick        |
+----------------+
        |
        v
xTickCount 증가
        |
        v
switch 필요 판단
        |
        v
PendSV pending
```

```text
[3] PendSV 시작: Task A context 저장

+----------------+
| CPU Registers  |
+-------+--------+
        |
        v
+----------------+
| Task A Stack   |
| saved context  |
+----------------+

TCB A.pxTopOfStack -> saved context 위치
```

```text
[4] 다음 task 선택

vTaskSwitchContext()
        |
        v
Ready List에서 Task B 선택
        |
        v
pxCurrentTCB -> TCB B
```

```text
[5] Task B context 복원

pxCurrentTCB
     |
     v
+----------------+
| TCB B          |
| pxTopOfStack --+----+
+----------------+    |
                      v
              +----------------+
              | Task B Stack   |
              | saved context  |
              +-------+--------+
                      |
                      v
              +----------------+
              | CPU Registers  |
              | restored B     |
              +----------------+
```

```text
[6] Task B running

+----------------+
| CPU            |
| running Task B |
+----------------+
```

## 한 장으로 전체 정리

```text
                    SysTick interrupt
                            |
                            v
+------------------------------------------------+
| SysTick path                                   |
|------------------------------------------------|
| xTickCount 증가                                |
| delayed list 확인                              |
| 깨어날 task를 ready list로 이동                |
| switch 필요하면 PendSV 요청                    |
+-----------------------+------------------------+
                        |
                        v
                    PendSV pending
                        |
                        v
+------------------------------------------------+
| PendSV handler                                 |
|------------------------------------------------|
| old task context 저장                           |
| old TCB.pxTopOfStack 갱신                       |
| vTaskSwitchContext() 호출                       |
| pxCurrentTCB를 next TCB로 변경                  |
| new TCB.pxTopOfStack에서 context 복원           |
+-----------------------+------------------------+
                        |
                        v
                    new task running
```

## 새 task는 어떻게 복원될까?

마지막 질문이 중요합니다.

```text
한 번도 실행된 적 없는 task는
저장된 context가 없는데 어떻게 restore하지?
```

답은 이것입니다.

```text
task 생성 시점에
stack에 fake initial stack frame을 미리 만들어 둔다.
```

즉 새 task는 실제로 실행된 적이 없지만, FreeRTOS가 stack을 이렇게 꾸며둡니다.

```text
New Task Stack

+-----------------------------+
| fake initial context        |
|-----------------------------|
| PC = task function address  |
| R0 = task parameter         |
| 기타 초기 register 값        |
+-----------------------------+
```

그래서 PendSV가 이 task를 restore하면:

```text
stack에서 context 복원
    |
    v
PC가 task 함수 주소가 됨
    |
    v
task 함수 시작
```

즉 새 task도 기존 task와 똑같이 처리할 수 있습니다.

```text
기존 task
    = 실제 저장된 context 복원

새 task
    = 미리 만든 fake context 복원
```

Scheduler 입장에서는 둘 다 같습니다.

```text
pxCurrentTCB->pxTopOfStack에서 복원한다
```

## 최종 요약

```text
Cortex-M exception
    = interrupt/exception 진입 시 CPU 상태 일부를 자동으로 stack에 저장

FreeRTOS PendSV handler
    = 하드웨어가 저장하지 않은 나머지 context를 software로 저장/복원

SysTick
    = 시간 관리
    = tick 증가
    = delayed task 깨우기
    = 필요하면 PendSV 요청

PendSV
    = 실제 context switch 담당
    = old task 저장
    = vTaskSwitchContext()로 next task 선택
    = new task 복원

task stack
    = task가 멈춘 위치와 CPU 상태를 기억하는 저장 공간

새 task
    = 처음부터 실행될 수 있도록 fake initial stack frame을 미리 만들어 둠
```

## 가장 중요한 그림

```text
SysTick
   |
   v
시간 증가
delayed task 깨움
switch 필요 판단
   |
   v
PendSV 요청
   |
   v
PendSV
   |
   +--> old task context 저장
   |
   +--> vTaskSwitchContext()
   |       |
   |       v
   |   pxCurrentTCB 변경
   |
   +--> new task context 복원
   |
   v
new task 실행
```

한 문장으로 정리하면:

```text
Cortex-M에서는 exception 진입 때 CPU가 context 일부를 자동 저장해주고,
FreeRTOS는 PendSV에서 나머지를 저장/복원한다.

SysTick은 시간이 흐른 것을 처리하고,
PendSV는 실제 task 전환을 수행한다.
```
