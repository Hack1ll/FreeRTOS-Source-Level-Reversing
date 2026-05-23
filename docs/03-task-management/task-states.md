# Task states


```text
FreeRTOS task 상태는
"state = READY" 같은 enum 하나로 저장되는 게 아니라,

task의 ListItem_t가
어느 list에 들어가 있느냐로 표현된다.
```

즉 FreeRTOS에서는 task 상태를 이렇게 봐야 합니다.

```text
Task 상태 = 어떤 list에 들어 있는가?
```

---

## 1. 보통 우리가 생각하는 task state

처음에는 task 안에 이런 필드가 있을 것 같다고 생각하기 쉽습니다.

```c
typedef enum
{
    TASK_READY,
    TASK_BLOCKED,
    TASK_DELAYED,
    TASK_SUSPENDED
} TaskState;

typedef struct
{
    TaskState state;
} TCB_t;
```

그러면 task 상태는 이렇게 저장됩니다.

```text
+----------------+
| TCB_t          |
|----------------|
| state = READY  |
+----------------+
```

하지만 FreeRTOS는 핵심 scheduling 상태를 이런 식으로만 관리하지 않습니다.

FreeRTOS는 더 실용적인 방법을 씁니다.

```text
READY 상태다
    =
ready list 안에 있다

DELAYED 상태다
    =
delayed list 안에 있다

SUSPENDED 상태다
    =
suspended list 안에 있다
```

---

## 2. FreeRTOS식 상태 표현

FreeRTOS에서 task 하나는 `TCB_t`로 관리됩니다.

그 안에는 `xStateListItem`이 있습니다.

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| task name                      |
| priority                       |
| stack info                     |
|                                |
| xStateListItem                 |
| xEventListItem                 |
+--------------------------------+
```

여기서 `xStateListItem`이 task의 큰 상태를 표현합니다.

```text
TCB_t.xStateListItem
    |
    +--> ready list
    |
    +--> delayed list
    |
    +--> suspended list
```

즉 task 상태는 `xStateListItem`이 어디에 꽂혀 있는지로 알 수 있습니다.

---

## 3. Ready 상태

Task A가 실행 가능한 상태라고 해봅시다.

그럼 Task A의 `xStateListItem`은 ready list에 들어갑니다.

```text
+------------------+
|      TCB A       |
|------------------|
| xStateListItem --+----+
+------------------+    |
                        v
                +----------------+
                | Ready List     |
                |----------------|
                | Task A item    |
                +----------------+
```

이 말은 곧:

```text
Task A는 ready 상태다
```

라는 뜻입니다.

다시 말하면 FreeRTOS는 이렇게 생각합니다.

```text
Task A가 ready list 안에 있다
    =
Task A는 실행 가능하다
```

---

## 4. Delayed 상태

이번에는 Task A가 `vTaskDelay(100)`을 호출했다고 해봅시다.

그러면 Task A는 잠시 실행되면 안 됩니다.

이때 FreeRTOS는 Task A의 `xStateListItem`을 ready list에서 빼고 delayed list에 넣습니다.

```text
Before

Ready List
+----------------+
| Task A item    |
+----------------+

Delayed List
empty
```

```text
Task A calls vTaskDelay(100)
```

```text
After

Ready List
empty

Delayed List
+----------------------------+
| Task A item                |
| wake tick = current + 100  |
+----------------------------+
```

그림으로 보면:

```text
+------------------+
|      TCB A       |
|------------------|
| xStateListItem --+----+
+------------------+    |
                        v
                +----------------+
                | Delayed List   |
                |----------------|
                | Task A item    |
                | wake tick=150  |
                +----------------+
```

이 말은 곧:

```text
Task A는 delayed 상태다
```

라는 뜻입니다.

---

## 5. Suspended 상태

Task가 suspended 되면 scheduler 후보에서 완전히 빠집니다.

이때는 `xStateListItem`이 suspended list에 들어갑니다.

```text
+------------------+
|      TCB A       |
|------------------|
| xStateListItem --+----+
+------------------+    |
                        v
                +----------------+
                | Suspended List |
                |----------------|
                | Task A item    |
                +----------------+
