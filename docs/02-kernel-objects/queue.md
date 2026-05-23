# Queue object

FreeRTOS queue를 볼 때 가장 먼저 잡아야 할 핵심은 이것입니다.

```text
FreeRTOS의 Queue는 단순히 데이터를 담는 줄이 아니다.

Queue는
1. 데이터를 담는 공간이고
2. send하다가 막힌 task들의 대기실이고
3. receive하다가 막힌 task들의 대기실이다.
```

이 장에서는 `FreeRTOS-Kernel/queue.c`의 `Queue_t`를 그림 중심으로 읽습니다.

## 우리가 보통 생각하는 queue

컴퓨터공학에서 queue라고 하면 보통 이런 것을 떠올립니다.

```text
FIFO Queue

+-----+-----+-----+-----+
|  A  |  B  |  C  |     |
+-----+-----+-----+-----+
  ^
  |
먼저 들어온 A가 먼저 나감
```

즉:

```text
enqueue = 뒤에 넣기
dequeue = 앞에서 꺼내기
```

입니다. 하지만 FreeRTOS의 queue는 이것보다 더 큽니다.

## FreeRTOS Queue는 데이터 줄 + task 대기실이다

FreeRTOS의 `Queue_t`는 대략 이렇게 보면 됩니다.

```text
+------------------------------------------------+
|                    Queue_t                     |
|------------------------------------------------|
|                                                |
|  [ data storage area ]                         |
|                                                |
|  +------+  +------+  +------+  +------+        |
|  | item |  | item |  |      |  |      |        |
|  +------+  +------+  +------+  +------+        |
|                                                |
|------------------------------------------------|
|                                                |
|  xTasksWaitingToSend                           |
|  = tasks blocked because the queue was full    |
|    while they tried to send                    |
|                                                |
|------------------------------------------------|
|                                                |
|  xTasksWaitingToReceive                        |
|  = tasks blocked because the queue was empty   |
|    while they tried to receive                 |
|                                                |
+------------------------------------------------+
```

즉 queue는 단순한 buffer가 아닙니다.

```text
Queue_t
 ├─ data storage area
 ├─ task list waiting to send
 └─ task list waiting to receive
```

## Queue_t 구조체를 쉽게 보기

원래 코드는 이런 느낌입니다.

```c
typedef struct QueueDefinition
{
    int8_t * pcHead;
    int8_t * pcWriteTo;

    union
    {
        QueuePointers_t xQueue;
        SemaphoreData_t xSemaphore;
    } u;

    List_t xTasksWaitingToSend;
    List_t xTasksWaitingToReceive;

    volatile UBaseType_t uxMessagesWaiting;
    UBaseType_t uxLength;
    UBaseType_t uxItemSize;

    volatile int8_t cRxLock;
    volatile int8_t cTxLock;
} xQUEUE;
```

처음 보면 복잡하지만, 크게 네 덩어리로 보면 됩니다.

```text
+------------------------------------------------+
|                    Queue_t                     |
+------------------------------------------------+
|  1. buffer position information                |
|     pcHead                                     |
|     pcWriteTo                                  |
|     u.xQueue                                   |
+------------------------------------------------+
|  2. waiting task lists                         |
|     xTasksWaitingToSend                        |
|     xTasksWaitingToReceive                     |
+------------------------------------------------+
|  3. queue state information                    |
|     uxMessagesWaiting                          |
|     uxLength                                   |
|     uxItemSize                                 |
+------------------------------------------------+
|  4. lock-related information                   |
|     cRxLock                                    |
|     cTxLock                                    |
+------------------------------------------------+
```

처음 읽을 때는 1, 2, 3번을 먼저 붙잡으면 됩니다.

## 저장 공간 관련 필드

`pcHead`는 queue 저장 공간의 시작 주소입니다.

```text
pcHead
  |
  v
+------+------+------+------+------+
| item | item |      |      |      |
+------+------+------+------+------+
```

`pcWriteTo`는 다음 item을 어디에 쓸지 가리킵니다.

