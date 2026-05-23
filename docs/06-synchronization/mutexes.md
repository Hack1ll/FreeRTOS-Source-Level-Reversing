# Mutexes

이번 주제는 Mutex입니다.

Mutex는 semaphore와 비슷해 보이지만, 중요한 차이가 하나 있습니다.

```text
Mutex에는 owner가 있다.
```

즉, FreeRTOS는 mutex에 대해 이렇게 기억합니다.

```text
이 mutex를 지금 누가 가지고 있는가?
```

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/queue.c`
- `FreeRTOS-Kernel/include/semphr.h`
- `FreeRTOS-Kernel/tasks.c`

## Semaphore와 Mutex의 첫 차이

Semaphore는 보통 token이 있는가가 중요합니다.

```text
Semaphore

+----------------+
| token 있음     |
+----------------+
```

누가 token을 줬는지, 누가 이전에 가지고 있었는지는 핵심이 아닙니다.

```text
Task A가 give
Task B가 take

가능
```

하지만 mutex는 다릅니다.

Mutex는 lock입니다.

```text
Mutex

+----------------+
| locked         |
| owner = Task A |
+----------------+
```

즉 mutex는 반드시 이런 질문을 합니다.

```text
누가 이 lock을 가지고 있는가?
```

## Mutex를 열쇠로 생각하기

공유 자원에 들어가기 위한 열쇠가 하나 있다고 생각해봅시다.

```text
+----------------+
| Resource Key   |
+----------------+
```

Task A가 열쇠를 가져가면:

```text
Mutex

+----------------+
| locked         |
| owner = Task A |
+----------------+
```

Task B가 같은 자원을 쓰려고 하면:

```text
Task B
  |
  | mutex take
  v
이미 Task A가 가지고 있음
  |
  v
Task B는 기다림
```

그림:

```text
+------------------------+
|        Mutex           |
|------------------------|
| state: locked          |
| owner: Task A          |
|                        |
| waiting tasks          |
| +----------------+     |
| | Task B         |     |
| +----------------+     |
+------------------------+
```

## Mutex take 흐름

Task A가 mutex를 가지고 있지 않은 상태에서 take하면 성공합니다.

```text
Before

Mutex
+----------------+
| unlocked       |
| owner = none   |
+----------------+


Task A takes mutex


After

Mutex
+----------------+
| locked         |
| owner = Task A |
+----------------+
```

즉:

```text
xSemaphoreTake(mutex)
    |
    v
mutex가 비어 있음
    |
    v
현재 task가 owner가 됨
```

## 이미 owner가 있으면 block된다

이번에는 Task A가 이미 mutex를 가지고 있습니다.

```text
Mutex
+----------------+
| locked         |
| owner = Task A |
+----------------+
```

Task B가 mutex를 take하려고 합니다.

```text
Task B
  |
  | take mutex
  v
mutex already owned by Task A
  |
  v
Task B blocked
```

그림:

```text
Before

Running
+---------+
| Task B  |
+---------+

Mutex
+----------------+
| owner = Task A |
+----------------+

Mutex wait list
empty


After Task B tries to take

Mutex
+----------------+
| owner = Task A |
+----------------+

Mutex wait list
+----------------+
| Task B         |
+----------------+

CPU는 다른 ready task 실행
```

즉 mutex도 semaphore처럼 wait list를 씁니다.

```text
Ready List
    |
    | take mutex, already owned
    v
Mutex Wait List
```

## Mutex give 흐름

Mutex owner인 Task A가 일을 끝내고 mutex를 release합니다.

```text
Task A
  |
  | give mutex
  v
mutex ownership release
```

기다리는 task가 없으면 mutex는 unlocked 상태가 됩니다.

```text
Before

Mutex
+----------------+
| locked         |
| owner = Task A |
+----------------+


Task A gives mutex


After

Mutex
+----------------+
| unlocked       |
| owner = none   |
+----------------+
```

기다리는 task가 있으면 그 task를 깨울 수 있습니다.

```text
Before