```

즉:

```text
Task A가 suspended list 안에 있다
    =
Task A는 suspended 상태다
```

---

## 6. 중요한 그림: 상태는 list membership이다

가장 중요한 그림은 이것입니다.

```text
                    +------------------+
                    |      TCB_t       |
                    |------------------|
                    | xStateListItem   |
                    +--------+---------+
                             |
                             v

        +--------------------+--------------------+
        |                    |                    |
        v                    v                    v

+---------------+    +----------------+    +----------------+
| Ready List    |    | Delayed List   |    | Suspended List |
+---------------+    +----------------+    +----------------+
| 실행 가능 task |    | 시간 대기 task  |    | 중단된 task     |
+---------------+    +----------------+    +----------------+
```

즉 FreeRTOS에서 task 상태는 따로 떨어진 값이 아니라 list 위치입니다.

```text
상태를 바꾼다
    =
list에서 빼서 다른 list에 넣는다
```

---

## 7. 왜 enum 하나보다 list가 좋을까?

만약 모든 task가 enum 상태만 가지고 있다면 scheduler는 이런 식으로 해야 할 수 있습니다.

```text
모든 task를 하나씩 검사한다

Task A state가 READY인가?
Task B state가 READY인가?
Task C state가 READY인가?
Task D state가 READY인가?
...
```

그림으로 보면:

```text
All Tasks

+---------+ state=READY
| Task A  |
+---------+

+---------+ state=DELAYED
| Task B  |
+---------+

+---------+ state=READY
| Task C  |
+---------+

+---------+ state=SUSPENDED
| Task D  |
+---------+
```

이런 방식은 매번 찾는 비용이 커질 수 있습니다.

FreeRTOS는 scheduler가 바로 필요한 형태로 task들을 정리해둡니다.

```text
Ready List

+---------+     +---------+
| Task A  | --> | Task C  |
+---------+     +---------+
```

그러면 scheduler는 ready list만 보면 됩니다.

```text
scheduler:
    "실행 가능한 task는 ready list에 이미 모여 있네."
```

즉:

```text
list 자체가 scheduler가 바로 쓰는 자료구조다.
```

---

## 8. xStateListItem 하나가 여러 list 사이를 이동한다

`xStateListItem`은 여러 개가 생기는 게 아니라, 같은 item이 list 사이를 이동합니다.

```text
Task A의 xStateListItem

Ready List
    |
    | vTaskDelay()
    v

Delayed List
    |
    | timeout expires
    v

Ready List
    |
    | vTaskSuspend()
    v

Suspended List
```

그림:

```text
+------------------+
|      TCB A       |
|------------------|
| xStateListItem   |
+--------+---------+
         |
         v

[Ready List]  --->  [Delayed List]  --->  [Ready List]
     |                       ^                   |
     |                       |                   |
     +---- task runs         +---- wake tick     +---- scheduler can choose
```

즉 task 상태 변화는 대부분 이런 식입니다.

```text
list remove
    +
list insert
```

---

## 9. 그런데 xEventListItem도 있다

TCB에는 `xStateListItem`만 있는 것이 아닙니다.

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| xStateListItem                 |
| xEventListItem                 |
+--------------------------------+
```

`xStateListItem`은 task의 큰 상태를 나타냅니다.

```text
ready인가?
delayed인가?
suspended인가?
```

반면 `xEventListItem`은 task가 **무엇을 기다리는지** 나타냅니다.

```text
queue를 기다리는가?
semaphore를 기다리는가?
mutex를 기다리는가?
event group을 기다리는가?
```

---

## 10. xStateListItem과 xEventListItem의 차이

쉽게 비교하면 이렇습니다.

```text
xStateListItem
    = scheduler 관점의 상태
    = 이 task가 ready인지, delayed인지, suspended인지

xEventListItem
    = event object 관점의 대기 상태
    = 이 task가 어떤 queue/semaphore/event를 기다리는지
```

