# Semaphores

이번 주제는 Semaphore입니다.

앞에서 Queue를 배웠다면 semaphore는 훨씬 쉽게 볼 수 있습니다.

핵심은 이것입니다.

```text
FreeRTOS semaphore는 완전히 새로운 자료구조가 아니다.

Queue 구현을 재사용해서 만든
"token을 주고받는 동기화 object"다.
```

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/queue.c`
- `FreeRTOS-Kernel/include/semphr.h`
- `FreeRTOS-Kernel/include/queue.h`

## Semaphore를 토큰으로 생각하기

Semaphore는 쉽게 말하면 token이 있으면 통과, 없으면 기다림입니다.

```text
Semaphore

+---------+
| token   |
+---------+
```

Task가 semaphore를 `take`하면 token을 가져갑니다.

```text
Before take

+---------+
| token   |
+---------+


Task A take


After take

+---------+
| empty   |
+---------+
```

이제 token이 없으므로 다른 task가 take하려고 하면 기다려야 합니다.

```text
Task B take 시도
        |
        v
token 없음
        |
        v
Task B blocked
```

## Binary semaphore

Binary semaphore는 token이 최대 1개인 semaphore입니다.

```text
Binary Semaphore

상태 1: token 있음

+---------+
| token   |
+---------+


상태 2: token 없음

+---------+
| empty   |
+---------+
```

즉 binary semaphore는 이런 질문에 답합니다.

```text
지금 신호가 있는가?
```

예를 들어 interrupt가 어떤 일이 발생했음을 task에게 알려줄 때 사용할 수
있습니다.

```text
ISR:
    "데이터 들어왔어!"
    semaphore give

Task:
    semaphore take로 기다리다가 깨어남
```

## Counting semaphore

Counting semaphore는 token이 여러 개 있을 수 있습니다.

```text
Counting Semaphore

+----------------+
| token count = 3|
+----------------+
```

Task가 take하면 token 수가 줄어듭니다.

```text
Before

token count = 3


Task A take


After

token count = 2
```

Task가 give하면 token 수가 늘어납니다.

```text
Before

token count = 2


Task B give


After

token count = 3
```

즉 counting semaphore는 이런 상황에 어울립니다.

```text
사용 가능한 자원이 여러 개 있음

예:
- buffer slot 3개
- 연결 가능한 장치 2개
- 사용 가능한 resource N개
```

## Semaphore는 Queue 위에서 만들어진다

중요한 점입니다.

FreeRTOS에서 semaphore는 내부적으로 queue 메커니즘을 사용합니다.

일반 queue는 데이터를 저장합니다.

```text
Queue

+------+------+------+
| data | data |      |
+------+------+------+
```

Semaphore는 데이터 내용보다 token이 있는지, 몇 개인지가 중요합니다.

```text
Semaphore

+----------------------+
| token count          |
+----------------------+
```

그래서 semaphore는 이렇게 볼 수 있습니다.

```text
Semaphore
    =
Queue에서 data payload의 중요성을 줄이고,
token 상태와 wait list를 중심으로 쓰는 object
```

## Queue와 semaphore 비교

```text
Queue

+------------------------------------------------+
| data buffer                                    |
| +------+------+------+                         |
| |  A   |  B   |      |                         |
| +------+------+------+                         |
|                                                |
| receive wait list                              |
| send wait list                                 |
+------------------------------------------------+
```

```text
Semaphore

+------------------------------------------------+
| token state                                    |
| token 있음 / 없음                              |
| 또는 token count                               |
|                                                |
| take wait list                                 |
| give로 깨울 수 있는 task들                     |
+------------------------------------------------+
```

Queue에서는 데이터가 중요합니다.

```text
Queue:
    "어떤 데이터를 전달할 것인가?"
```

Semaphore에서는 상태 변화가 중요합니다.

```text
Semaphore:
    "token이 생겼는가?"
    "기다리던 task를 깨울 수 있는가?"
```

## give semaphore

Semaphore `give`는 token을 available 상태로 만드는 동작입니다.

```text
give semaphore
    |
    v
token을 사용 가능하게 만듦
    |
    v
기다리는 task가 있으면 깨움
```

그림:

```text
Before give

Semaphore
+----------------+
| token 없음     |
+----------------+

Waiting tasks
+----------------+
| Task A         |
+----------------+


Task B gives semaphore


After give

Semaphore
+----------------+
| token available|
+----------------+

