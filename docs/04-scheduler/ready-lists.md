# Ready lists

FreeRTOS scheduler의 핵심 질문은 하나입니다.

```text
지금 당장 실행 가능한 task들 중에서
가장 priority가 높은 task는 누구인가?
```

FreeRTOS는 이 질문에 빠르게 답하기 위해 priority별 ready list를 둡니다.

## Ready list란?

Ready 상태는 이런 뜻입니다.

```text
이 task는 지금 실행될 수 있다.
CPU만 배정받으면 바로 실행 가능하다.
```

예를 들어 이런 task들이 있다고 해봅시다.

```text
Task A: 센서 읽기
Task B: 모터 제어
Task C: 로그 출력
Task D: idle task
```

이 중에서 지금 실행 가능한 task들은 ready list에 들어갑니다.

```text
Ready List

+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+
```

하지만 FreeRTOS는 ready task를 하나의 list에 전부 넣지 않습니다.

```text
priority마다 ready list를 따로 둔다
```

가 핵심입니다.

## priority마다 list가 하나씩 있다

FreeRTOS 내부에는 개념적으로 이런 배열이 있습니다.

```c
pxReadyTasksLists[ configMAX_PRIORITIES ];
```

쉽게 말하면:

```text
pxReadyTasksLists[0]  -> priority 0 ready task들
pxReadyTasksLists[1]  -> priority 1 ready task들
pxReadyTasksLists[2]  -> priority 2 ready task들
pxReadyTasksLists[3]  -> priority 3 ready task들
...
```

그림으로 보면:

```text
+-----------------------+
| pxReadyTasksLists     |
+-----------------------+

index 0
+-----------------------+
| Priority 0 Ready List |
+-----------------------+
| Idle Task             |
+-----------------------+

index 1
+-----------------------+
| Priority 1 Ready List |
+-----------------------+
| Task D                |
+-----------------------+

index 2
+-----------------------+
| Priority 2 Ready List |
+-----------------------+
| Task B -> Task C      |
+-----------------------+

index 3
+-----------------------+
| Priority 3 Ready List |
+-----------------------+
| Task A                |
+-----------------------+
```

즉 priority가 같은 task끼리 같은 ready list에 들어갑니다.

## scheduler는 높은 priority list부터 본다

FreeRTOS scheduler가 알고 싶은 것은 이것입니다.

```text
실행 가능한 task 중 가장 priority가 높은 task
```

그래서 scheduler는 ready list들을 priority 높은 쪽부터 확인합니다.

예를 들어:

```text
Priority 3 Ready List
+---------+
| Task A  |
+---------+

Priority 2 Ready List
+---------+     +---------+
| Task B  | --> | Task C  |
+---------+     +---------+

Priority 1 Ready List
+---------+
| Task D  |
+---------+

Priority 0 Ready List
+---------+
| Idle    |
+---------+
```

이 경우 scheduler는 `Priority 3 Ready List`가 비어 있지 않으므로 `Task A`를
고릅니다.

```text
Scheduler
    |
    v
Priority 3 list가 비어 있나?
    |
    v
아니오, Task A가 있음
    |
    v
Task A 실행
```

낮은 priority task들은 ready 상태여도 높은 priority task가 있으면 실행되지 못할
수 있습니다.

```text
Task B, Task C, Task D도 ready 상태지만
Task A가 더 높은 priority라서 Task A가 먼저 실행됨
```

## ready list에는 TCB_t가 직접 들어가지 않는다

앞에서 배운 내용과 연결됩니다.

FreeRTOS list에는 task 전체인 `TCB_t`가 직접 들어가지 않습니다. 대신 task 안에
들어 있는 `xStateListItem`이 들어갑니다.

```text
TCB_t
+--------------------------------+
| Task A                         |
|--------------------------------|
| priority = 3                   |
| xStateListItem                 |
| xEventListItem                 |
+--------------------------------+
```

Ready list에 들어가는 것은 이것입니다.

```text
xStateListItem
```

그리고 그 안의 `pvOwner`가 다시 원래 task인 `TCB_t`를 가리킵니다.

```text
Ready List Item
    |
    v
pvOwner
    |
    v
TCB_t
```

그림으로 보면:

```text
Priority 3 Ready List

+-----------------------+
| Task A xStateListItem |
| pvOwner --------------+----+
+-----------------------+    |
                             v
                        +---------+
                        | TCB A   |
                        | prio 3  |
                        +---------+
```

즉 scheduler는 ready list에서 list item을 꺼낸 뒤, `pvOwner`를 따라가 실제 task
정보를 얻습니다.

## 전체 구조 그림

