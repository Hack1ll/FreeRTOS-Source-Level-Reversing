# Queues

이번에는 Queue를 데이터 보관함과 기다리는 task 대기실로 생각하면 됩니다.

핵심은 이것입니다.

```text
FreeRTOS Queue는 단순 FIFO buffer가 아니다.

Queue는
1. 데이터를 저장하고
2. 데이터를 받으려다 실패한 task를 재우고
3. 데이터를 보내려다 실패한 task를 재우고
4. 조건이 맞으면 task를 다시 깨운다.
```

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/queue.c`
- `FreeRTOS-Kernel/include/queue.h`
- `FreeRTOS-Kernel/tasks.c`

## 일반적인 Queue

자료구조 시간에 배운 queue는 보통 이런 모습입니다.

```text
FIFO Queue

+-----+-----+-----+-----+
|  A  |  B  |  C  |     |
+-----+-----+-----+-----+

A가 먼저 들어왔으므로 A가 먼저 나감
```

즉:

```text
send
    = queue에 data 넣기

receive
    = queue에서 data 꺼내기
```

하지만 FreeRTOS queue는 여기서 끝나지 않습니다.

## FreeRTOS Queue는 더 크다

FreeRTOS의 Queue는 대략 이렇게 봐야 합니다.

```text
+------------------------------------------------+
|                    Queue                       |
|------------------------------------------------|
|                                                |
|  [1] Data Buffer                               |
|                                                |
|      +------+------+------+                    |
|      | data | data |      |                    |
|      +------+------+------+                    |
|                                                |
|------------------------------------------------|
|                                                |
|  [2] Receive Wait List                         |
|                                                |
|      queue가 비어서 receive 못 하는 task들      |
|                                                |
|------------------------------------------------|
|                                                |
|  [3] Send Wait List                            |
|                                                |
|      queue가 꽉 차서 send 못 하는 task들        |
|                                                |
+------------------------------------------------+
```

즉 Queue는 세 가지를 가지고 있습니다.

```text
Queue
 ├─ data buffer
 ├─ receive wait list
 └─ send wait list
```

## Send는 데이터 복사만이 아니다

`xQueueGenericSend()`는 queue에 데이터를 넣는 함수입니다.

겉으로 보면:

```text
xQueueGenericSend()
    -> queue buffer에 data 복사
```

하지만 실제로는 하나 더 중요합니다.

```text
xQueueGenericSend()
    -> queue buffer에 data 복사
    -> receive 기다리는 task가 있는지 확인
    -> 있으면 그 task를 ready list로 이동
```

그림으로 보면:

```text
xQueueGenericSend()

+--------------------------+
| queue에 빈 공간이 있는가? |
+------------+-------------+
             |
            Yes
             |
             v
+--------------------------+
| data를 queue에 복사       |
+------------+-------------+
             |
             v
+--------------------------+
| receive 기다리는 task가?  |
+------------+-------------+
             |
       +-----+-----+
       |           |
      있음        없음
       |           |
       v           v
+-------------+   끝
| waiting     |
| receiver를  |
| ready로 이동|
+-------------+
```

## Send 예시

Task A가 queue에서 데이터를 기다리고 있다고 합시다.

```text
Task A
    |
    | xQueueReceive()
    v
queue가 비어 있음
    |
    v
receive wait list로 이동
```

상태는 이렇게 됩니다.

```text
+------------------------------------------------+
|                    Queue                       |
|------------------------------------------------|
| Data Buffer                                    |
|                                                |
| +------+------+------+                         |
| |      |      |      |                         |
| +------+------+------+                         |
|                                                |
|------------------------------------------------|
| Receive Wait List                              |
|                                                |
| +----------------+                             |
| | Task A item    | ---> TCB A                  |
| +----------------+                             |
+------------------------------------------------+
```

이제 Task B가 데이터를 보냅니다.

```text
Task B
    |
    | xQueueSend(queue, X)
    v
queue에 X 넣기
```

결과는 두 가지입니다.

```text
1. queue buffer에 X가 들어감
2. Task A가 receive wait list에서 빠져 ready list로 이동
```

그림:

```text
Before send

Queue buffer
+------+------+------+
|      |      |      |
+------+------+------+

Receive Wait List
+----------------+
| Task A         |
+----------------+


Task B sends X


After send

Queue buffer
+------+------+------+
|  X   |      |      |
+------+------+------+

Receive Wait List
empty