Task A moves to ready list
```

즉 `give`는 단순히 token count를 올리는 것만이 아닙니다.

```text
give 성공
    =
token 사용 가능
+
기다리던 taker를 ready list로 이동 가능
```

## take semaphore

Semaphore `take`는 token을 가져가는 동작입니다.

Token이 있으면 바로 가져갑니다.

```text
Before take

Semaphore
+----------------+
| token 있음     |
+----------------+


Task A take


After take

Semaphore
+----------------+
| token 없음     |
+----------------+
```

Token이 없으면 기다릴 수 있습니다.

```text
Task A take
    |
    v
token 없음
    |
    v
기다릴 시간이 있음
    |
    v
Task A를 semaphore wait list에 넣음
    |
    v
scheduler가 다른 task 선택
```

그림:

```text
Before

Running
+---------+
| Task A  |
+---------+

Semaphore
+----------------+
| token 없음     |
+----------------+

Wait list
empty


Task A calls take


After

Running
다른 task 실행

Semaphore wait list
+----------------+
| Task A         |
+----------------+
```

## Semaphore wait도 queue wait와 같은 패턴이다

Queue에서 배운 패턴과 똑같습니다.

Queue receive에서 데이터가 없으면:

```text
Queue empty
    |
    v
current task blocks
    |
    v
queue receive wait list
```

Semaphore take에서 token이 없으면:

```text
Semaphore unavailable
    |
    v
current task blocks
    |
    v
semaphore wait list
```

둘 다 본질은 같습니다.

```text
event unavailable
    -> block current task

event becomes available
    -> unblock waiting task
```

그림:

```text
Queue

data 없음
   |
   v
Task blocked
   |
   v
receive wait list
   |
   v
data 들어오면 ready list


Semaphore

token 없음
   |
   v
Task blocked
   |
   v
semaphore wait list
   |
   v
give 되면 ready list
```

## Semaphore 안에도 wait list가 있다

Semaphore를 내부적으로 보면 이런 느낌입니다.

```text
+------------------------------------------------+
|                  Semaphore                     |
|------------------------------------------------|
|                                                |
|  token state                                   |
|                                                |
|  binary: token 있음 / 없음                     |
|  counting: token count                         |
|                                                |
|------------------------------------------------|
|                                                |
|  Waiting tasks                                 |
|                                                |
|  token이 없어서 take 못 하고 기다리는 task들   |
|                                                |
|  +----------------+     +----------------+     |
|  | ListItem_t     | --> | ListItem_t     |     |
|  | pvOwner        |     | pvOwner        |     |
|  +------|---------+     +------|---------+     |
|         |                      |               |
|         v                      v               |
|      +-------+              +-------+          |
|      | TCB A |              | TCB B |          |
|      +-------+              +-------+          |
|                                                |
+------------------------------------------------+
```

여기서도 list 안에는 task 전체가 아니라 `ListItem_t`가 들어갑니다.

```text
wait list item
    |
    v
pvOwner
    |
    v
TCB_t
```

## take 실패 후 기다리는 과정

Task A가 semaphore를 take하려고 합니다.

```c
xSemaphoreTake(sem, 100);
```

그런데 token이 없습니다.

```text
Semaphore

+---------+
| empty   |
+---------+
```

그러면 Task A는 wait list에 들어갑니다.

```text
Task A running
     |
     | xSemaphoreTake()
     v

+----------------------+
| token이 있는가?      |
+----------+-----------+
           |
          No
           |
           v
+----------------------+
| 기다릴 수 있는가?    |
+----------+-----------+
           |
          Yes
           |
           v
+----------------------+
| Task A를 wait list에 |
| 넣음                 |
+----------+-----------+
           |
           v
+----------------------+
| scheduler가 다른 task|
| 선택                 |
+----------------------+
```

그림:

```text
Before

Ready / Running
+---------+
| Task A  |
+---------+

Semaphore wait list
empty


After take blocks

Semaphore wait list
+----------------+
| Task A item    | ---> TCB A
+----------------+

CPU는 다른 ready task 실행
```

## give로 기다리던 task 깨우기

나중에 Task B나 ISR이 semaphore를 give합니다.

```c
xSemaphoreGive(sem);
```

또는 ISR에서는:

```c
xSemaphoreGiveFromISR(sem, &xHigherPriorityTaskWoken);
```

그러면 기다리던 task를 깨울 수 있습니다.

```text
Semaphore give
    |
    v