```text
pxReadyTasksLists

+------------------------------------------------+
| [0] Priority 0 Ready List                      |
|                                                |
|   +----------------------+                     |
|   | Idle xStateListItem  | ----> TCB Idle      |
|   +----------------------+                     |
+------------------------------------------------+

+------------------------------------------------+
| [1] Priority 1 Ready List                      |
|                                                |
|   +----------------------+                     |
|   | Task D state item    | ----> TCB D         |
|   +----------------------+                     |
+------------------------------------------------+

+------------------------------------------------+
| [2] Priority 2 Ready List                      |
|                                                |
|   +----------------------+     +-------------+ |
|   | Task B state item    | --> | Task C item | |
|   | pvOwner -> TCB B     |     | -> TCB C    | |
|   +----------------------+     +-------------+ |
+------------------------------------------------+

+------------------------------------------------+
| [3] Priority 3 Ready List                      |
|                                                |
|   +----------------------+                     |
|   | Task A state item    | ----> TCB A         |
|   +----------------------+                     |
+------------------------------------------------+
```

Scheduler는 높은 index 쪽 priority부터 봅니다.

```text
Priority 3 확인
    |
    v
비어 있지 않으면 여기서 선택

비어 있으면
    |
    v
Priority 2 확인

비어 있으면
    |
    v
Priority 1 확인

...
```

## 같은 priority task가 여러 개 있으면?

이번에는 priority 2 task가 여러 개 있다고 해봅시다.

```text
Priority 2 Ready List

+---------+     +---------+     +---------+
| Task A  | --> | Task B  | --> | Task C  |
+---------+     +---------+     +---------+
```

이 세 task는 priority가 같습니다.

그러면 FreeRTOS는 설정에 따라 이 task들을 번갈아 실행할 수 있습니다. 이것을
보통 time slicing 또는 같은 priority 안의 round-robin처럼 이해하면 됩니다.

```text
첫 번째 선택: Task A
두 번째 선택: Task B
세 번째 선택: Task C
네 번째 선택: Task A
```

그림으로 보면:

```text
Priority 2 Ready List

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

여기서 `pxIndex`는 `List_t` 안에 있는 순회용 pointer입니다.

```text
pxIndex
    = 같은 priority list 안에서
      다음에 누구를 고를지 기억하는 위치
```

## priority가 다르면 round-robin이 아니다

중요한 점입니다.

Round-robin은 같은 priority 안에서만 생각해야 합니다.

예를 들어:

```text
Task A priority 3
Task B priority 2
Task C priority 2
```

이 경우 Task A가 ready 상태라면 Task B, Task C는 보통 실행되지 않습니다.

```text
Priority 3
+---------+
| Task A  |
+---------+

Priority 2
+---------+     +---------+
| Task B  | --> | Task C  |
+---------+     +---------+
```

Scheduler는 먼저 priority 3 list를 봅니다.

```text
Priority 3에 Task A가 있음
    |
    v
Task A 선택
```

그러므로 priority 2의 Task B, Task C는 같은 priority끼리 번갈아 실행될 기회가
있더라도, priority 3 task가 계속 ready이면 밀릴 수 있습니다.

```text
높은 priority ready task가 있으면
낮은 priority ready task는 기다린다.
```

## ready list가 비어 있으면?

예를 들어 priority 3 list가 비어 있다고 합시다.

```text
Priority 3 Ready List
empty

Priority 2 Ready List
+---------+     +---------+
| Task B  | --> | Task C  |
+---------+     +---------+

Priority 1 Ready List
+---------+
| Task D  |
+---------+
```

그러면 scheduler는 priority 2 list에서 고릅니다.

```text
Priority 3 확인
    |
    v
비어 있음
    |
    v
Priority 2 확인
    |
    v
Task B, Task C 있음
    |
    v
둘 중 다음 순서 task 선택
```

## idle task는 왜 priority 0에 있을까?

FreeRTOS에는 보통 idle task가 있습니다.

Idle task는 실행할 다른 task가 없을 때 실행됩니다.

```text
Priority 0 Ready List

+-----------+
| Idle Task |
+-----------+
```

Idle task는 가장 낮은 priority입니다.

즉:

```text
다른 ready task가 하나라도 있으면
idle task보다 그 task가 먼저 실행된다.
```

그림:

```text
Priority 2
+---------+
| Task A  |
+---------+

Priority 0
+---------+
| Idle    |
+---------+
```

이 경우 Task A가 실행됩니다.

모든 일반 task가 delayed, suspended, blocked 상태라면?

```text
Priority 3
empty

Priority 2
empty

Priority 1
empty

