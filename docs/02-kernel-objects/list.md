# Doubly linked lists

FreeRTOS list를 볼 때 가장 먼저 잡아야 할 핵심은 이것입니다.

```text
FreeRTOS는 task들을 직접 줄 세우지 않고,
task 안에 들어 있는 작은 ListItem_t를 줄 세운다.
```

이 장에서는 `FreeRTOS-Kernel/include/list.h`와 `FreeRTOS-Kernel/list.c`를
그림 중심으로 읽습니다.

## TCB_t 안에 task 정보가 있다

FreeRTOS에서 task 하나는 대략 `TCB_t`라는 큰 구조체로 표현됩니다.

```text
+--------------------------------+
|            TCB_t               |
|                                |
|  task name                     |
|  stack information             |
|  priority                      |
|                                |
|  +--------------------------+  |
|  |      xStateListItem      |  |
|  +--------------------------+  |
|                                |
|  +--------------------------+  |
|  |      xEventListItem      |  |
|  +--------------------------+  |
|                                |
+--------------------------------+
```

여기서 중요한 필드는 `xStateListItem`과 `xEventListItem`입니다. 이 둘은 task
자체가 아니라, task를 어떤 list에 걸어두기 위한 작은 node입니다.

```text
xStateListItem
    -> ready / delayed / suspended list에 연결될 때 사용

xEventListItem
    -> queue / semaphore / event wait list에 연결될 때 사용
```

## ListItem_t는 task 이름표다

`ListItem_t` 하나는 이렇게 볼 수 있습니다.

```text
+-----------------------------+
|         ListItem_t          |
|                             |
|  xItemValue                 |
|  pxNext       --------+     |
|  pxPrevious   <-------+     |
|                             |
|  pvOwner --------------+    |
|                         |    |
|  pxContainer           |    |
+-------------------------|---+
                          |
                          v
                    +-----------+
                    |   TCB_t   |
                    | real task |
                    +-----------+
```

`ListItem_t`는 list에 들어가는 작은 node입니다. 그런데 이 node에는 `pvOwner`가
있습니다.

```text
pvOwner = this ListItem_t's owner task
```

즉, scheduler가 list에서 `ListItem_t`를 발견하면 다음 흐름으로 실제 task를
찾습니다.

```text
found ListItem_t
      |
      v
follow pvOwner
      |
      v
found TCB_t
      |
      v
this is the task to run
```

코드로는 이 매크로가 그 관계를 보여줍니다.

```c
#define listGET_LIST_ITEM_OWNER( pxListItem ) \
    ( ( pxListItem )->pvOwner )
```

쉽게 말하면:

```text
이 list item의 주인 task를 가져와라
```

입니다.

## Ready list에는 TCB_t가 아니라 ListItem_t가 들어간다

초보자가 가장 헷갈리는 부분이 여기입니다. 겉으로는 ready list가 task를 직접
담는 것처럼 생각하기 쉽습니다.

```text
ready list
   |
   +----> Task A
   |
   +----> Task B
   |
   +----> Task C
```

하지만 실제 느낌은 이것에 더 가깝습니다.

```text
ready list
   |
   v
+---------------+      +---------------+      +---------------+
| ListItem_t    | ---> | ListItem_t    | ---> | ListItem_t    |
| of Task A     |      | of Task B     |      | of Task C     |
+-------|-------+      +-------|-------+      +-------|-------+
        |                      |                      |
        v                      v                      v
    +-------+              +-------+              +-------+
    | TCB A |              | TCB B |              | TCB C |
    +-------+              +-------+              +-------+
```

정리하면:

```text
list에는 ListItem_t가 들어간다.
ListItem_t의 pvOwner를 통해 TCB_t를 찾는다.
```

이 구조가 FreeRTOS scheduler를 읽는 첫 번째 열쇠입니다.

## 왜 이렇게 복잡하게 할까?

왜 그냥 task를 list에 넣지 않을까요? 이유는 하나의 task가 여러 종류의 list에
걸릴 수 있어야 하기 때문입니다.

예를 들어 어떤 task가 queue를 기다리고 있다고 합시다. 그 task는 동시에 이런
의미를 가질 수 있습니다.

```text
state view:
    this task is blocked

event view:
    this task is waiting for a queue
```

그래서 task 안에는 list item이 여러 개 있습니다.

```text
+--------------------------------+
|             TCB_t              |
|                                |
|  Task A                        |
|                                |
|  +--------------------------+  |
|  |   xStateListItem         |  | ----> ready / delayed / suspended list
|  +--------------------------+  |
|                                |
|  +--------------------------+  |
|  |   xEventListItem         |  | ----> queue / semaphore wait list
|  +--------------------------+  |
|                                |
+--------------------------------+
```