```text
pcHead
  |
  v
+------+------+------+------+------+
|  A   |  B   |      |      |      |
+------+------+------+------+------+
                ^
                |
            pcWriteTo
```

새로운 item `C`를 send하면 `pcWriteTo`는 다음 빈 위치로 이동합니다.

```text
Before

+------+------+------+------+------+
|  A   |  B   |      |      |      |
+------+------+------+------+------+
                ^
                |
            pcWriteTo

After

+------+------+------+------+------+
|  A   |  B   |  C   |      |      |
+------+------+------+------+------+
                       ^
                       |
                   pcWriteTo
```

`uxMessagesWaiting`은 현재 queue 안에 item이 몇 개 있는지 나타냅니다.

```text
+------+------+------+------+------+
|  A   |  B   |  C   |      |      |
+------+------+------+------+------+

uxMessagesWaiting = 3
```

`uxLength`는 queue의 최대 길이입니다.

```text
+------+------+------+------+------+
|      |      |      |      |      |
+------+------+------+------+------+

uxLength = 5
```

`uxItemSize`는 item 하나의 크기입니다.

```text
uxItemSize = sizeof(int)
uxItemSize = sizeof(MyStruct)
```

FreeRTOS queue는 item을 넣을 때 보통 값을 복사합니다.

```text
sender task variable
      |
      | copy
      v
queue internal buffer
```

## 중요한 건 wait list 두 개다

Queue에서 scheduler 관점으로 가장 중요한 필드는 이 두 개입니다.

```c
List_t xTasksWaitingToSend;
List_t xTasksWaitingToReceive;
```

그림으로 보면:

```text
+------------------------------------------------+
|                    Queue_t                     |
|------------------------------------------------|
|                                                |
|  storage buffer                                |
|  +------+------+------+                        |
|  |  A   |  B   |      |                        |
|  +------+------+------+                        |
|                                                |
|------------------------------------------------|
| xTasksWaitingToSend                            |
|                                                |
|  tasks blocked because the queue is full       |
|                                                |
|------------------------------------------------|
| xTasksWaitingToReceive                         |
|                                                |
|  tasks blocked because the queue is empty      |
|                                                |
+------------------------------------------------+
```

이 두 list 때문에 `Queue_t`는 단순 FIFO가 아니라 scheduler와 연결된 kernel
object가 됩니다.

## Receive를 했는데 queue가 비어 있으면?

어떤 task가 queue에서 데이터를 받으려고 합니다.

```c
xQueueReceive(queue, &data, waitTime);
```

그런데 queue가 비어 있습니다.

```text
Queue buffer

+------+------+------+
|      |      |      |
+------+------+------+

uxMessagesWaiting = 0
```

그러면 당장 받을 데이터가 없습니다.

이때 wait time이 0이 아니라면 현재 task는 기다릴 수 있습니다.

```text
Task A가 receive 시도
        |
        v
queue가 비어 있음
        |
        v
Task A를 xTasksWaitingToReceive list에 넣음
```

그림으로 보면:

```text
+------------------------------------------------+
|                    Queue_t                     |
|------------------------------------------------|
| buffer                                         |
|                                                |
| +------+------+------+                         |
| |      |      |      |                         |
| +------+------+------+                         |
|                                                |
| uxMessagesWaiting = 0                          |
|------------------------------------------------|
| xTasksWaitingToReceive                         |
|                                                |
| +----------------+                             |
| | ListItem_t A   | ----> TCB A                 |
| +----------------+                             |
|                                                |
|------------------------------------------------|
| xTasksWaitingToSend                            |
|                                                |
| empty                                          |
+------------------------------------------------+
```

즉 Task A는 이런 상태가 됩니다.

```text
Task A
  |
  v
"queue에 데이터가 들어올 때까지 기다리는 중"
```

## 그 상태에서 다른 task가 send하면?

이제 Task B가 queue에 데이터를 보냅니다.

```c
xQueueSend(queue, &data, waitTime);
```

Queue는 비어 있었기 때문에 데이터가 들어갑니다.