wait list에 task가 있는가?
    |
    v
Task A가 기다리는 중
    |
    v
Task A를 wait list에서 제거
    |
    v
Task A를 ready list에 넣음
```

그림:

```text
Before give

Semaphore wait list
+----------------+
| Task A         |
+----------------+

Ready list
+----------------+
| Task B         |
+----------------+


Task B gives semaphore


After give

Semaphore wait list
empty

Ready list
+----------------+     +----------------+
| Task B         | --> | Task A         |
+----------------+     +----------------+
```

Task A가 더 높은 priority라면 context switch가 발생할 수도 있습니다.

```text
Task A priority > current task priority
    |
    v
yield / PendSV 요청 가능
```

## Queue와 semaphore의 대응 관계

Queue에서:

```text
xQueueSend()
    = data를 넣음
    = receiver를 깨울 수 있음

xQueueReceive()
    = data를 꺼냄
    = data 없으면 기다림
```

Semaphore에서:

```text
xSemaphoreGive()
    = token을 제공
    = taker를 깨울 수 있음

xSemaphoreTake()
    = token을 소비
    = token 없으면 기다림
```

그림으로 비교:

```text
Queue

send data
   |
   v
receiver wakes


Semaphore

give token
   |
   v
taker wakes
```

```text
Queue

receive data
   |
   v
data 없으면 wait


Semaphore

take token
   |
   v
token 없으면 wait
```

## Semaphore에서 payload는 중요하지 않다

Queue는 item 자체가 중요합니다.

```text
Queue

+----------------+
| temperature=25 |
+----------------+
```

Semaphore는 item 내용이 중요하지 않습니다.

```text
Semaphore

+----------------+
| token exists   |
+----------------+
```

즉 queue에서는 질문이 이것입니다.

```text
무슨 데이터를 받았는가?
```

Semaphore에서는 질문이 이것입니다.

```text
신호가 왔는가?
자원이 사용 가능한가?
```

그래서 본문에서 말한:

```text
A queue without interesting payload
```

는 이런 뜻입니다.

```text
Semaphore는 queue처럼 동작하지만,
실제로 전달되는 data payload는 중요하지 않고
token 상태가 중요하다.
```

## Binary semaphore 예시: ISR이 task 깨우기

예를 들어 버튼 interrupt가 발생하면 task를 깨우고 싶다고 합시다.

```text
Button ISR
    |
    v
semaphore give
```

Task는 semaphore를 기다리고 있습니다.

```text
ButtonTask
    |
    v
xSemaphoreTake(buttonSem, portMAX_DELAY)
```

흐름:

```text
ButtonTask
    |
    | take semaphore
    v
token 없음
    |
    v
blocked


Button interrupt 발생
    |
    v
ISR gives semaphore
    |
    v
ButtonTask ready
```

그림:

```text
Before button press

Semaphore
+---------+
| empty   |
+---------+

Wait list
+----------------+
| ButtonTask     |
+----------------+


Button ISR gives semaphore


After

Semaphore
+----------------+
| token or wake  |
+----------------+

Wait list
empty

Ready list
+----------------+
| ButtonTask     |
+----------------+
```

## Counting semaphore 예시: 자원 개수 관리

예를 들어 동시에 사용할 수 있는 buffer가 3개 있다고 합시다.

```text
Available buffers = 3
```

Counting semaphore로 표현하면:

```text
Counting Semaphore

+----------------+
| token count = 3|
+----------------+
```

Task A가 buffer를 하나 사용합니다.

```text
Task A take

token count: 3 -> 2
```

Task B도 하나 사용합니다.

```text
Task B take

token count: 2 -> 1
```

Task C도 하나 사용합니다.

```text
Task C take

token count: 1 -> 0
```

이제 Task D가 take하려고 하면?

```text
token count = 0
    |
    v
Task D blocked
```

누군가 buffer를 반환하면 give합니다.

```text
Task A returns buffer
    |
    v
semaphore give
    |
    v
Task D wakes
```

그림:

```text
Counting Semaphore

token count = 0

Wait list
+----------------+
| Task D         |
+----------------+


Task A gives


Wait list
empty

Ready list
+----------------+
| Task D         |
+----------------+
```

## Semaphore도 결국 list movement다

앞에서 계속 배운 FreeRTOS의 핵심 패턴입니다.

```text
상태 변화
    =