그림으로 보면:

```text
+--------------------------------+
|             TCB A              |
|--------------------------------|
| xStateListItem                 |
|   -> delayed list              |
|                                |
| xEventListItem                 |
|   -> queue receive wait list   |
+--------------------------------+
```

즉 하나의 task가 동시에 두 종류의 list와 관련될 수 있습니다.

---

## 11. 예시: queue를 기다리는 task

Task A가 queue에서 데이터를 받으려고 합니다.

```c
xQueueReceive(queue, &data, 100);
```

그런데 queue가 비어 있습니다.

그러면 Task A는 이렇게 됩니다.

```text
1. 지금 당장 실행할 수 없음
2. queue에 데이터가 들어오기를 기다림
3. 최대 100 tick까지만 기다림
```

이걸 FreeRTOS는 두 list item으로 표현합니다.

```text
xStateListItem
    -> delayed list
       "최대 언제까지 기다릴 것인가?"

xEventListItem
    -> queue receive wait list
       "어떤 queue를 기다리고 있는가?"
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
             |---------------|   |--------------------------|
             | wake tick=200 |   | waiting for Queue Q      |
             +---------------+   +--------------------------+
```

이게 아주 중요합니다.

하나의 blocked task가 두 가지 질문에 동시에 답해야 하기 때문입니다.

```text
언제 timeout 되는가?
무엇이 오면 timeout 전에 깨어날 수 있는가?
```

---

## 12. blocked 상태를 더 쉽게 보기

`blocked`라는 말은 약간 넓은 말입니다.

Task가 blocked 되는 이유는 여러 가지입니다.

```text
시간을 기다림
queue 데이터를 기다림
semaphore를 기다림
mutex를 기다림
event bit를 기다림
```

그래서 FreeRTOS는 이렇게 나눠서 표현합니다.

```text
시간 조건
    -> delayed list

event 조건
    -> queue/semaphore/event wait list
```

예를 들어:

```text
Task A:
    queue Q에서 데이터가 오거나,
    100 tick이 지나면 깨어나야 함
```

그림으로 보면:

```text
                        +------------------+
                        |      Task A      |
                        +------------------+
                              /      \
                             /        \
                            v          v

             +----------------+      +------------------------+
             | Delayed List   |      | Queue Q Wait List      |
             | wake tick=200  |      | data arrives?          |
             +----------------+      +------------------------+
```

Task A는 두 가지 방법으로 깨어날 수 있습니다.

```text
방법 1:
queue에 데이터가 들어온다
    -> event wait list에서 제거
    -> delayed list에서도 제거
    -> ready list로 이동

방법 2:
timeout이 된다
    -> delayed list에서 제거
    -> event wait list에서도 제거
    -> ready list로 이동
```

---

## 13. event가 먼저 발생하는 경우

Task A가 queue 데이터를 기다리고 있습니다.

```text
Task A waiting

Delayed List
+------------------+
| Task A           |
| timeout tick=200 |
+------------------+

Queue Receive Wait List
+------------------+
| Task A           |
| waiting queue Q  |
+------------------+
```

그런데 tick 200이 되기 전에 다른 task가 queue에 데이터를 넣었습니다.

```text
Task B sends data to Queue Q
```

그러면 Task A는 queue event 때문에 깨어납니다.

```text
Queue Q에 데이터 들어옴
      |
      v
Task A를 Queue Receive Wait List에서 제거
      |
      v
Task A를 Delayed List에서도 제거
      |
      v
Task A를 Ready List에 넣음
```

그림:

```text
Before

Delayed List
+------------------+
| Task A           |
+------------------+

Queue Wait List
+------------------+
| Task A           |
+------------------+

Ready List
empty


Queue event occurs


After

Delayed List
empty

Queue Wait List
empty

Ready List
+------------------+
| Task A           |
+------------------+
```

---

## 14. timeout이 먼저 발생하는 경우