`xStateListItem`은 task의 실행 상태를 관리할 때 사용됩니다. `xEventListItem`은
queue, semaphore 같은 event 대기를 관리할 때 사용됩니다.

## Ready list 구조

FreeRTOS는 priority별로 ready list를 따로 둡니다. 예를 들어 priority 3인
task들이 있다고 해봅시다.

```text
Priority 3 Ready List

+-----------+
|  List_t   |
|-----------|
| uxNumber  | = 3
| pxIndex   | ----+
| xListEnd  |     |
+-----------+     |
                  |
                  v
        +----------------+
        | ListItem_t A   |
        | pvOwner ----+  |
        +-------------|--+
                      |
                      v
                  +-------+
                  | TCB A |
                  +-------+

        +----------------+
        | ListItem_t B   |
        | pvOwner ----+  |
        +-------------|--+
                      |
                      v
                  +-------+
                  | TCB B |
                  +-------+

        +----------------+
        | ListItem_t C   |
        | pvOwner ----+  |
        +-------------|--+
                      |
                      v
                  +-------+
                  | TCB C |
                  +-------+
```

실제로 연결 관계까지 그리면 이런 느낌입니다.

```text
Priority 3 Ready List

        pxIndex
          |
          v
+----------------+     +----------------+     +----------------+
| ListItem_t A   | --> | ListItem_t B   | --> | ListItem_t C   |
| pvOwner -> TCB |     | pvOwner -> TCB |     | pvOwner -> TCB |
+----------------+     +----------------+     +----------------+
       ^                       ^                       ^
       |                       |                       |
       v                       v                       v
    +-------+               +-------+               +-------+
    | TCB A |               | TCB B |               | TCB C |
    +-------+               +-------+               +-------+
```

## pxNext와 pxPrevious는 양방향 연결이다

`ListItem_t`는 doubly linked list의 node입니다. 그래서 앞뒤로 움직일 수 있습니다.

```text
+-------------+       +-------------+       +-------------+
| item A      | <---> | item B      | <---> | item C      |
| pxNext      |       | pxNext      |       | pxNext      |
| pxPrevious  |       | pxPrevious  |       | pxPrevious  |
+-------------+       +-------------+       +-------------+
```

단방향 linked list였다면 다음 item만 알 수 있습니다.

```text
A -> B -> C
```

Doubly linked list는 앞뒤를 모두 압니다.

```text
A <-> B <-> C
```

그래서 중간 item을 제거할 때 편합니다.

```text
Before

A <-> B <-> C

After

A <------> C
```

B의 앞과 뒤를 알고 있으므로 빠르게 제거할 수 있습니다.

## xListEnd는 가짜 끝 노드다

FreeRTOS list에는 `xListEnd`라는 특별한 node가 있습니다. 이 node는 실제 task가
아닙니다.

```text
xListEnd = list의 끝을 표시하는 가짜 node
```

보통 linked list는 이런 예외 처리가 필요합니다.

```text
list가 비어 있나?
첫 번째 node인가?
마지막 node인가?
```

FreeRTOS는 `xListEnd`라는 sentinel node를 둬서 이런 처리를 단순하게 만듭니다.
더 정확히는 원형 list처럼 동작합니다.

```text
              +----------------------+
              |                      |
              v                      |
+----------+      +--------+      +--------+
| xListEnd | <--> | item A | <--> | item B |
+----------+      +--------+      +--------+
      ^                              |
      |                              |
      +------------------------------+
```

`xListEnd` 덕분에 list의 시작과 끝을 다루는 코드가 단순해집니다.

## pxIndex는 이번에 어디까지 봤는지 기억한다

`pxIndex`는 list를 순회할 때 현재 위치를 기억합니다. 이게 왜 중요하냐면, 같은
priority의 task가 여러 개 있을 때 공평하게 실행해야 하기 때문입니다.

```text
Priority 3 Ready List

+--------+     +--------+     +--------+
| Task A | --> | Task B | --> | Task C |
+--------+     +--------+     +--------+
```

계속 Task A만 실행하면 안 됩니다. FreeRTOS는 같은 priority의 ready task들을 이런
식으로 돌립니다.

```text
first selection:  Task A
second selection: Task B
third selection:  Task C
fourth selection: Task A
```

이것을 round-robin이라고 생각하면 됩니다. `pxIndex`는 현재 순서를 기억합니다.

```text
Round 1

pxIndex
  |
  v
+--------+     +--------+     +--------+
| Task A | --> | Task B | --> | Task C |
+--------+     +--------+     +--------+

Round 2

              pxIndex
                |
                v
+--------+     +--------+     +--------+
| Task A | --> | Task B | --> | Task C |
+--------+     +--------+     +--------+

Round 3

                             pxIndex
                               |
                               v
+--------+     +--------+     +--------+
| Task A | --> | Task B | --> | Task C |
+--------+     +--------+     +--------+
```