Mutex
+----------------+
| owner = Task A |
+----------------+

Wait list
+----------------+
| Task B         |
+----------------+


Task A gives mutex


After

Wait list
empty

Ready list
+----------------+
| Task B         |
+----------------+
```

정리하면:

```text
give mutex
    |
    v
ownership 해제
    |
    v
기다리는 task가 있으면 깨움
```

## Mutex가 semaphore보다 특별한 이유

Semaphore도 task를 재우고 깨웁니다.

```text
take unavailable semaphore
    -> task block

give semaphore
    -> waiting task wake
```

Mutex도 비슷합니다.

```text
take owned mutex
    -> task block

give mutex
    -> waiting task wake
```

하지만 mutex에는 추가로 이것이 있습니다.

```text
owner
```

왜 owner가 중요할까요?

바로 priority inheritance 때문입니다.

## Priority inversion 문제

먼저 상황을 봅시다.

```text
Task L: 낮은 priority
Task H: 높은 priority
Task M: 중간 priority
```

Task L이 mutex를 가지고 있습니다.

```text
Mutex
+----------------+
| owner = Task L |
+----------------+
```

이제 Task H가 같은 mutex를 원합니다.

```text
Task H
  |
  | take mutex
  v
이미 Task L이 가지고 있음
  |
  v
Task H blocked
```

문제는 Task H가 높은 priority인데도, 낮은 priority Task L 때문에 기다린다는
것입니다.

```text
높은 priority Task H
    ↓
낮은 priority Task L이 mutex를 놓을 때까지 기다림
```

여기에 Task M이 있으면 더 문제가 커집니다.

```text
Task M은 priority가 중간이고,
Task L보다 priority가 높음.
```

그러면 scheduler는 Task M을 자꾸 실행할 수 있습니다.

```text
Task L이 실행되어야 mutex를 release할 수 있는데,
Task M이 Task L보다 priority가 높아서 Task L을 밀어냄.
```

그 결과:

```text
Task H는 Task L을 기다림
Task L은 Task M 때문에 실행을 못 함
Task M은 mutex와 상관없는데 계속 실행됨
```

이게 priority inversion입니다.

## Priority inversion 그림

```text
Priority

High    Task H  ---- waits for mutex ----+
                                         |
Medium  Task M  ---- keeps running       |
                                         |
Low     Task L  ---- owns mutex <--------+
```

문제:

```text
Task H는 가장 중요하지만 blocked됨.
Task L이 mutex를 release해야 하는데 low priority라 잘 실행되지 못함.
Task M이 중간에서 CPU를 차지함.
```

그림으로 더 보면:

```text
[1] Task L owns mutex

Mutex
+----------------+
| owner = Task L |
+----------------+


[2] Task H tries to take mutex

Task H
+----------------+
| blocked        |
| waiting mutex  |
+----------------+


[3] Task M runs

Task M
+----------------+
| does unrelated |
| work           |
+----------------+


결과:
Task H가 Task M보다 priority가 높은데도,
Task M 때문에 Task H가 간접적으로 밀림.
```

## Priority inheritance란?

FreeRTOS mutex는 이 문제를 줄이기 위해 priority inheritance를 사용합니다.

의미는 이것입니다.

```text
높은 priority task가 mutex를 기다리고 있으면,
그 mutex의 owner가 임시로 높은 priority를 물려받는다.
```

상황:

```text
Task L priority = 1
Task H priority = 5

Task L owns mutex
Task H waits for mutex
```

그러면 FreeRTOS는 Task L의 priority를 임시로 올릴 수 있습니다.

```text
Task L priority 1
    |
    | inherits from Task H
    v
Task L priority 5
```

그림:

```text
Before inheritance

Task H priority 5  -> waiting
Task L priority 1  -> owns mutex


After inheritance