반대로 queue에 데이터가 안 들어오고 시간이 먼저 끝날 수도 있습니다.

```text
tick reaches timeout
```

그러면 Task A는 timeout 때문에 깨어납니다.

```text
timeout 도달
      |
      v
Task A를 Delayed List에서 제거
      |
      v
Task A를 Queue Receive Wait List에서도 제거
      |
      v
Task A를 Ready List에 넣음
```

그림:

```text
Before

Delayed List
+------------------+
| Task A           |
| timeout tick=200 |
+------------------+

Queue Wait List
+------------------+
| Task A           |
| waiting queue Q  |
+------------------+


tick = 200


After

Delayed List
empty

Queue Wait List
empty

Ready List
+------------------+
| Task A           |
| timeout result   |
+------------------+
```

즉 blocked task는 보통 "event로 깨거나 timeout으로 깨거나" 둘 중 하나입니다.

---

## 15. task state를 list 이동으로 이해하기

FreeRTOS scheduler 코드를 읽을 때 핵심은 이것입니다.

```text
상태 변경 함수
    =
task를 list에서 빼고 다른 list에 넣는 함수
```

예를 들어 delay:

```text
Ready List
    |
    | vTaskDelay()
    v
Delayed List
```

queue wait:

```text
Ready List
    |
    | xQueueReceive() but queue empty
    v
Delayed List + Queue Wait List
```

semaphore wait:

```text
Ready List
    |
    | xSemaphoreTake() but unavailable
    v
Delayed List + Semaphore Wait List
```

wake up:

```text
Delayed/Event Wait List
    |
    | event occurs or timeout
    v
Ready List
```

---

## 16. 전체 구조 그림

```text
+------------------------------------------------------+
|                       TCB_t                          |
|------------------------------------------------------|
|                                                      |
|  xStateListItem                                      |
|     |                                                |
|     +--> Ready List                                  |
|     |       "실행 가능"                              |
|     |                                                |
|     +--> Delayed List                                |
|     |       "시간이 될 때까지 대기"                  |
|     |                                                |
|     +--> Suspended List                              |
|             "scheduler 대상 아님"                    |
|                                                      |
|------------------------------------------------------|
|                                                      |
|  xEventListItem                                      |
|     |                                                |
|     +--> Queue Wait List                             |
|     |       "queue 데이터/공간 기다림"                |
|     |                                                |
|     +--> Semaphore Wait List                         |
|     |       "token 기다림"                           |
|     |                                                |
|     +--> Mutex Wait List                             |
|             "lock 기다림"                            |
|                                                      |
+------------------------------------------------------+
```

---

## 17. 상태를 enum으로만 보면 어려운 이유

FreeRTOS 코드를 읽다가 이런 걸 찾으면 헷갈릴 수 있습니다.

```text
task->state = BLOCKED
```

그런데 핵심 scheduling code에서는 이런 단일 state field보다 list 이동이 중요합니다.

FreeRTOS식 사고방식:

```text
이 task가 ready인가?
    -> ready list에 있는가?

이 task가 delay 중인가?
    -> delayed list에 있는가?

이 task가 queue를 기다리는가?
    -> queue의 event wait list에 있는가?
```

즉 코드를 읽을 때는 이렇게 질문하는 게 좋습니다.

```text
이 함수는 어떤 list에서 task를 빼는가?
이 함수는 어떤 list에 task를 넣는가?
```

---

## 18. 예시: vTaskDelay()

`vTaskDelay()`는 가장 단순한 상태 이동입니다.

```text
Task A running
     |
     | vTaskDelay(100)
     v

Ready List에서 제거
     |
     v
Delayed List에 삽입
     |
     v
다른 task 실행
```

그림:

```text
Before

Ready List
+----------------+
| Task A         |
+----------------+

Delayed List
empty


After vTaskDelay(100)

Ready List
empty

Delayed List
+----------------+
| Task A         |
| wake tick=100  |
+----------------+
```

---

## 19. 예시: queue receive with timeout

