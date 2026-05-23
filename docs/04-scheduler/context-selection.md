# Choosing the next context

이번 주제는 FreeRTOS가 다음에 어떤 task를 실행할지 고르는 순간입니다.

핵심은 이것입니다.

```text
vTaskSwitchContext()
    = CPU register를 저장/복원하는 함수가 아니다.

vTaskSwitchContext()
    = 다음에 실행할 TCB_t를 고르고,
      pxCurrentTCB가 그 TCB_t를 가리키게 바꾸는 함수다.
```

## context switch를 둘로 나눠서 봐야 한다

처음에는 context switch를 하나의 큰 동작으로 생각하기 쉽습니다.

```text
context switch
    = Task A 멈추고 Task B 실행
```

그런데 FreeRTOS 내부에서는 이걸 크게 두 부분으로 나눕니다.

```text
[1] scheduler의 일
    다음에 실행할 task를 고른다.

[2] port layer의 일
    CPU register를 실제로 저장하고 복원한다.
```

그림으로 보면:

```text
+--------------------------------+
| FreeRTOS common scheduler      |
| tasks.c                        |
|--------------------------------|
| 다음 task를 고른다             |
| pxCurrentTCB를 바꾼다          |
+---------------+----------------+
                |
                v
+--------------------------------+
| Port-specific code             |
| ARM_CM4F/port.c                |
|--------------------------------|
| CPU register 저장              |
| stack pointer 저장             |
| CPU register 복원              |
+--------------------------------+
```

즉:

```text
vTaskSwitchContext()
    = 누구를 실행할지 고르는 함수

PendSV handler 같은 port code
    = 실제 CPU 상태를 바꾸는 함수
```

## pxCurrentTCB가 핵심이다

FreeRTOS에서 현재 실행 중인 task는 `pxCurrentTCB`가 가리킵니다.

```text
pxCurrentTCB
     |
     v
+-------------+
| TCB of A    |
| Task A      |
+-------------+
```

즉:

```text
pxCurrentTCB = 지금 실행 중인 task의 TCB
```

Context switch 전에는 Task A를 가리키고 있을 수 있습니다.

```text
Before switch

pxCurrentTCB
     |
     v
+-------------+
| TCB A       |
+-------------+
```

`vTaskSwitchContext()`가 실행되면 다음 task를 고릅니다.

```text
vTaskSwitchContext()
    |
    v
ready list에서 다음 task 선택
```

그 결과 `pxCurrentTCB`가 Task B를 가리키게 바뀝니다.

```text
After switch decision

pxCurrentTCB
     |
     v
+-------------+
| TCB B       |
+-------------+
```

이 포인터 하나가 바뀌는 것이 중요합니다.

```text
pxCurrentTCB가 바뀐다
    =
port layer가 복원할 stack도 바뀐다
    =
다음에 실행될 task가 바뀐다
```

## vTaskSwitchContext()가 하는 일

`vTaskSwitchContext()`의 일을 단순화하면 이렇습니다.

```text
vTaskSwitchContext()
    |
    v
가장 높은 priority의 ready list를 찾는다
    |
    v
그 list에서 다음 task를 고른다
    |
    v
그 task의 TCB_t를 찾는다
    |
    v
pxCurrentTCB를 그 TCB_t로 바꾼다
```

그림:

```text
+-----------------------------+
| vTaskSwitchContext()        |
+-------------+---------------+
              |
              v
+-----------------------------+
| 가장 높은 priority ready list|
| 찾기                         |
+-------------+---------------+
              |
              v
+-----------------------------+
| 그 list에서 다음 item 선택   |
+-------------+---------------+
              |
              v
+-----------------------------+
| item->pvOwner로 TCB 찾기     |
+-------------+---------------+
              |
              v
+-----------------------------+
| pxCurrentTCB = 선택된 TCB    |
+-----------------------------+
```

## ready list에서 task를 고르는 모습

예를 들어 ready list들이 이렇게 있다고 해봅시다.

```text
pxReadyTasksLists

Priority 3 Ready List
+----------------------+
| Task B state item    | ----> TCB B
+----------------------+

Priority 2 Ready List
+----------------------+     +----------------------+
| Task A state item    | --> | Task C state item    |
| pvOwner -> TCB A     |     | pvOwner -> TCB C     |
+----------------------+     +----------------------+

Priority 1 Ready List
+----------------------+
| Task D state item    | ----> TCB D
+----------------------+
```