Task H priority 5  -> waiting
Task L priority 5  -> owns mutex temporarily
```

이렇게 하면 Task L이 빨리 실행되어 mutex를 release할 가능성이 커집니다.

```text
Task L 실행
    |
    v
mutex release
    |
    v
Task H wake
```

## Priority inheritance 흐름

```text
low-priority task owns mutex
        |
        v
high-priority task tries to take mutex
        |
        v
high-priority task blocks
        |
        v
kernel checks owner
        |
        v
owner priority temporarily raised
        |
        v
owner runs sooner
        |
        v
owner gives mutex
        |
        v
owner priority restored
        |
        v
high-priority task wakes
```

그림:

```text
+-----------------------------+
| Task L owns mutex           |
| priority 1                  |
+-------------+---------------+
              |
              v
+-----------------------------+
| Task H wants mutex          |
| priority 5                  |
+-------------+---------------+
              |
              v
+-----------------------------+
| Task H blocks               |
+-------------+---------------+
              |
              v
+-----------------------------+
| Task L inherits priority 5  |
+-------------+---------------+
              |
              v
+-----------------------------+
| Task L runs and releases    |
+-------------+---------------+
              |
              v
+-----------------------------+
| Task L disinherits priority |
| back to 1                   |
+-------------+---------------+
              |
              v
+-----------------------------+
| Task H becomes ready        |
+-----------------------------+
```

## Disinheritance: priority를 되돌리기

Priority inheritance는 영구적인 priority 변경이 아닙니다.

```text
임시 상승
```

입니다.

Task L이 mutex를 release하면 원래 priority로 돌아가야 합니다.

```text
Task L priority 5
    |
    | give mutex
    v
Task L priority 1
```

이걸 disinherit라고 볼 수 있습니다.

```text
inherit
    = priority를 임시로 물려받음

disinherit
    = 원래 priority로 되돌림
```

그림:

```text
Before give

Task L
+----------------+
| priority = 5   |
| inherited      |
+----------------+


Task L gives mutex


After give

Task L
+----------------+
| priority = 1   |
| original       |
+----------------+
```

## Mutex take/give 전체 흐름

Take owned mutex:

```text
take mutex
    |
    v
mutex owner가 있는가?
    |
    +--> 없음
    |       |
    |       v
    |   현재 task가 owner 됨
    |
    +--> 있음
            |
            v
        현재 task block
            |
            v
        owner priority inheritance 가능
```

그림:

```text
+----------------------+
| xSemaphoreTake(mutex)|
+----------+-----------+
           |
           v
+----------------------+
| mutex unlocked?      |
+----------+-----------+
           |
     +-----+-----+
     |           |
    Yes          No
     |           |
     v           v
current task   block current task
becomes owner       |
                    v
              maybe raise owner priority
```

Give mutex:

```text
give mutex
    |
    v
현재 task가 owner인가?
    |
    v
ownership release
    |
    v
priority disinherit 가능
    |
    v
waiting task가 있으면 깨움
```

그림:

```text
+----------------------+
| xSemaphoreGive(mutex)|
+----------+-----------+
           |
           v
+----------------------+
| release ownership    |
+----------+-----------+
           |
           v
+----------------------+
| maybe disinherit     |
| priority             |
+----------+-----------+
           |
           v
+----------------------+
| waiting task exists? |
+----------+-----------+
           |
     +-----+-----+
     |           |
    Yes          No
     |           |
     v           v
wake waiter    mutex unlocked
```

## Mutex도 Queue 근처에 산다

FreeRTOS에서 mutex 구현은 queue 코드 주변에 있습니다.

왜냐하면 mutex도 queue/semaphore와 같은 wait list 메커니즘을 쓰기 때문입니다.

```text
mutex unavailable
    -> current task wait list로 이동

mutex released
    -> waiting task ready list로 이동