Ready List
+----------------+
| Task A         |
+----------------+
```

즉:

```text
send 성공
    = data 넣기
    + receive 기다리던 task 깨우기
```

## Receive도 데이터 꺼내기만이 아니다

`xQueueReceive()`는 queue에서 데이터를 꺼냅니다.

데이터가 있으면 간단합니다.

```text
Before receive

Queue buffer
+------+------+------+
|  A   |  B   |      |
+------+------+------+

Task receives

After receive

Queue buffer
+------+------+------+
|  B   |      |      |
+------+------+------+
```

하지만 queue가 비어 있으면 task가 기다릴 수 있습니다.

```text
xQueueReceive()
    |
    v
queue empty
    |
    v
기다릴 수 있는 timeout이 있는가?
    |
    v
현재 task를 receive wait list에 넣음
    |
    v
scheduler가 다른 task 실행
```

그림:

```text
Before

Running
+---------+
| Task A  |
+---------+

Queue buffer
+------+------+------+
|      |      |      |
+------+------+------+

Receive Wait List
empty


Task A calls xQueueReceive()


After

Running
+------------------+
| 다른 task 실행    |
+------------------+

Receive Wait List
+----------------+
| Task A         |
+----------------+
```

즉:

```text
receive 시도
    + data 있음
        -> data 꺼내고 계속 실행

receive 시도
    + data 없음
        -> 기다릴 수 있으면 task block
```

## Receive 성공은 sender를 깨울 수도 있다

반대로 queue가 꽉 차 있다고 해봅시다.

```text
Queue buffer

+------+------+------+
|  A   |  B   |  C   |
+------+------+------+

queue full
```

Task D가 send하려고 합니다.

```text
Task D
    |
    | xQueueSend()
    v
queue full
    |
    v
send wait list로 이동
```

상태:

```text
+------------------------------------------------+
|                    Queue                       |
|------------------------------------------------|
| Data Buffer                                    |
|                                                |
| +------+------+------+                         |
| |  A   |  B   |  C   |                         |
| +------+------+------+                         |
|                                                |
|------------------------------------------------|
| Send Wait List                                 |
|                                                |
| +----------------+                             |
| | Task D item    | ---> TCB D                  |
| +----------------+                             |
+------------------------------------------------+
```

이제 Task A가 receive를 해서 데이터를 하나 꺼냅니다.

```text
Task A receives one item
```

그러면 queue에 빈 공간이 생깁니다.

이제 send를 기다리던 Task D를 깨울 수 있습니다.

```text
Before receive

Queue buffer
+------+------+------+
|  A   |  B   |  C   |
+------+------+------+

Send Wait List
+----------------+
| Task D         |
+----------------+


Task A receives


After receive

Queue buffer
+------+------+------+
|  B   |  C   |      |
+------+------+------+

Send Wait List
empty

Ready List
+----------------+
| Task D         |
+----------------+
```

즉:

```text
receive 성공
    = data 꺼내기
    + send 기다리던 task 깨우기
```

## Send와 Receive는 거울처럼 동작한다

```text
send 성공
    |
    v
receive wait list를 확인
    |
    v
기다리는 receiver를 깨울 수 있음
```

```text
receive 성공
    |
    v
send wait list를 확인
    |
    v
기다리는 sender를 깨울 수 있음
```

한 그림으로 보면:

```text
                     queue empty
Ready List  ---------------------------->  Receive Wait List
     ^                                            |
     |                                            |
     |              send data                     |
     +--------------------------------------------+


                     queue full
Ready List  ---------------------------->  Send Wait List
     ^                                            |
     |                                            |
     |              receive data                  |
     +--------------------------------------------+
```

## Queue wait는 vTaskDelay와 비슷하다

앞에서 `vTaskDelay()`를 배웠습니다.

```text
vTaskDelay()
    |
    v
Ready List에서 빠짐
    |
    v
Delayed List에 들어감
    |
    v
tick이 지나면 Ready List로 돌아옴
```

Queue도 비슷합니다.

```text
xQueueReceive()
    |
    v
queue empty
    |
    v
Ready List에서 빠짐
    |
    v
Queue Receive Wait List에 들어감
    |
    v
data가 들어오면 Ready List로 돌아옴
```

차이는 깨우는 조건입니다.

```text
vTaskDelay()
    = 시간이 지나면 깨어남

Queue receive wait
    = data가 들어오면 깨어남
```

그림:

```text
Delay