가장 높은 priority 중 비어 있지 않은 list는 priority 3입니다.

```text
Priority 3 list가 비어 있지 않음
    |
    v
Task B 선택
```

그다음 list item의 `pvOwner`를 따라 TCB를 찾습니다.

```text
Task B state item
       |
       v
pvOwner
       |
       v
TCB B
```

그리고:

```text
pxCurrentTCB = TCB B
```

가 됩니다.

## pxCurrentTCB가 바뀌기 전과 후

Task A가 실행 중이었다고 해봅시다.

```text
Before

CPU is running Task A

pxCurrentTCB
     |
     v
+----------------+
| TCB A          |
| pxTopOfStack   |
+----------------+
```

이제 scheduler가 Task B를 선택합니다.

```text
vTaskSwitchContext()
    |
    v
Task B 선택
```

결과:

```text
After

pxCurrentTCB
     |
     v
+----------------+
| TCB B          |
| pxTopOfStack   |
+----------------+
```

이제 port layer는 `pxCurrentTCB->pxTopOfStack`을 보고 Task B의 stack에서 CPU 상태를
복원할 수 있습니다.

```text
pxCurrentTCB
     |
     v
TCB B
     |
     v
pxTopOfStack
     |
     v
Task B stack
     |
     v
CPU register 복원
```

## vTaskSwitchContext()가 하지 않는 일

중요합니다. `vTaskSwitchContext()`는 이름 때문에 context switch 전체를 다 할 것처럼
보이지만, 실제로는 그렇지 않습니다.

`vTaskSwitchContext()`는 이런 일을 하지 않습니다.

```text
하지 않는 일:

CPU register 저장
R4-R11 저장
PSP(Process Stack Pointer) 쓰기
stack pointer 직접 변경
CPU register 복원
Task B로 직접 return
```

그럼 누가 하느냐?

```text
PendSV handler 같은 port-specific assembly 코드가 한다.
```

역할을 나누면 이렇게 됩니다.

```text
+--------------------------------+
| vTaskSwitchContext()           |
|--------------------------------|
| 다음 task 선택                 |
| pxCurrentTCB 변경              |
+--------------------------------+

+--------------------------------+
| PendSV handler                 |
|--------------------------------|
| 현재 task register 저장        |
| 현재 task pxTopOfStack 저장    |
| vTaskSwitchContext() 호출      |
| 새 task pxTopOfStack 읽기      |
| 새 task register 복원          |
+--------------------------------+
```

## context switch 전체 흐름

Task A에서 Task B로 바뀐다고 해봅시다.

```text
[1] Task A 실행 중

pxCurrentTCB
     |
     v
+---------+
| TCB A   |
+---------+
```

```text
[2] tick interrupt 또는 yield로 switch 필요

+----------------+
| switch request |
+----------------+
        |
        v
+----------------+
| PendSV pending |
+----------------+
```

```text
[3] PendSV handler가 Task A 상태 저장

CPU registers
      |
      v
Task A stack

+----------------+
| TCB A          |
| pxTopOfStack --+----> saved Task A stack top
+----------------+
```

```text
[4] vTaskSwitchContext()가 다음 task 선택

Ready Lists
    |
    v
Task B 선택
    |
    v
pxCurrentTCB = TCB B
```

```text
[5] PendSV handler가 Task B 상태 복원

pxCurrentTCB
     |
     v
+----------------+
| TCB B          |
| pxTopOfStack --+----> Task B stack
+----------------+
                          |
                          v
                  CPU registers restored
```

```text
[6] CPU는 Task B 실행

+---------+
| Task B  |
| running |
+---------+
```

전체를 한 장으로 보면:

```text
Task A running
     |
     v
PendSV handler
     |
     v
Save Task A registers to Task A stack
     |
     v
TCB A.pxTopOfStack = saved stack pointer
     |
     v
vTaskSwitchContext()
     |
     v
pxCurrentTCB = TCB B
     |
     v
Load Task B stack pointer from TCB B.pxTopOfStack
     |
     v
Restore Task B registers
     |
     v
Task B running
```

## scheduler와 port layer의 경계

