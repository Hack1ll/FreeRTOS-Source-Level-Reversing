# PendSV

이번 주제는 PendSV입니다.

앞에서 SysTick은 시간이 흘렀고 context switch가 필요할 수 있다고 알려주는
역할이었습니다. PendSV는 실제로 task를 바꾸는 곳입니다.

핵심은 이것입니다.

```text
PendSV
    = 현재 task의 CPU 상태를 stack에 저장하고
      다음 task의 stack에서 CPU 상태를 복원하는 exception
```

즉, scheduler의 결정이 실제 CPU 상태 변화로 바뀌는 지점입니다.

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c`
- `FreeRTOS-Kernel/tasks.c`

## 전체 그림 먼저 보기

Task A에서 Task B로 바뀐다고 해봅시다.

```text
Before

CPU
+----------------+
| running Task A |
+----------------+

pxCurrentTCB
     |
     v
+----------------+
| TCB A          |
+----------------+
```

PendSV가 실행되면:

```text
PendSV
    |
    v
Task A의 register를 Task A stack에 저장
    |
    v
vTaskSwitchContext()로 다음 task 선택
    |
    v
pxCurrentTCB가 TCB B를 가리킴
    |
    v
Task B stack에서 register 복원
    |
    v
Task B 실행
```

결과:

```text
After

CPU
+----------------+
| running Task B |
+----------------+

pxCurrentTCB
     |
     v
+----------------+
| TCB B          |
+----------------+
```

## PendSV는 왜 필요한가?

SysTick은 주기적으로 발생해서 시간을 증가시킵니다.

```text
SysTick
    |
    v
xTickCount 증가
    |
    v
delayed task 깨움
    |
    v
switch 필요하면 PendSV 요청
```

하지만 SysTick이 직접 task를 바꾸지는 않습니다.

```text
SysTick:
    "context switch가 필요해."

PendSV:
    "알겠어. 실제 CPU 상태 저장/복원은 내가 할게."
```

그림:

```text
+----------------------+
| SysTick              |
|----------------------|
| 시간 증가             |
| delayed task 깨우기   |
| switch 필요 판단      |
+----------+-----------+
           |
           | pend PendSV
           v
+----------------------+
| PendSV               |
|----------------------|
| 실제 context switch   |
+----------------------+
```

## PendSV handler의 큰 흐름

본문의 흐름을 더 쉽게 쓰면 이렇습니다.

```text
xPortPendSVHandler()
    |
    v
현재 task의 stack pointer를 읽음
    |
    v
현재 task의 추가 register들을 stack에 저장
    |
    v
저장 후 stack 위치를 현재 TCB의 pxTopOfStack에 기록
    |
    v
vTaskSwitchContext() 호출
    |
    v
pxCurrentTCB가 다음 task의 TCB로 바뀜
    |
    v
다음 task의 pxTopOfStack을 읽음
    |
    v
다음 task의 register들을 stack에서 복원
    |
    v
exception return
    |
    v
CPU가 다음 task 실행
```

그림:

```text
+------------------------------------------------+
| xPortPendSVHandler()                           |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 1. 현재 PSP 읽기                               |
|    현재 task stack 위치 확인                   |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 2. software-managed registers 저장             |
|    하드웨어가 자동 저장하지 않은 register 저장 |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 3. 현재 TCB의 pxTopOfStack 갱신                |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 4. vTaskSwitchContext() 호출                   |
|    다음 task 선택                              |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 5. 새 pxCurrentTCB->pxTopOfStack 읽기           |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 6. 새 task register 복원                       |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 7. exception return                            |
|    하드웨어 frame 복원 후 새 task 실행          |
+------------------------------------------------+
```

## Cortex-M은 일부 register를 자동 저장한다

Cortex-M에서 exception이 발생하면 hardware가 일부 CPU 상태를 자동으로 stack에
저장합니다.

```text
Exception entry
    |
    v
hardware가 일부 register를 stack에 자동 저장
```

이걸 아주 단순하게 표현하면:

```text
Task A Stack

+------------------------------+
| hardware-saved frame         |
| Cortex-M이 자동 저장한 부분  |
+------------------------------+
```

하지만 모든 register를 자동 저장하지는 않습니다.

그래서 PendSV handler가 나머지를 직접 저장합니다.

```text
Task A Stack

+------------------------------+
| software-saved registers     |
| FreeRTOS PendSV가 저장       |
+------------------------------+
| hardware-saved frame         |
| Cortex-M이 자동 저장         |
+------------------------------+
```

즉 context는 두 부분으로 저장됩니다.

```text
context
    = hardware-saved part
    + software-saved part