즉:

```text
pxIndex = 같은 priority task들 사이에서 순서를 기억하는 pointer
```

입니다.

## xItemValue는 list마다 의미가 달라진다

`xItemValue`는 list 안에서 정렬 기준으로 쓰입니다. 하지만 항상 같은 의미는
아닙니다.

Delayed list에서는 보통 "몇 tick에 깨어날 것인가"를 의미합니다.

```text
Delayed List

+------------------+      +------------------+
| Task A item      | ---> | Task B item      |
| wake tick = 50   |      | wake tick = 80   |
+------------------+      +------------------+
        |                         |
        v                         v
     +-------+                 +-------+
     | TCB A |                 | TCB B |
     +-------+                 +-------+
```

Event list에서는 priority 기반 정렬 값으로 쓰일 수 있습니다.

```text
Event Wait List

+----------------------+
| Task A event item    |
| priority-related val |
+----------------------+

+----------------------+
| Task B event item    |
| priority-related val |
+----------------------+
```

정리하면:

```text
Delayed list에서 xItemValue
    -> wake-up tick

Event list에서 xItemValue
    -> priority-related ordering value
```

같은 필드지만, 사용하는 list에 따라 의미가 달라집니다.

## 전체 구조를 한 그림으로 보면

```text
                 +----------------------+
                 |      Ready List      |
                 |       List_t         |
                 |----------------------|
                 | uxNumberOfItems = 3  |
                 | pxIndex              |
                 | xListEnd             |
                 +----------+-----------+
                            |
                            v

        +-------------------+-------------------+
        |                   |                   |
        v                   v                   v

+---------------+   +---------------+   +---------------+
| ListItem_t    |   | ListItem_t    |   | ListItem_t    |
| Task A state  |   | Task B state  |   | Task C state  |
|---------------|   |---------------|   |---------------|
| xItemValue    |   | xItemValue    |   | xItemValue    |
| pxNext        |-->| pxNext        |-->| pxNext        |
| pxPrevious    |<--| pxPrevious    |<--| pxPrevious    |
| pvOwner       |   | pvOwner       |   | pvOwner       |
+------|--------+   +------|--------+   +------|--------+
       |                   |                   |
       v                   v                   v
+-------------+     +-------------+     +-------------+
|   TCB A     |     |   TCB B     |     |   TCB C     |
|-------------|     |-------------|     |-------------|
| priority 3  |     | priority 3  |     | priority 3  |
| stack       |     | stack       |     | stack       |
| state item  |     | state item  |     | state item  |
| event item  |     | event item  |     | event item  |
+-------------+     +-------------+     +-------------+
```

## Scheduler가 task를 고르는 과정

Scheduler 입장에서 보면 흐름은 이렇습니다.

```text
+----------------------------+
| scheduler                  |
+-------------+--------------+
              |
              v
+----------------------------+
| find the highest-priority  |
| ready list                 |
+-------------+--------------+
              |
              v
+----------------------------+
| use pxIndex to choose the  |
| next ListItem_t            |
+-------------+--------------+
              |
              v
+----------------------------+
| read ListItem_t->pvOwner   |
+-------------+--------------+
              |
              v
+----------------------------+
| pvOwner points to the      |
| TCB_t to run               |
+----------------------------+
```

다시 코드로 보면 이 부분이 핵심입니다.

```c
#define listGET_LIST_ITEM_OWNER( pxListItem ) \
    ( ( pxListItem )->pvOwner )
```

## 핵심 정리

```text
TCB_t
    = task 전체 정보

ListItem_t
    = task를 list에 넣기 위한 작은 node

pvOwner
    = ListItem_t에서 원래 TCB_t로 돌아가는 pointer

List_t
    = ListItem_t들을 담는 list

xListEnd
    = list 끝을 표시하는 fake/sentinel node

pxIndex
    = list를 어디까지 순회했는지 기억하는 pointer

xItemValue
    = 정렬 기준
    = delayed list에서는 wake-up tick
    = event list에서는 priority-related value
```

가장 중요한 그림은 이것입니다.

```text
List_t
  |
  v
ListItem_t
  |
  v
pvOwner
  |
  v
TCB_t
```

즉, FreeRTOS의 list를 읽을 때는 이렇게 생각하면 됩니다.

```text
FreeRTOS는 task를 직접 list에 넣지 않는다.

task 안에 들어 있는 ListItem_t를 list에 넣고,
나중에 pvOwner를 통해 다시 task로 돌아간다.
```

이제 이 구조를 알고 `TCB_t`를 보면, task 안에 왜 `xStateListItem`과
`xEventListItem`이 따로 있는지 훨씬 자연스럽게 보입니다.