```text
Before

+------+------+------+
|      |      |      |
+------+------+------+

After

+------+------+------+
|  X   |      |      |
+------+------+------+
```

그런데 중요한 일이 하나 더 일어납니다.

이미 receive를 기다리는 Task A가 있었습니다.

```text
xTasksWaitingToReceive

+----------------+
| Task A item    |
+----------------+
```

이제 데이터가 생겼으므로 Task A를 깨울 수 있습니다.

```text
send 성공
   |
   v
receive 기다리던 task가 있나?
   |
   v
Task A를 wait list에서 제거
   |
   v
Task A를 ready list로 이동
```

그림으로 보면:

```text
Before send

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| |      |      |      |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToReceive      |
| +----------------+          |
| | Task A item    | -> TCB A |
| +----------------+          |
+-----------------------------+


Task B가 send


After send

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| |  X   |      |      |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToReceive      |
| empty                       |
+-----------------------------+

Task A는 ready list로 이동
```

즉 send는 단순히 데이터를 넣는 일이 아닙니다.

```text
send 성공
  = 데이터 넣기
  + receive 기다리던 task 깨우기
```

## Send를 했는데 queue가 가득 차 있으면?

이번에는 반대 상황입니다.

Queue가 이미 꽉 차 있습니다.

```text
Queue buffer

+------+------+------+
|  A   |  B   |  C   |
+------+------+------+

uxMessagesWaiting = 3
uxLength = 3
```

Task B가 send를 시도합니다.

```c
xQueueSend(queue, &data, waitTime);
```

하지만 자리가 없습니다.

그래서 wait time이 0이 아니라면 Task B는 기다립니다.

```text
Task B가 send 시도
        |
        v
queue가 꽉 차 있음
        |
        v
Task B를 xTasksWaitingToSend list에 넣음
```

그림으로 보면:

```text
+------------------------------------------------+
|                    Queue_t                     |
|------------------------------------------------|
| buffer                                         |
|                                                |
| +------+------+------+                         |
| |  A   |  B   |  C   |                         |
| +------+------+------+                         |
|                                                |
| uxMessagesWaiting = 3                          |
| uxLength = 3                                   |
|------------------------------------------------|
| xTasksWaitingToSend                            |
|                                                |
| +----------------+                             |
| | ListItem_t B   | ----> TCB B                 |
| +----------------+                             |
|                                                |
|------------------------------------------------|
| xTasksWaitingToReceive                         |
|                                                |
| empty                                          |
+------------------------------------------------+
```

Task B는 이런 상태입니다.

```text
Task B
  |
  v
"queue에 빈 공간이 생길 때까지 기다리는 중"
```

## 그 상태에서 다른 task가 receive하면?

이제 Task A가 queue에서 데이터를 하나 받습니다.

```c
xQueueReceive(queue, &data, waitTime);
```

Queue에서 item 하나가 빠집니다.

```text
Before

+------+------+------+
|  A   |  B   |  C   |
+------+------+------+

After

+------+------+------+
|  B   |  C   |      |
+------+------+------+
```

이제 queue에 빈 공간이 생겼습니다.

그럼 send를 기다리던 Task B를 깨울 수 있습니다.

```text
receive 성공
   |
   v
send 기다리던 task가 있나?
   |
   v
Task B를 wait list에서 제거
   |
   v
Task B를 ready list로 이동
```

그림으로 보면:

```text
Before receive

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| |  A   |  B   |  C   |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToSend         |
| +----------------+          |
| | Task B item    | -> TCB B |
| +----------------+          |
+-----------------------------+


Task A가 receive


After receive

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| |  B   |  C   |      |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToSend         |
| empty                       |
+-----------------------------+

Task B는 ready list로 이동
```

즉 receive도 단순히 데이터를 꺼내는 일이 아닙니다.

```text
receive 성공
  = 데이터 꺼내기
  + send 기다리던 task 깨우기
```

## send / receive 전체 흐름

Send 흐름:

```text
xQueueGenericSend()

+--------------------------+
| queue에 빈 공간이 있는가? |
+------------+-------------+
             |
     +-------+-------+
     |               |
    Yes              No
     |               |
     v               v
+-----------+   +----------------------------+
| data 복사 |   | 기다릴 수 있는가?           |
| queue에   |   +-------------+--------------+
| 넣기      |                 |
+-----+-----+          +------+------+
      |                |             |
      v               Yes            No
+----------------+     |             |
| receive 기다린 |     v             v
| task가 있나?   |  send wait     실패 또는
+-------+--------+  list에 넣기   바로 return
        |
        v
있으면 ready list로 이동
```

Receive 흐름:

```text
xQueueReceive()

+--------------------------+
| queue에 data가 있는가?    |
+------------+-------------+
             |
     +-------+-------+
     |               |
    Yes              No
     |               |
     v               v
+-----------+   +----------------------------+
| data 꺼냄 |   | 기다릴 수 있는가?           |
+-----+-----+   +-------------+--------------+
      |                       |
      v                +------+------+
+----------------+     |             |
| send 기다린    |    Yes            No
| task가 있나?   |     |             |
+-------+--------+     v             v
        |          receive wait   실패 또는
        v          list에 넣기    바로 return
있으면 ready list로 이동
```

## Queue 안의 wait list도 결국 List_t다

앞에서 봤던 FreeRTOS list가 여기서 다시 나옵니다.

```text
xTasksWaitingToSend
xTasksWaitingToReceive
```

이 둘은 그냥 배열이 아니라 `List_t`입니다.

```text
Queue_t
 ├─ xTasksWaitingToSend     : List_t
 └─ xTasksWaitingToReceive  : List_t
```

그리고 그 list 안에는 task 자체가 아니라 `ListItem_t`가 들어갑니다.

```text
xTasksWaitingToReceive

+---------------+     +---------------+
| ListItem_t A  | --> | ListItem_t B  |
| pvOwner       |     | pvOwner       |
+------|--------+     +------|--------+
       |                     |
       v                     v
    +-------+             +-------+
    | TCB A |             | TCB B |
    +-------+             +-------+
```

즉 Queue도 내부적으로는 지난번에 배운 구조를 사용합니다.

```text
Queue
  |
  v
wait list
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

## Queue를 scheduler 관점에서 보면

일반적인 queue 설명은 보통 이렇습니다.

```text
데이터를 넣고 뺀다
```

하지만 kernel 관점에서는 이렇게 봐야 합니다.

```text
Queue는 task를 잠들게 하고,
조건이 만족되면 다시 깨우는 object다.
```

그림으로 보면:

```text
Task A
  |
  | receive 시도
  v
+----------------+
| Queue가 비어있음 |
+----------------+
  |
  v
Task A blocked
  |
  v
xTasksWaitingToReceive에 들어감


나중에 Task B가 send
  |
  v
Queue에 데이터 생김
  |
  v
Task A ready
```

즉 Queue는 task 상태를 바꿉니다.

```text
Ready  -> Blocked
Blocked -> Ready
```

이게 kernel object로서 Queue가 중요한 이유입니다.

## Semaphore도 Queue 위에서 만들어진다

Semaphore는 쉽게 말하면 token입니다.

```text
토큰이 있으면 통과
토큰이 없으면 기다림
```

예를 들어 binary semaphore는 이런 느낌입니다.

```text
Binary Semaphore

+-------+
| token |
+-------+
```

토큰이 있으면 task가 가져갑니다.

```text
Before

+-------+
| token |
+-------+

Task A가 take

After

+-------+
| empty |
+-------+
```

토큰이 없는데 take하면 기다립니다.

```text
+-------+
| empty |
+-------+

Task B가 take 시도
        |
        v
기다림
```

이건 queue와 매우 비슷합니다.

```text
queue receive
    = data를 기다림

semaphore take
    = token을 기다림
```

그래서 FreeRTOS는 semaphore를 완전히 새로운 구조로 만들지 않고 queue 구조를
재사용합니다.

```text
Semaphore
   |
   v