Ready List
    |
    | wait for time
    v
Delayed List
    |
    | tick reaches wake time
    v
Ready List


Queue

Ready List
    |
    | wait for data
    v
Queue Receive Wait List
    |
    | data arrives
    v
Ready List
```

## timeout이 있으면 두 list에 걸릴 수 있다

예를 들어:

```c
xQueueReceive(queue, &data, 100);
```

이 뜻은:

```text
queue에 data가 있으면 바로 받기.
없으면 최대 100 tick까지 기다리기.
```

그러면 task는 두 가지 이유로 깨어날 수 있습니다.

```text
1. queue에 data가 들어옴
2. 100 tick timeout이 끝남
```

그래서 내부적으로는 이렇게 생각할 수 있습니다.

```text
TCB A
 ├─ xStateListItem
 │    -> delayed list
 │       "timeout은 언제인가?"
 │
 └─ xEventListItem
      -> queue receive wait list
         "어떤 queue를 기다리는가?"
```

그림:

```text
                   +------------------+
                   |      TCB A       |
                   |------------------|
                   | xStateListItem   |
                   | xEventListItem   |
                   +----+--------+----+
                        |        |
                        |        |
                        v        v

             +---------------+   +--------------------------+
             | Delayed List  |   | Queue Receive Wait List  |
             | timeout=100   |   | wait for queue data      |
             +---------------+   +--------------------------+
```

즉 Task A는 이렇게 말하는 중입니다.

```text
"queue에 data가 오면 깨워줘.
그런데 100 tick이 지나도 안 오면 timeout으로 깨워줘."
```

## ISR용 Queue API는 다르다

ISR은 interrupt service routine입니다.

예를 들어:

```text
UART interrupt
Timer interrupt
GPIO button interrupt
```

ISR에서는 일반 task처럼 기다리면 안 됩니다.

그래서 ISR용 queue API는 block하지 않습니다.

```text
일반 task API

xQueueSend()
xQueueReceive()

특징:
    기다릴 수 있음
    block 가능
```

```text
ISR API

xQueueSendFromISR()
xQueueReceiveFromISR()

특징:
    기다릴 수 없음
    block 불가능
    가능하면 수행하고 바로 return
```

## ISR에서 queue send 예시

UART interrupt가 byte 하나를 받았다고 합시다.

```text
UART ISR
    |
    v
received byte = 'A'
```

그 byte를 queue에 넣습니다.

```text
xQueueSendFromISR(queue, 'A', ...)
```

어떤 task가 이 queue를 기다리고 있었다면?

```text
Task Reader
    |
    v
queue receive wait list에서 대기 중
```

ISR이 queue에 data를 넣는 순간 그 task가 깨어날 수 있습니다.

```text
Before ISR

Queue buffer
empty

Receive Wait List
+----------------+
| Reader Task    |
+----------------+


UART ISR sends 'A'


After ISR

Queue buffer
+----------------+
| A              |
+----------------+

Receive Wait List
empty

Ready List
+----------------+
| Reader Task    |
+----------------+
```

## pxHigherPriorityTaskWoken

ISR API에서 자주 나오는 변수가 있습니다.

```c
BaseType_t xHigherPriorityTaskWoken = pdFALSE;

xQueueSendFromISR(queue, &data, &xHigherPriorityTaskWoken);

portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
```

이 변수의 의미는 이것입니다.

```text
xHigherPriorityTaskWoken
    =
    이번 ISR 작업 때문에
    현재 실행 중이던 task보다 더 높은 priority task가 깨어났는가?
```

예를 들어 현재 실행 중이던 task는 priority 2입니다.

```text
Current Task
+-------------------+
| priority 2        |
+-------------------+
```

ISR 때문에 깨어난 task는 priority 4입니다.

```text
Woken Task
+-------------------+
| priority 4        |
+-------------------+
```

그러면:

```text
xHigherPriorityTaskWoken = pdTRUE
```

가 될 수 있습니다.

이 경우 ISR이 끝난 뒤 바로 더 높은 priority task로 전환하는 것이 좋습니다.

## portYIELD_FROM_ISR()

ISR에서 더 높은 priority task를 깨웠다면 context switch가 필요할 수 있습니다.

이때 사용하는 것이:

```text
portYIELD_FROM_ISR()
```

입니다.

흐름:

```text
FromISR operation wakes task
    |
    v
xHigherPriorityTaskWoken = true
    |
    v