Priority 0
+---------+
| Idle    |
+---------+
```

그때 idle task가 실행됩니다.

```text
실행할 게 아무것도 없을 때
CPU가 놀지 않도록 idle task 실행
```

## ready list는 전체 task 목록이 아니다

중요한 오해가 있습니다.

```text
ready list에 없으면 task가 사라진 건가?
```

아닙니다.

Ready list에 없다는 뜻은 단지:

```text
지금 당장 실행할 수 없다는 뜻
```

일 수 있습니다.

그 task는 다른 list에 있을 수 있습니다.

```text
Delayed List
    -> vTaskDelay()로 잠자는 task

Suspended List
    -> suspend 된 task

Queue Wait List
    -> queue 데이터를 기다리는 task

Semaphore Wait List
    -> semaphore를 기다리는 task
```

그림으로 보면:

```text
전체 task들

+------------------+
| Ready Lists      |
| 지금 실행 가능   |
+------------------+

+------------------+
| Delayed Lists    |
| 시간 기다림      |
+------------------+

+------------------+
| Suspended List   |
| 중단됨           |
+------------------+

+------------------+
| Event Wait Lists |
| queue/semaphore  |
| 기다림           |
+------------------+
```

즉 ready list는 모든 task의 목록이 아닙니다.

```text
Ready lists
    = 지금 실행 가능한 task들의 집합
```

## task 상태 이동과 ready list

Task는 상황에 따라 ready list에 들어오고 나갑니다.

Delay를 호출하면:

```text
Ready List
    |
    | vTaskDelay()
    v
Delayed List
```

그림:

```text
Before

Ready List
+---------+
| Task A  |
+---------+

After vTaskDelay()

Delayed List
+------------------+
| Task A           |
| wake tick = 200  |
+------------------+
```

시간이 지나면:

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

tick = 200

After

Ready List
+---------+
| Task A  |
+---------+
```

Queue를 기다리면:

```text
Ready List
    |
    | queue empty
    v
Queue Wait List
```

그리고 timeout이 있으면 delayed list에도 걸릴 수 있습니다.

```text
Task A waits for queue with timeout

xStateListItem
    -> delayed list

xEventListItem
    -> queue wait list
```

Queue에 데이터가 오면:

```text
Queue Wait List
    |
    | data arrives
    v
Ready List
```

즉 scheduler가 보는 핵심 후보는 항상 ready list에 있습니다.

## scheduler의 선택 과정을 그림으로 보기

```text
Scheduler starts choosing

        |
        v
+-----------------------------+
| 가장 높은 priority부터 확인 |
+-------------+---------------+
              |
              v
+-----------------------------+
| 해당 ready list가 비었나?   |
+-------------+---------------+
              |
       +------+------+
       |             |
      No             Yes
       |             |
       v             v
+-------------+   +-------------------------+
| 그 list에서 |   | 다음 낮은 priority list |
| task 선택   |   | 확인                    |
+-------------+   +-------------------------+
       |
       v
+-----------------------------+
| ListItem_t의 pvOwner 확인   |
+-------------+---------------+
              |
              v
+-----------------------------+
| TCB_t 찾음                  |
+-------------+---------------+
              |
              v
+-----------------------------+
| pxCurrentTCB로 설정         |
+-------------+---------------+
              |
              v
+-----------------------------+
| context switch 후 실행      |
+-----------------------------+
```

## ready list에서 TCB로 돌아가는 과정

Ready list 안에는 `xStateListItem`이 있습니다.

```text
Priority 2 Ready List

+----------------------+
| Task B xStateListItem|
| pvOwner -------------+----+
+----------------------+    |
                            v
                       +---------+
                       | TCB B   |
                       | prio 2  |
                       +---------+
```

Scheduler는 이렇게 이동합니다.

```text
ready list에서 item 선택
    |
    v
item->pvOwner
    |
    v
TCB_t
    |
    v
이 task를 실행 후보로 선택
```

즉:

```text
ready list item
    -> pvOwner
        -> TCB_t
```

이 구조가 FreeRTOS 전체에서 계속 반복됩니다.

## 가장 단순한 예시

현재 task 상태가 이렇다고 합시다.

```text
Task A: priority 3, ready
Task B: priority 2, ready
Task C: priority 2, delayed
Task D: priority 1, ready
Task E: priority 0, idle
```

Ready lists는 이렇게 됩니다.

```text
Priority 3 Ready List
+---------+
| Task A  |
+---------+

Priority 2 Ready List
+---------+
| Task B  |
+---------+

Priority 1 Ready List
+---------+
| Task D  |
+---------+

Priority 0 Ready List
+---------+
| Idle    |
+---------+
```

Task C는 delayed 상태이므로 ready list에 없습니다.

```text
Delayed List
+------------------+
| Task C           |
| wake tick = 500  |
+------------------+
```

Scheduler는 Task A를 고릅니다.

```text
가장 높은 priority ready task = Task A
```

## Task A가 delay에 들어가면?

Task A가 `vTaskDelay()`를 호출합니다.