Queue_t 기반으로 구현됨
```

## Semaphore를 Queue처럼 보면

일반 queue는 데이터를 저장합니다.

```text
Queue

+------+------+------+
| data | data |      |
+------+------+------+
```

Semaphore는 데이터 자체보다 개수가 중요합니다.

```text
Counting Semaphore

+----------------------+
| token count = 2      |
+----------------------+
```

즉 queue의 저장 공간 의미가 약해지고, 대신 이런 의미가 됩니다.

```text
uxMessagesWaiting
    queue에서는: 현재 들어 있는 message 개수
    semaphore에서는: 현재 사용 가능한 token 개수
```

그림으로 보면:

```text
Queue_t used as Semaphore

+------------------------------------------------+
|                    Queue_t                     |
|------------------------------------------------|
| storage buffer                                 |
|   거의 중요하지 않음                           |
|------------------------------------------------|
| uxMessagesWaiting                              |
|   사용 가능한 token 수                         |
|------------------------------------------------|
| xTasksWaitingToReceive                         |
|   semaphore take를 기다리는 task들             |
|------------------------------------------------|
| xTasksWaitingToSend                            |
|   semaphore give 쪽에서 필요할 수 있는 대기 list|
+------------------------------------------------+
```

## Mutex도 Queue 위에서 만들어진다

Mutex는 semaphore와 비슷하지만, 하나가 더 중요합니다.

```text
Mutex = lock + owner 정보
```

즉:

```text
누가 이 mutex를 가지고 있는가?
```

가 중요합니다.

```text
Mutex

+---------------------------+
| owner = Task A            |
| locked                    |
+---------------------------+
```

Task A가 mutex를 가지고 있는데 Task B가 mutex를 얻으려고 하면:

```text
Task B
  |
  | mutex take 시도
  v
이미 Task A가 가지고 있음
  |
  v
Task B blocked
  |
  v
mutex wait list에 들어감
```

그림으로 보면:

```text
+------------------------------------------------+
|                  Mutex                         |
|------------------------------------------------|
| owner: Task A                                  |
| state: locked                                  |
|------------------------------------------------|
| waiting tasks                                  |
|                                                |
| +----------------+                             |
| | Task B item    | ----> TCB B                 |
| +----------------+                             |
+------------------------------------------------+
```

## Mutex에는 priority inheritance가 있다

Mutex가 semaphore보다 더 복잡한 이유는 priority inheritance 때문입니다.

상황을 보겠습니다.

```text
Task A: 낮은 priority
Task B: 높은 priority
```

Task A가 mutex를 가지고 있습니다.

```text
Mutex owner = Task A
```

그런데 높은 priority인 Task B가 mutex를 기다립니다.

```text
Task B wants mutex
        |
        v
blocked because Task A owns mutex
```

문제는 Task A의 priority가 낮으면 빨리 실행되지 않을 수 있다는 점입니다.

그러면 높은 priority인 Task B도 계속 기다리게 됩니다.

그래서 FreeRTOS는 임시로 Task A의 priority를 올릴 수 있습니다.

```text
Task B가 높은 priority로 mutex를 기다림
        |
        v
Task A의 priority를 임시로 올림
        |
        v
Task A가 빨리 실행됨
        |
        v
mutex를 빨리 release
        |
        v
Task B가 mutex 획득
```

이게 priority inheritance입니다.

그림으로 보면:

```text
Before

Task A priority 1
Task B priority 5

Mutex owner = Task A
Task B waits


Priority inheritance

Task A priority 1  ---- temporarily becomes ----> priority 5


After Task A releases mutex