portYIELD_FROM_ISR()
    |
    v
PendSV pending
    |
    v
ISR 종료 후 context switch
```

그림:

```text
+-----------------------------+
| ISR                         |
|-----------------------------|
| xQueueSendFromISR()         |
| queue에 data 넣기           |
| waiting task 깨움 가능      |
+-------------+---------------+
              |
              v
+-----------------------------+
| higher priority task woken? |
+-------------+---------------+
              |
        +-----+-----+
        |           |
       Yes          No
        |           |
        v           v
+-------------+    ISR 종료
| portYIELD_  |
| FROM_ISR()  |
+-------------+
        |
        v
+----------------+
| PendSV pending |
+----------------+
        |
        v
+----------------+
| context switch |
+----------------+
```

## Queue를 scheduler 관점에서 보기

Queue 코드를 읽을 때는 항상 두 가지를 같이 봐야 합니다.

```text
1. data가 어디로 복사되는가?
2. 어떤 task list가 바뀌는가?
```

Send에서는:

```text
xQueueGenericSend()
    |
    +--> data를 queue storage에 복사
    |
    +--> receive wait list에서 task를 깨울 수 있음
```

Receive에서는:

```text
xQueueReceive()
    |
    +--> data를 queue storage에서 꺼냄
    |
    +--> send wait list에서 task를 깨울 수 있음
```

ISR에서는:

```text
xQueueSendFromISR()
    |
    +--> 가능한 경우 data 복사
    |
    +--> 더 높은 priority task가 깨어났는지 보고
    |
    +--> 필요하면 portYIELD_FROM_ISR()
```

## 전체 구조 그림

```text
+--------------------------------------------------------------+
|                           Queue                              |
|--------------------------------------------------------------|
|                                                              |
|  [1] Data Buffer                                             |
|                                                              |
|      +------+------+------+                                  |
|      | item | item |      |                                  |
|      +------+------+------+                                  |
|                                                              |
|--------------------------------------------------------------|
|                                                              |
|  [2] Receive Wait List                                       |
|                                                              |
|      queue가 비어서 receive 못 하는 task들                    |
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
|  [3] Send Wait List                                          |
|                                                              |
|      queue가 꽉 차서 send 못 하는 task들                     |
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

## Queue의 핵심 패턴

Queue는 다음 패턴을 잘 보여줍니다.

```text
조건이 만족되지 않음
    |
    v
task를 wait list에 넣음

조건이 만족됨
    |
    v
wait list의 task를 ready list로 이동
```

Queue에서는 조건이 이렇게 바뀝니다.

```text
receive 입장:
    조건 = queue에 data가 있는가?

send 입장:
    조건 = queue에 빈 공간이 있는가?
```

그림:

```text
Receive path

queue empty
    |
    v
current task blocks
    |
    v
Receive Wait List
    |
    | data arrives
    v
Ready List
```

```text
Send path

queue full
    |
    v
current task blocks
    |
    v
Send Wait List
    |
    | space becomes available
    v
Ready List
```

## 최종 요약

```text
Queue
    = data buffer
    + receive wait list
    + send wait list

xQueueGenericSend()
    = item을 queue storage에 복사
    = receive 기다리는 task가 있으면 깨울 수 있음

xQueueReceive()
    = item을 queue storage에서 caller에게 복사
    = queue가 비어 있으면 current task를 receive wait list에 넣을 수 있음
    = receive 성공 시 send 기다리던 task를 깨울 수 있음

ISR queue API
    = block하지 않음
    = 가능한 operation만 수행
    = higher-priority task가 깨어났는지 알려줌

pxHigherPriorityTaskWoken
    = ISR 때문에 더 높은 priority task가 깨어났는지 표시

portYIELD_FROM_ISR()
    = ISR 종료 후 context switch를 요청
```

가장 중요한 그림은 이것입니다.

```text
                 +----------------+
                 |     Queue      |
                 +----------------+
                    /      |      \
                   /       |       \
                  v        v        v

        +-------------+  +-------------+  +-------------+
        | data buffer |  | send wait   |  | receive wait|
        |             |  | list        |  | list        |
        +-------------+  +-------------+  +-------------+
                                |              |
                                v              v
                              TCB들          TCB들
```

한 문장으로 정리하면:

```text
FreeRTOS Queue는 단순 FIFO가 아니라,
data를 주고받으면서 task를 재우고 깨우는 synchronization object다.
```