```

하지만 mutex는 semaphore보다 task 관리에 더 깊게 들어갑니다.

이유:

```text
priority inheritance 때문에 task priority를 바꿀 수 있음
```

그래서 mutex logic은 `queue.c`에 있지만, priority 변경은 `tasks.c`의 scheduler
상태와 연결됩니다.

```text
queue.c
    = mutex take/give logic

tasks.c
    = task priority 관리
    = priority inheritance/disinheritance
```

그림:

```text
+-----------------------------+
| queue.c                     |
|-----------------------------|
| mutex wait list 관리         |
| owner 확인                  |
| take/give 처리              |
+-------------+---------------+
              |
              v
+-----------------------------+
| tasks.c                     |
|-----------------------------|
| task priority 변경           |
| ready list 재배치            |
| priority inheritance         |
+-----------------------------+
```

즉 synchronization primitive는 단순 utility가 아닙니다.

```text
mutex는 scheduler 상태를 바꿀 수 있다.
```

## Mutex 안의 구조를 그림으로 보기

```text
+------------------------------------------------+
|                    Mutex                       |
|------------------------------------------------|
|                                                |
|  state                                         |
|    locked / unlocked                           |
|                                                |
|  owner                                         |
|    현재 mutex를 가진 TCB                       |
|                                                |
|------------------------------------------------|
|                                                |
|  wait list                                     |
|    mutex를 기다리는 task들                     |
|                                                |
|  +----------------+     +----------------+     |
|  | ListItem_t     | --> | ListItem_t     |     |
|  | pvOwner        |     | pvOwner        |     |
|  +------|---------+     +------|---------+     |
|         |                      |               |
|         v                      v               |
|      +-------+              +-------+          |
|      | TCB B |              | TCB C |          |
|      +-------+              +-------+          |
|                                                |
+------------------------------------------------+
```

그리고 owner도 TCB를 가리킵니다.

```text
Mutex
  |
  v
owner
  |
  v
TCB A
```

## Semaphore와 Mutex 비교

```text
+----------------------+-----------------------------+
| Semaphore            | Mutex                       |
+----------------------+-----------------------------+
| token 중심           | ownership 중심              |
| 누가 가졌는지 덜 중요 | owner가 매우 중요           |
| signal/count 용도    | shared resource 보호 용도   |
| priority inheritance 없음 | priority inheritance 있음 |
| give/take 가능       | lock/unlock 의미            |
+----------------------+-----------------------------+
```

쉽게 말하면:

```text
Semaphore
    = 신호 또는 개수 관리

Mutex
    = 누가 자원을 독점 사용 중인지 관리
```

## 언제 semaphore, 언제 mutex?

Semaphore가 어울리는 경우:

```text
ISR이 task에게 이벤트 발생을 알림

예:
UART 데이터 도착
버튼 눌림
ADC 완료
```

그림:

```text
ISR
  |
  | give semaphore
  v
Task wakes
```

Mutex가 어울리는 경우:

```text
여러 task가 공유 자원 하나를 보호해야 함

예:
공유 I2C 버스
공유 SPI 장치
공유 printf/log buffer
공유 파일 시스템
```

그림:

```text
Task A
  |
  | take mutex
  v
uses shared resource
  |
  | give mutex
  v
Task B can use resource
```

## 전체 예시: 공유 I2C 버스

두 task가 같은 I2C 버스를 사용한다고 해봅시다.

```text
Task Sensor
Task Display
```

I2C 버스는 동시에 하나의 task만 사용해야 합니다.

```text
I2C bus
+----------------+
| shared resource|
+----------------+
```

그래서 mutex를 둡니다.

```text
I2C Mutex
+----------------+
| owner = none   |
+----------------+
```

Task Sensor가 먼저 사용합니다.

```text
Task Sensor takes mutex

I2C Mutex
+----------------------+
| owner = SensorTask   |
+----------------------+
```

Task Display가 사용하려고 하면 기다립니다.

```text
Task Display
    |
    | take mutex
    v
blocked on I2C Mutex
```

SensorTask가 끝나고 give하면:

```text
SensorTask gives mutex
    |
    v