Task A priority returns to 1
Task B gets mutex
```

## union은 왜 있을까?

Queue 구조체 안에는 이런 부분이 있습니다.

```c
union
{
    QueuePointers_t xQueue;
    SemaphoreData_t xSemaphore;
} u;
```

`union`은 같은 메모리 공간을 여러 방식으로 해석하게 해줍니다.

즉, 이 object가 일반 queue로 쓰이면:

```text
u.xQueue로 해석
```

semaphore나 mutex로 쓰이면:

```text
u.xSemaphore로 해석
```

그림으로 보면:

```text
+--------------------------------+
|              u                 |
|--------------------------------|
|                                |
|  일반 Queue일 때               |
|  +--------------------------+  |
|  | QueuePointers_t xQueue   |  |
|  +--------------------------+  |
|                                |
|  Semaphore/Mutex일 때          |
|  +--------------------------+  |
|  | SemaphoreData_t          |  |
|  | xSemaphore               |  |
|  +--------------------------+  |
|                                |
+--------------------------------+
```

중요한 점은 둘을 동시에 쓰는 게 아닙니다.

```text
같은 메모리 공간을
queue일 때는 queue용 정보로 쓰고,
semaphore일 때는 semaphore용 정보로 쓴다.
```

## Queue, Semaphore, Mutex 관계

겉으로는 API가 다릅니다.

```text
xQueueSend()
xQueueReceive()

xSemaphoreGive()
xSemaphoreTake()

xSemaphoreCreateMutex()
xSemaphoreTake()
xSemaphoreGive()
```

하지만 내부적으로는 비슷한 구조를 공유합니다.

```text
+----------------------+
|       Queue_t        |
+----------------------+
          ^
          |
          |
+---------+----------+
|                    |
|                    |
v                    v
Queue            Semaphore
                      |
                      v
                   Mutex
```

조금 더 정확히 말하면:

```text
일반 Queue
    = data buffer + send/receive wait list

Semaphore
    = token count + wait list

Mutex
    = token + owner + priority inheritance + wait list
```

## 한 그림으로 전체 정리

```text
+--------------------------------------------------------------+
|                         Queue_t                              |
|--------------------------------------------------------------|
|                                                              |
|  [1] Storage Buffer                                          |
|                                                              |
|      pcHead                                                  |
|        |                                                     |
|        v                                                     |
|      +------+------+------+------+                           |
|      | item | item |      |      |                           |
|      +------+------+------+------+                           |
|                    ^                                         |
|                    |                                         |
|                pcWriteTo                                     |
|                                                              |
|--------------------------------------------------------------|
|                                                              |
|  [2] Queue State                                             |
|                                                              |
|      uxMessagesWaiting = 현재 들어 있는 item 수              |
|      uxLength          = queue 최대 길이                     |
|      uxItemSize        = item 하나의 크기                    |
|                                                              |
|--------------------------------------------------------------|
|                                                              |
|  [3] Tasks Waiting To Send                                   |
|                                                              |
|      queue가 꽉 차서 send 못 하는 task들                    |
|                                                              |
|      +---------------+     +---------------+                 |
|      | ListItem_t    | --> | ListItem_t    |                 |
|      | pvOwner       |     | pvOwner       |                 |
|      +------|--------+     +------|--------+                 |
|             |                     |                          |
|             v                     v                          |
|          +-------+             +-------+                     |
|          | TCB A |             | TCB B |                     |
|          +-------+             +-------+                     |
|                                                              |
|--------------------------------------------------------------|
|                                                              |
|  [4] Tasks Waiting To Receive                                |
|                                                              |
|      queue가 비어서 receive 못 하는 task들                  |
|                                                              |
|      +---------------+     +---------------+                 |
|      | ListItem_t    | --> | ListItem_t    |                 |
|      | pvOwner       |     | pvOwner       |                 |
|      +------|--------+     +------|--------+                 |
|             |                     |                          |
|             v                     v                          |
|          +-------+             +-------+                     |
|          | TCB C |             | TCB D |                     |
|          +-------+             +-------+                     |
|                                                              |
+--------------------------------------------------------------+
```

## send 성공 시 그림

```text
상황:
receive를 기다리는 Task C가 있음
Task A가 queue에 send 성공
```

```text
Before

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| |      |      |      |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToReceive      |
| +----------------+          |
| | Task C item    | -> TCB C |
| +----------------+          |
+-----------------------------+