```text
Task A
    |
    | vTaskDelay()
    v
Delayed List로 이동
```

이제 ready lists는 이렇게 됩니다.

```text
Priority 3 Ready List
empty

Priority 2 Ready List
+---------+
| Task B  |
+---------+

Priority 1 Ready List
+---------+
| Task D  |
+---------+

Priority 0 Ready List
+---------+
| Idle    |
+---------+
```

이제 scheduler는 Task B를 고릅니다.

```text
Priority 3은 비어 있음
Priority 2에 Task B가 있음
    |
    v
Task B 실행
```

## Task C가 깨어나면?

Task C는 priority 2였고 delayed 상태였습니다.

```text
Delayed List
+------------------+
| Task C           |
| wake tick = 500  |
+------------------+
```

Tick이 500이 되면 Task C가 ready list로 돌아옵니다.

```text
Priority 2 Ready List

+---------+     +---------+
| Task B  | --> | Task C  |
+---------+     +---------+
```

이제 priority 2 안에서는 Task B와 Task C가 같은 priority입니다.

Time slicing이 켜져 있다면 둘이 번갈아 실행될 수 있습니다.

```text
Task B -> Task C -> Task B -> Task C ...
```

## 전체 그림: ready lists 중심 세계관

```text
                         +------------------+
                         |    Scheduler     |
                         +--------+---------+
                                  |
                                  v
                    +--------------------------+
                    | Highest non-empty        |
                    | ready list 찾기          |
                    +------------+-------------+
                                 |
                                 v

+--------------------------------------------------------+
| pxReadyTasksLists                                      |
|--------------------------------------------------------|
| [3] Priority 3 Ready List                              |
|     +----------------------+                           |
|     | Task A state item    | ---> TCB A                |
|     +----------------------+                           |
|                                                        |
| [2] Priority 2 Ready List                              |
|     +----------------------+     +-------------------+ |
|     | Task B state item    | --> | Task C state item | |
|     | pvOwner -> TCB B     |     | pvOwner -> TCB C  | |
|     +----------------------+     +-------------------+ |
|                                                        |
| [1] Priority 1 Ready List                              |
|     +----------------------+                           |
|     | Task D state item    | ---> TCB D                |
|     +----------------------+                           |
|                                                        |
| [0] Priority 0 Ready List                              |
|     +----------------------+                           |
|     | Idle state item      | ---> TCB Idle             |
|     +----------------------+                           |
+--------------------------------------------------------+
```

## 왜 이렇게 설계했을까?

Scheduler가 매번 모든 task를 보면 느립니다.

```text
모든 task 검사 방식

Task A ready?
Task B ready?
Task C ready?
Task D ready?
Task E ready?
...
```

FreeRTOS는 미리 정리해둡니다.

```text
priority별 ready list 방식

Priority 3 list 비었나?
Priority 2 list 비었나?
Priority 1 list 비었나?
...
```

그래서 scheduler가 필요한 질문에 빠르게 답할 수 있습니다.

```text
지금 실행 가능한 가장 높은 priority task는?
```

## 핵심 요약

```text
pxReadyTasksLists
    = priority별 ready list 배열

pxReadyTasksLists[0]
    = priority 0 task들의 ready list

pxReadyTasksLists[1]
    = priority 1 task들의 ready list

pxReadyTasksLists[N]
    = priority N task들의 ready list

ready list에 들어가는 것
    = TCB_t 자체가 아니라 TCB_t.xStateListItem

xStateListItem.pvOwner
    = 원래 TCB_t를 가리킴

scheduler
    = 가장 높은 priority의 비어 있지 않은 ready list를 찾고,
      그 안에서 다음 task를 고름

time slicing
    = 같은 priority task들이 ready list 안에서 번갈아 실행되는 방식

ready list에 없다는 것
    = task가 사라졌다는 뜻이 아님
    = delayed, suspended, event wait 상태일 수 있음
```

## 가장 중요한 그림

```text
                 +----------------------+
                 | pxReadyTasksLists    |
                 +----------------------+
                    |      |      |
                    |      |      |
                    v      v      v

        +-----------+  +-----------+  +-----------+
        | Priority0 |  | Priority1 |  | Priority2 |
        | ReadyList |  | ReadyList |  | ReadyList |
        +-----------+  +-----------+  +-----------+
              |              |              |
              v              v              v

        ListItem_t     ListItem_t     ListItem_t
              |              |              |
              v              v              v

          pvOwner        pvOwner        pvOwner
              |              |              |
              v              v              v

            TCB_t          TCB_t          TCB_t
```

한 문장으로 정리하면:

```text
FreeRTOS의 ready list는
"지금 실행 가능한 task들을 priority별로 정리해둔 배열"이고,
scheduler는 여기서 가장 높은 priority의 task를 빠르게 고른다.
```