```

## 현재 task 저장하기

Task A가 실행 중입니다.

```text
CPU
+----------------+
| running Task A |
+----------------+

pxCurrentTCB
     |
     v
+----------------+
| TCB A          |
+----------------+
```

PendSV가 시작되면 현재 task의 stack pointer를 읽습니다.

```text
read current process stack pointer
```

쉽게 말하면:

```text
"Task A의 stack이 지금 어디까지 사용됐지?"
```

그다음 hardware가 자동 저장하지 않은 register들을 stack에 추가로 저장합니다.

```text
CPU registers
      |
      v
Task A Stack
```

그림:

```text
+--------------------------+
| CPU registers            |
| software-managed part    |
+------------+-------------+
             |
             | save
             v
+--------------------------+
| Task A Stack             |
|--------------------------|
| software-saved registers |
| hardware-saved frame     |
+--------------------------+
```

그리고 저장 후의 stack top을 TCB A에 기록합니다.

```text
TCB A.pxTopOfStack = saved stack top
```

그림:

```text
+--------------------------+
| TCB A                    |
|--------------------------|
| pxTopOfStack ------------+----+
+--------------------------+    |
                                v
                       +--------------------------+
                       | Task A Stack             |
                       | saved context            |
                       +--------------------------+
```

이제 Task A는 나중에 다시 복원될 수 있습니다.

## 중간에 vTaskSwitchContext()를 호출한다

이제 현재 task의 상태 저장이 끝났습니다.

다음으로 PendSV handler는 공통 scheduler 함수인 `vTaskSwitchContext()`를
호출합니다.

```text
vTaskSwitchContext()
    |
    v
가장 높은 priority ready list 찾기
    |
    v
다음 task 선택
    |
    v
pxCurrentTCB 변경
```

중요한 점:

```text
vTaskSwitchContext() 호출 전:
    pxCurrentTCB -> old task, 즉 Task A

vTaskSwitchContext() 호출 후:
    pxCurrentTCB -> new task, 즉 Task B
```

그림:

```text
Before vTaskSwitchContext()

pxCurrentTCB
     |
     v
+---------+
| TCB A   |
+---------+


vTaskSwitchContext()
    |
    v
ready list에서 Task B 선택


After vTaskSwitchContext()

pxCurrentTCB
     |
     v
+---------+
| TCB B   |
+---------+
```

이 함수가 바로 port-specific assembly와 common scheduler code의 연결점입니다.

```text
PendSV handler
    = CPU 상태 저장/복원 담당

vTaskSwitchContext()
    = 다음 task 선택 담당
```

## 다음 task 복원하기

이제 `pxCurrentTCB`는 Task B의 TCB를 가리킵니다.

```text
pxCurrentTCB
     |
     v
+--------------------------+
| TCB B                    |
| pxTopOfStack ------------+----+
+--------------------------+    |
                                v
                       +--------------------------+
                       | Task B Stack             |
                       | saved context            |
                       +--------------------------+
```

PendSV handler는 Task B의 `pxTopOfStack`을 읽습니다.

```text
load next task top-of-stack from pxCurrentTCB
```

그리고 그 stack에서 register를 복원합니다.

```text
Task B Stack
      |
      v
CPU registers
```

그림:

```text
+--------------------------+
| Task B Stack             |
|--------------------------|
| software-saved registers |
| hardware-saved frame     |
+------------+-------------+
             |
             | restore
             v
+--------------------------+
| CPU registers            |
| restored Task B state    |
+--------------------------+
```

마지막으로 exception return이 일어나면서 hardware가 저장했던 frame까지
복원합니다.

```text
exception return
    |
    v
hardware-saved frame 복원
    |
    v
Task B 실행
```

## exception return은 마지막 복원 단계다

PendSV handler가 software-saved registers를 복원한 뒤, exception에서
빠져나갑니다.

Cortex-M은 exception return 과정에서 hardware-saved frame을 자동으로
복원합니다.

```text
PendSV handler
    |
    v
software-saved registers 복원
    |
    v
exception return
    |
    v
hardware-saved frame 복원
    |
    v
Task B로 돌아감
```

그림:

```text
Task B Stack

+------------------------------+
| software-saved registers     |  <- PendSV가 복원
+------------------------------+
| hardware-saved frame         |  <- exception return이 복원
+------------------------------+
                |
                v
          Task B running
```

즉 PendSV가 모든 것을 혼자 다 복원하는 게 아니라, Cortex-M hardware의
exception return 동작과 협력합니다.

## pxTopOfStack이 왜 중요한가?

TCB에는 `pxTopOfStack`이 있습니다.

```text
TCB_t
+----------------------------+
| pxTopOfStack               |
| xStateListItem             |
| xEventListItem             |
| uxPriority                 |
| pxStack                    |
+----------------------------+
```

`pxTopOfStack`은 이 task의 저장된 context 위치를 가리킵니다.

```text
pxCurrentTCB
    |
    v