`pxCurrentTCB`는 두 세계를 연결하는 경계입니다.

```text
Common scheduler world
    |
    | pxCurrentTCB를 바꿈
    v
Port-specific CPU world
    |
    | pxCurrentTCB->pxTopOfStack을 사용
    v
CPU register 복원
```

그림:

```text
+--------------------------------------+
| tasks.c                              |
| common scheduler                     |
|--------------------------------------|
| vTaskSwitchContext()                 |
|                                      |
| "다음 task는 TCB B야"                |
| pxCurrentTCB = TCB B                 |
+------------------+-------------------+
                   |
                   v
+--------------------------------------+
| port.c / assembly                    |
| Cortex-M specific                    |
|--------------------------------------|
| pxCurrentTCB->pxTopOfStack 읽기      |
| Task B register 복원                 |
+--------------------------------------+
```

즉 scheduler는 CPU register를 모릅니다.

```text
scheduler:
    "다음 task는 이 TCB야."
```

Port layer는 scheduling 정책을 모릅니다.

```text
port layer:
    "알겠어. 그 TCB의 stack에서 CPU 상태를 복원할게."
```

## 왜 이렇게 나눴을까?

FreeRTOS는 여러 CPU에서 동작합니다.

```text
ARM Cortex-M
RISC-V
AVR
PIC
Xtensa
...
```

CPU마다 register 구조와 context switch 방식이 다릅니다.

만약 scheduler 선택 로직과 register 저장/복원을 한 함수에 섞어버리면, CPU port마다
scheduler를 다시 구현해야 합니다.

나쁜 구조:

```text
Cortex-M scheduler + register switch
RISC-V scheduler + register switch
AVR scheduler + register switch
PIC scheduler + register switch
...
```

그러면 scheduler 로직이 여러 곳에 중복됩니다.

FreeRTOS는 이렇게 나눕니다.

```text
공통 부분:
    어떤 task를 고를 것인가?
    -> tasks.c의 vTaskSwitchContext()

CPU별 부분:
    register를 어떻게 저장/복원할 것인가?
    -> 각 port.c / assembly
```

그림:

```text
                 +-----------------------------+
                 | Common FreeRTOS scheduler   |
                 | tasks.c                     |
                 |-----------------------------|
                 | vTaskSwitchContext()        |
                 | ready list에서 task 선택    |
                 +--------------+--------------+
                                |
          +---------------------+----------------------+
          |                     |                      |
          v                     v                      v
+----------------+    +----------------+     +----------------+
| Cortex-M port  |    | RISC-V port    |     | AVR port       |
| register save  |    | register save  |     | register save  |
| register load  |    | register load  |     | register load  |
+----------------+    +----------------+     +----------------+
```

이렇게 하면 FreeRTOS의 핵심 scheduler는 공통으로 유지되고, CPU마다 필요한 낮은 수준
코드만 다르게 만들면 됩니다.

## 비유: 감독과 무대 장치팀

Scheduler는 감독입니다.

```text
감독:
    "다음 배우는 B야."
```

Port layer는 무대 장치팀입니다.

```text
무대 장치팀:
    "알겠습니다.
     조명을 바꾸고,
     세트를 바꾸고,
     배우 B가 무대에 서게 하겠습니다."
```

감독은 조명 케이블을 직접 만지지 않습니다. 무대 장치팀은 다음 배우를 마음대로
정하지 않습니다.

```text
vTaskSwitchContext()
    = 다음 배우 선택

PendSV handler
    = 실제 무대 전환
```

## task 선택 과정 자세히 보기

`vTaskSwitchContext()`는 ready list를 봅니다.

예를 들어:

```text
Priority 4 Ready List
empty

Priority 3 Ready List
+----------------------+
| Task B state item    |
| pvOwner -> TCB B     |
+----------------------+

Priority 2 Ready List
+----------------------+
| Task A state item    |
| pvOwner -> TCB A     |
+----------------------+
```

선택 과정:

```text
Priority 4 확인
    |
    v
비어 있음
    |
    v
Priority 3 확인
    |
    v
Task B 있음
    |
    v
Task B state item 선택
    |
    v
pvOwner로 TCB B 찾기
    |
    v
pxCurrentTCB = TCB B
```

그림:

```text
+----------------------------+
| Priority 3 Ready List      |
|----------------------------|
| +------------------------+ |
| | Task B xStateListItem  | |
| | pvOwner ---------------+-+----+
| +------------------------+ |    |
+----------------------------+    |
                                  v
                            +-----------+
                            | TCB B     |
                            +-----------+
                                  ^
                                  |
                            pxCurrentTCB
```

## 같은 priority task가 여러 개 있으면?

같은 priority task가 여러 개 있으면 ready list 안에서 다음 순서 task를 고릅니다.

```text
Priority 2 Ready List

+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+
```

Time slicing이 켜져 있으면 tick마다 이런 식으로 돌아갈 수 있습니다.

```text
첫 번째 선택: Task A
두 번째 선택: Task B
세 번째 선택: Task C
네 번째 선택: Task A
```

그림:

```text
Round 1

pxIndex
  |
  v
+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+

Round 2

                pxIndex
                  |
                  v
+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+

Round 3

                              pxIndex
                                |
                                v
+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+
```

이때도 `vTaskSwitchContext()`가 하는 일은 같습니다.

```text
ready list에서 다음 item 선택
    |
    v
pvOwner로 TCB 찾기
    |
    v
pxCurrentTCB 갱신
```

## 중요한 오해 정리

오해 1:

```text
vTaskSwitchContext()가 context switch를 직접 한다.
```

정확히는:

```text
vTaskSwitchContext()는 다음 task를 고른다.
실제 CPU context switch는 port layer가 한다.
```

오해 2:

```text
pxCurrentTCB를 바꾸면 즉시 Task B가 실행된다.
```

정확히는:

```text
pxCurrentTCB를 바꾸면
port layer가 복원할 대상이 바뀐다.

그 후 register 복원이 일어나야
실제로 Task B가 실행된다.
```

오해 3:

```text
scheduler가 CPU register를 직접 다룬다.
```

정확히는:

```text
scheduler는 TCB를 고른다.
CPU register는 port-specific 코드가 다룬다.
```

## 가장 중요한 그림

```text
                     context switch needed
                              |
                              v
+------------------------------------------------+
|                PendSV handler                  |
|------------------------------------------------|
| 1. 현재 task의 CPU register 저장                |
| 2. 현재 task의 pxTopOfStack 저장                |
|                                                |
| 3. vTaskSwitchContext() 호출                   |
|       - highest ready priority 찾기             |
|       - ready list에서 다음 task 고르기          |
|       - pxCurrentTCB 갱신                       |
|                                                |
| 4. 새 pxCurrentTCB->pxTopOfStack 읽기            |
| 5. 새 task의 CPU register 복원                  |
+------------------------------------------------+
                              |
                              v
                       new task running
```

## 더 짧게 보는 핵심 구조

```text
Before

pxCurrentTCB
     |
     v
+---------+
| TCB A   |
+---------+

vTaskSwitchContext()
     |
     v
ready lists에서 Task B 선택

After

pxCurrentTCB
     |
     v
+---------+
| TCB B   |
+---------+
```

그리고 port layer가 이어서 합니다.

```text
pxCurrentTCB
     |
     v
TCB B
     |
     v
pxTopOfStack
     |
     v
Task B stack
     |
     v
CPU register restore
     |
     v
Task B 실행
```

## 최종 요약

```text
vTaskSwitchContext()
    = FreeRTOS 공통 scheduler 함수

하는 일
    = 가장 높은 priority ready list를 찾음
    = 그 list에서 다음 task를 고름
    = pxCurrentTCB를 새 task의 TCB로 바꿈

하지 않는 일
    = CPU register 저장/복원
    = stack pointer 직접 변경
    = 실제 CPU context restore

pxCurrentTCB
    = 현재 실행할 task의 TCB를 가리키는 핵심 포인터

port layer
    = pxCurrentTCB->pxTopOfStack을 사용해서
      실제 CPU 상태를 저장/복원함
```

한 문장으로 정리하면:

```text
vTaskSwitchContext()는
"다음에 실행할 task가 누구인지"를 고르고
pxCurrentTCB를 그 task의 TCB로 바꾸는 함수다.

실제로 CPU register를 바꿔서 task를 전환하는 일은
Cortex-M port의 PendSV handler 같은 코드가 담당한다.
```