list 이동
```

Semaphore에서도 똑같습니다.

Token 없을 때 take:

```text
Ready List
    |
    | xSemaphoreTake(), token 없음
    v
Semaphore Wait List
```

Give로 깨우기:

```text
Semaphore Wait List
    |
    | xSemaphoreGive()
    v
Ready List
```

그림:

```text
                     token unavailable
Ready List  ------------------------------>  Semaphore Wait List
     ^                                                |
     |                                                |
     |                  give token                    |
     +------------------------------------------------+
```

## ISR에서 semaphore give

ISR에서도 semaphore를 줄 수 있습니다.

```text
xSemaphoreGiveFromISR()
```

ISR은 block할 수 없습니다.
하지만 기다리던 task를 깨울 수는 있습니다.

```text
ISR
    |
    v
semaphore give
    |
    v
waiting task wakes
    |
    v
higher priority task가 깨어났는지 확인
    |
    v
필요하면 portYIELD_FROM_ISR()
```

그림:

```text
+-----------------------------+
| ISR                         |
+-----------------------------+
        |
        v
+-----------------------------+
| xSemaphoreGiveFromISR()     |
+-------------+---------------+
              |
              v
+-----------------------------+
| waiting task 깨움 가능      |
+-------------+---------------+
              |
              v
+-----------------------------+
| 더 높은 priority task인가?  |
+-------------+---------------+
              |
        +-----+-----+
        |           |
       Yes          No
        |           |
        v           v
+----------------+  ISR 종료
| portYIELD_     |
| FROM_ISR()     |
+-------+--------+
        |
        v
+----------------+
| PendSV pending |
+----------------+
```

## Semaphore와 Mutex는 다르다

이번 장은 semaphore이고, 다음 장은 mutex입니다.

둘은 비슷하지만 중요한 차이가 있습니다.

```text
Semaphore
    = token이 있는가?
    = 누가 가져갔는지는 핵심이 아님

Mutex
    = lock을 누가 소유하고 있는가?
    = owner가 중요함
    = priority inheritance가 붙을 수 있음
```

비교:

```text
Semaphore

+----------------+
| token count    |
+----------------+


Mutex

+----------------+
| owner = Task A |
| locked         |
+----------------+
```

그래서 semaphore는 신호나 개수에 가깝고, mutex는 소유권 있는 lock에 가깝습니다.

## 전체 그림

```text
+------------------------------------------------+
|                  Semaphore                     |
|------------------------------------------------|
|                                                |
|  Token State                                   |
|                                                |
|  Binary semaphore:                             |
|      token 있음 / 없음                         |
|                                                |
|  Counting semaphore:                           |
|      token count = N                           |
|                                                |
|------------------------------------------------|
|                                                |
|  Waiting Tasks                                 |
|                                                |
|  token이 없어서 take 못 하는 task들            |
|                                                |
|  +----------------+     +----------------+     |
|  | Task A item    | --> | Task B item    |     |
|  | pvOwner -> TCB |     | pvOwner -> TCB |     |
|  +----------------+     +----------------+     |
|                                                |
+------------------------------------------------+
```

동작:

```text
take
    |
    +--> token 있으면 소비하고 계속 실행
    |
    +--> token 없으면 wait list로 이동 가능


give
    |
    +--> token available 상태로 만듦
    |
    +--> 기다리는 task가 있으면 ready list로 이동 가능
```

## 최종 요약

```text
Semaphore
    = FreeRTOS에서 queue 메커니즘 위에 만들어진 동기화 object

Binary semaphore
    = token이 0개 또는 1개

Counting semaphore
    = token이 여러 개 가능

xSemaphoreTake()
    = token을 소비
    = token 없으면 task가 block될 수 있음

xSemaphoreGive()
    = token을 제공
    = 기다리던 task를 깨울 수 있음

Semaphore wait list
    = token이 없어서 기다리는 task들이 들어가는 list

핵심 패턴
    event unavailable
        -> current task block

    event available
        -> waiting task unblock
```

가장 중요한 그림은 이것입니다.

```text
Ready List
    |
    | take semaphore, token 없음
    v
Semaphore Wait List
    |
    | give semaphore
    v
Ready List
```

한 문장으로 정리하면:

```text
FreeRTOS semaphore는 queue처럼 wait list를 이용하지만,
중요한 것은 data payload가 아니라
token의 존재와 task를 재우고 깨우는 상태 변화다.
```