이건 조금 더 복잡합니다.

```c
xQueueReceive(queue, &data, 100);
```

Queue가 비어 있으면 Task A는 기다립니다.

```text
Task A
    |
    | queue empty
    v

xStateListItem
    -> delayed list
       timeout 관리

xEventListItem
    -> queue receive wait list
       queue event 관리
```

그림:

```text
                   +------------------+
                   |      TCB A       |
                   +----+--------+----+
                        |        |
                        |        |
                        v        v

             +---------------+   +--------------------------+
             | Delayed List  |   | Queue Receive Wait List  |
             | timeout=100   |   | wait for data            |
             +---------------+   +--------------------------+
```

즉 이 task는 "blocked" 상태지만, 내부적으로는 두 list에 걸려 있습니다.

---

## 20. task가 깨어날 때

어떤 이유로든 task가 다시 실행 가능해지면 ready list로 돌아갑니다.

```text
event 발생 또는 timeout 발생
        |
        v
관련 list item 제거
        |
        v
ready list에 xStateListItem 삽입
```

그림:

```text
Before wake

Delayed/Event Wait Lists
+----------------+
| Task A         |
+----------------+


Wake condition happens


After wake

Ready List
+----------------+
| Task A         |
+----------------+
```

이제 Task A는 scheduler가 고를 수 있습니다.

---

## 21. 한 장으로 보는 task state 변화

```text
                         +----------------+
                         |   Ready List   |
                         | 실행 가능 task |
                         +--------+-------+
                                  |
              vTaskDelay()       | event wait
                                  v
                         +----------------+
                         | Delayed List   |
                         | 시간 대기 task |
                         +--------+-------+
                                  |
                                  | wake tick 도달
                                  v
                         +----------------+
                         |   Ready List   |
                         +----------------+


Queue/Semaphore wait가 있으면 추가로:

                         +----------------------+
                         | Event Wait List      |
                         | queue/semaphore 대기 |
                         +----------------------+
```

좀 더 구체적으로:

```text
Ready
  |
  | vTaskDelay()
  v
Delayed
  |
  | timeout
  v
Ready


Ready
  |
  | queue empty + wait
  v
Delayed + Queue Wait
  |
  | data arrives or timeout
  v
Ready
```

---

## 22. 최종 요약

```text
FreeRTOS task state
    = 하나의 master enum field로만 표현되는 것이 아님

xStateListItem
    = task의 scheduler 상태를 표현
    = ready list, delayed list, suspended list 등에 들어감

xEventListItem
    = task가 기다리는 event object를 표현
    = queue, semaphore, mutex, event group wait list 등에 들어감

ready 상태
    = xStateListItem이 ready list에 있음

delayed 상태
    = xStateListItem이 delayed list에 있음

suspended 상태
    = xStateListItem이 suspended list에 있음

event wait 상태
    = xEventListItem이 queue/semaphore/event list에 있음

task가 깨어남
    = wait list에서 제거되고 ready list로 이동
```

---

## 23. 가장 중요한 그림

```text
                       +------------------+
                       |      TCB_t       |
                       |------------------|
                       | xStateListItem   |
                       | xEventListItem   |
                       +----+--------+----+
                            |        |
                            |        |
                            v        v

        +---------------------+      +--------------------------+
        | Scheduler State     |      | Event Wait State         |
        |---------------------|      |--------------------------|
        | Ready List          |      | Queue Wait List          |
        | Delayed List        |      | Semaphore Wait List      |
        | Suspended List      |      | Mutex Wait List          |
        +---------------------+      +--------------------------+
```

한 문장으로 정리하면:

```text
FreeRTOS에서 task 상태는
"state 필드 값"이라기보다
"TCB 안의 list item이 어느 list에 들어 있는가"로 표현된다.
```

그래서 scheduler 코드를 읽을 때는 이렇게 보면 됩니다.

```text
이 task의 상태가 무엇인가?
    ↓
이 task의 list item이 어느 list에 들어 있는가?
```