TCB_t
    |
    v
pxTopOfStack
    |
    v
saved register context
```

그림:

```text
pxCurrentTCB
     |
     v
+--------------------------+
| TCB A                    |
|--------------------------|
| pxTopOfStack ------------+----+
+--------------------------+    |
                                v
                       +--------------------------+
                       | Task A Stack             |
                       | saved register context   |
                       +--------------------------+
```

이 포인터가 정확해야 합니다.

만약 잘못되면 단순히 다른 task를 고르는 문제가 아닙니다.

```text
pxTopOfStack이 잘못됨
    |
    v
엉뚱한 메모리를 stack context라고 생각함
    |
    v
잘못된 register 값 복원
    |
    v
CPU가 이상한 주소로 점프하거나 crash
```

즉:

```text
pxTopOfStack
    = task 복원의 출발점
```

## pxTopOfStack이 TCB 초반에 있어야 하는 이유

Cortex-M port의 assembly 코드는 TCB의 layout을 믿고 동작합니다.

특히 FreeRTOS에서는 `pxTopOfStack`이 TCB의 앞쪽, 보통 첫 번째 필드에 있어야
한다는 전제가 중요합니다.

```text
TCB_t memory layout

+--------------------------+ offset 0
| pxTopOfStack             |  <- port assembly가 여기 있다고 기대
+--------------------------+
| xStateListItem           |
+--------------------------+
| xEventListItem           |
+--------------------------+
| uxPriority               |
+--------------------------+
```

만약 구조체 순서가 바뀌면?

```text
잘못된 layout

+--------------------------+ offset 0
| uxPriority               |
+--------------------------+
| pxTopOfStack             |
+--------------------------+
```

assembly는 여전히 offset 0을 `pxTopOfStack`으로 생각할 수 있습니다.

그러면 priority 값을 stack pointer처럼 읽어버릴 수 있습니다.

```text
port assembly:
    "offset 0에 stack pointer가 있겠지."

실제 구조체:
    "offset 0은 priority인데?"
```

결과는 매우 위험합니다.

```text
잘못된 stack pointer
    |
    v
잘못된 context restore
    |
    v
시스템 오동작
```

## PendSV 전체 흐름을 한 장으로 보기

```text
Task A running
     |
     | PendSV 발생
     v

+------------------------------------------------+
| PendSV entry                                   |
|------------------------------------------------|
| Cortex-M hardware가 일부 context 자동 저장      |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| 현재 PSP 읽기                                  |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| Task A의 software-managed registers 저장       |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| TCB A.pxTopOfStack 갱신                        |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| vTaskSwitchContext()                           |
| ready list에서 Task B 선택                     |
| pxCurrentTCB = TCB B                            |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| TCB B.pxTopOfStack 읽기                        |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| Task B의 software-managed registers 복원       |
+-----------------------+------------------------+
                        |
                        v
+------------------------------------------------+
| exception return                               |
| hardware-saved frame 복원                      |
+-----------------------+------------------------+
                        |
                        v
                   Task B running
```

## Task A stack과 Task B stack 변화

Task A를 저장할 때:

```text
Before save

Task A Stack
+------------------------------+
| existing stack data          |
+------------------------------+


PendSV saves context


After save

Task A Stack
+------------------------------+
| software-saved registers     |
+------------------------------+
| hardware-saved frame         |
+------------------------------+
| existing stack data          |
+------------------------------+
        ^
        |
TCB A.pxTopOfStack
```

Task B를 복원할 때:

```text
Before restore

TCB B.pxTopOfStack
        |
        v
Task B Stack
+------------------------------+
| software-saved registers     |
+------------------------------+
| hardware-saved frame         |
+------------------------------+
| existing stack data          |
+------------------------------+


PendSV restores


After restore

CPU registers = Task B context
Task B running
```

## PendSV와 vTaskSwitchContext의 관계

둘의 역할을 분리해서 보면 매우 쉽습니다.

```text
PendSV handler
    = CPU context 저장/복원

vTaskSwitchContext()
    = 다음 TCB 선택
```

그림:

```text
+--------------------------------+
| PendSV                         |
|--------------------------------|
| save old CPU state             |
+---------------+----------------+
                |
                v
+--------------------------------+
| vTaskSwitchContext()           |
|--------------------------------|
| choose next TCB                |
| pxCurrentTCB 변경              |
+---------------+----------------+
                |
                v