DisplayTask wakes
    |
    v
DisplayTask can use I2C
```

그림:

```text
+-------------------+
| SensorTask        |
| owns I2C mutex    |
+---------+---------+
          |
          | using I2C
          v

+-------------------+
| I2C bus           |
+-------------------+


+-------------------+
| DisplayTask       |
| waiting mutex     |
+-------------------+


SensorTask releases mutex


+-------------------+
| DisplayTask ready |
+-------------------+
```

## Priority inheritance 예시까지 붙이기

이번에는 priority를 넣어봅시다.

```text
SensorTask priority 1
ControlTask priority 5
LogTask priority 3
```

SensorTask가 I2C mutex를 가지고 있습니다.

```text
I2C Mutex owner = SensorTask
```

ControlTask가 I2C를 쓰려고 합니다.

```text
ControlTask priority 5
    |
    | take I2C mutex
    v
blocked because SensorTask owns it
```

그럼 SensorTask가 priority를 임시로 물려받을 수 있습니다.

```text
SensorTask priority 1 -> temporarily 5
```

왜냐하면 SensorTask가 빨리 실행되어 mutex를 놓아야 ControlTask가 진행할 수 있기
때문입니다.

```text
SensorTask runs sooner
    |
    v
releases I2C mutex
    |
    v
ControlTask wakes
    |
    v
SensorTask priority returns to 1
```

그림:

```text
Before

ControlTask prio 5  waits for I2C mutex
LogTask     prio 3  ready
SensorTask  prio 1  owns I2C mutex


Without inheritance

LogTask may run before SensorTask
ControlTask keeps waiting


With inheritance

SensorTask temporarily becomes prio 5
SensorTask runs
SensorTask releases mutex
ControlTask wakes
SensorTask returns to prio 1
```

## Mutex도 결국 list movement + priority change다

지금까지 배운 FreeRTOS 스타일로 다시 정리하면:

```text
mutex take 실패
    =
현재 task를 mutex wait list에 넣음
+
owner priority를 올릴 수 있음
```

```text
mutex give
    =
ownership 해제
+
owner priority를 원래대로 되돌릴 수 있음
+
기다리는 task를 ready list로 옮김
```

그림:

```text
take owned mutex

Ready List
    |
    | mutex owned
    v
Mutex Wait List
    |
    +--> owner priority inheritance 가능


give mutex

Mutex Wait List
    |
    | mutex released
    v
Ready List
    |
    +--> owner priority disinherit 가능
```

## 최종 요약

```text
Mutex
    = ownership이 있는 semaphore-like object

ownership
    = 현재 mutex를 가진 task를 kernel이 기억함

take mutex
    = 비어 있으면 현재 task가 owner가 됨
    = 이미 owner가 있으면 current task가 block됨
    = 높은 priority task가 기다리면 owner priority가 임시 상승 가능

give mutex
    = owner가 mutex를 release
    = priority inheritance를 되돌릴 수 있음
    = 기다리던 task를 ready list로 이동 가능

priority inversion
    = 높은 priority task가 낮은 priority task가 가진 mutex 때문에 기다리는 문제

priority inheritance
    = mutex owner가 기다리는 높은 priority task의 priority를 임시로 물려받는 해결책

중요한 차이
    = semaphore는 token 중심
    = mutex는 owner 중심
```

가장 중요한 그림은 이것입니다.

```text
Low-priority Task owns mutex
        |
        v
High-priority Task tries to take mutex
        |
        v
High-priority Task blocks
        |
        v
Owner temporarily inherits high priority
        |
        v
Owner runs and releases mutex
        |
        v
High-priority Task becomes ready
```

한 문장으로 정리하면:

```text
FreeRTOS mutex는 queue/semaphore 기반의 wait list 구조를 쓰지만,
semaphore와 달리 owner를 추적하고,
priority inheritance를 통해 scheduler priority까지 바꿀 수 있는 동기화 object다.
```