Task A sends data


After

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| | data |      |      |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToReceive      |
| empty                       |
+-----------------------------+

Task C moves to ready list
```

핵심:

```text
send 성공
  -> data가 queue에 들어감
  -> receive 기다리던 task를 깨울 수 있음
  -> 필요하면 context switch 발생
```

## receive 성공 시 그림

```text
상황:
queue가 꽉 차 있어서 send를 기다리던 Task B가 있음
Task A가 receive 성공
```

```text
Before

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| |  X   |  Y   |  Z   |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToSend         |
| +----------------+          |
| | Task B item    | -> TCB B |
| +----------------+          |
+-----------------------------+


Task A receives data


After

+-----------------------------+
| Queue buffer                |
| +------+------+------+       |
| |  Y   |  Z   |      |       |
| +------+------+------+       |
+-----------------------------+
| xTasksWaitingToSend         |
| empty                       |
+-----------------------------+

Task B moves to ready list
```

핵심:

```text
receive 성공
  -> data가 queue에서 빠짐
  -> send 기다리던 task를 깨울 수 있음
  -> 필요하면 context switch 발생
```

## Queue를 커널 object로 봐야 하는 이유

일반 자료구조 수업에서 queue는 이렇게 봅니다.

```text
Queue = FIFO 자료구조
```

하지만 FreeRTOS에서는 이렇게 봐야 합니다.

```text
Queue = synchronization object
```

즉, task들 사이의 실행 순서를 조절합니다.

```text
Task A가 데이터를 기다림
        |
        v
Queue가 Task A를 blocked 상태로 보냄

Task B가 데이터를 보냄
        |
        v
Queue가 Task A를 ready 상태로 깨움
```

그림으로 보면:

```text
+---------+       receive empty       +---------+
| Ready   | ------------------------> | Blocked |
| Task A  |                           | Task A  |
+---------+                           +---------+
                                           |
                                           | Task B sends data
                                           v
                                      +---------+
                                      | Ready   |
                                      | Task A  |
                                      +---------+
```

즉 Queue는 데이터를 담는 것뿐 아니라, task의 상태 전환에도 관여합니다.

## 최종 요약

```text
Queue_t
    = FreeRTOS의 queue object

pcHead
    = queue buffer의 시작 위치

pcWriteTo
    = 다음 데이터를 쓸 위치

uxMessagesWaiting
    = 현재 들어 있는 item 수

uxLength
    = queue 최대 길이

uxItemSize
    = item 하나의 크기

xTasksWaitingToSend
    = queue가 꽉 차서 send 못 하고 기다리는 task list

xTasksWaitingToReceive
    = queue가 비어서 receive 못 하고 기다리는 task list

u.xQueue
    = 일반 queue로 쓸 때 필요한 정보

u.xSemaphore
    = semaphore/mutex로 쓸 때 필요한 정보

cRxLock, cTxLock
    = queue 동작 중 receive/send 관련 변경을 잠시 기록하는 lock 카운터
```

진짜 핵심은 이것입니다.

```text
FreeRTOS Queue는 단순 FIFO buffer가 아니다.

Queue는
데이터를 보관하고,
send 못 하는 task를 재우고,
receive 못 하는 task를 재우고,
조건이 만족되면 그 task들을 다시 ready 상태로 깨운다.
```

가장 중요한 그림은 이겁니다.

```text
                 +----------------+
                 |    Queue_t     |
                 +----------------+
                    /     |      \
                   /      |       \
                  v       v        v

        +-------------+  +-------------+  +-------------+
        | data buffer |  | send wait   |  | receive wait|
        |             |  | task list   |  | task list   |
        +-------------+  +-------------+  +-------------+
                                |              |
                                v              v
                              TCB들          TCB들
```

그래서 `Queue_t`는 단순한 IPC용 FIFO가 아니라, FreeRTOS에서 task들을 잠들게 하고
깨우는 동기화 kernel object라고 이해하면 됩니다.