+--------------------------------+
| PendSV                         |
|--------------------------------|
| restore new CPU state          |
+--------------------------------+
```

즉 PendSV 안에 scheduler 선택 함수가 끼어 있습니다.

```text
PendSV
    |
    +-- old task 저장
    |
    +-- vTaskSwitchContext()
    |
    +-- new task 복원
```

## 첫 scheduler loop 완성

여기까지 보면 FreeRTOS의 기본 scheduler loop가 완성됩니다.

```text
Task A가 delay 또는 block됨
        |
        v
ready list에서 빠짐
        |
        v
tick 또는 event가 다른 task를 ready로 만듦
        |
        v
scheduler가 다음 TCB 선택
        |
        v
PendSV가 그 TCB의 stack을 복원
        |
        v
다음 task 실행
```

그림:

```text
+-------------------------+
| Task delays or blocks   |
+------------+------------+
             |
             v
+-------------------------+
| Ready list 변경         |
+------------+------------+
             |
             v
+-------------------------+
| Tick or event occurs    |
+------------+------------+
             |
             v
+-------------------------+
| 어떤 task가 ready가 됨  |
+------------+------------+
             |
             v
+-------------------------+
| vTaskSwitchContext()    |
| next TCB 선택           |
+------------+------------+
             |
             v
+-------------------------+
| PendSV                  |
| next stack 복원         |
+------------+------------+
             |
             v
+-------------------------+
| next task running       |
+-------------------------+
```

## 예시로 한 번에 보기

상황:

```text
현재 실행 중:
    Task A priority 2

깨어난 task:
    Task B priority 3
```

SysTick이 Task B를 ready list로 옮겼습니다.

```text
Ready List priority 3
+----------------+
| Task B         |
+----------------+
```

Task B가 더 높은 priority라서 PendSV가 요청됩니다.

```text
portYIELD()
    |
    v
PendSV pending
```

PendSV 실행:

```text
[1] Task A 저장

CPU registers
      |
      v
Task A stack

TCB A.pxTopOfStack = saved position
```

```text
[2] vTaskSwitchContext()

ready list에서 Task B 선택
pxCurrentTCB = TCB B
```

```text
[3] Task B 복원

TCB B.pxTopOfStack
      |
      v
Task B stack
      |
      v
CPU registers restore
```

결과:

```text
CPU
+----------------+
| running Task B |
+----------------+
```

## 비유: 책갈피 바꾸기

각 task는 자기 책을 읽고 있는 사람이라고 생각할 수 있습니다.

```text
Task A 책
Task B 책
Task C 책
```

context switch는 이런 일입니다.

```text
Task A 책을 읽다가 멈춤
    |
    v
Task A 책갈피 저장
    |
    v
다음에 읽을 책을 고름
    |
    v
Task B 책갈피를 펼침
    |
    v
Task B부터 읽기 시작
```

여기서:

```text
TCB.pxTopOfStack
    = 책갈피

PendSV
    = 책갈피를 저장하고 다른 책갈피를 펼치는 사람

vTaskSwitchContext()
    = 다음에 읽을 책을 고르는 사람
```

## 최종 요약

```text
PendSV
    = Cortex-M에서 FreeRTOS context switch를 실제로 수행하는 exception

xPortPendSVHandler()
    = 현재 task context 저장
    = vTaskSwitchContext() 호출
    = 새 task context 복원

vTaskSwitchContext()
    = ready list를 보고 다음 task를 선택
    = pxCurrentTCB를 새 task의 TCB로 변경

pxCurrentTCB
    = 현재 복원해야 할 task의 TCB를 가리키는 포인터

pxTopOfStack
    = 해당 task의 저장된 CPU context 위치

exception entry
    = Cortex-M hardware가 context 일부를 자동 저장

exception return
    = Cortex-M hardware가 저장된 frame 일부를 자동 복원
```

가장 중요한 그림은 이것입니다.

```text
PendSV
   |
   +--> old task stack에 context 저장
   |
   +--> old TCB.pxTopOfStack 갱신
   |
   +--> vTaskSwitchContext()
   |       |
   |       v
   |   pxCurrentTCB = next TCB
   |
   +--> next TCB.pxTopOfStack 읽기
   |
   +--> next task stack에서 context 복원
   |
   v
next task running
```

한 문장으로 정리하면:

```text
PendSV는 FreeRTOS에서 scheduler가 고른 다음 TCB를
실제 CPU 실행 상태로 바꿔주는 곳이다.

즉, vTaskSwitchContext()가 "누구를 실행할지" 정하면,
PendSV가 "그 task의 stack을 복원해서 실제로 실행되게" 만든다.
```
