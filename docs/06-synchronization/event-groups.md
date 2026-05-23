# Event groups

이번 주제는 Event Group입니다.

Queue, semaphore, mutex가 데이터, token, ownership을 기다렸다면, Event Group은
bit 조건을 기다립니다.

핵심은 이것입니다.

```text
Event Group
    = 여러 개의 event 상태를 bit로 저장해두고,
      task가 특정 bit 조건이 만족될 때까지 기다리게 하는 동기화 object
```

이번 장에서 보는 source file은 다음입니다.

- `FreeRTOS-Kernel/event_groups.c`
- `FreeRTOS-Kernel/include/event_groups.h`
- `FreeRTOS-Kernel/tasks.c`

## Event Group은 bit를 기다린다

Event Group은 내부에 bit들을 가지고 있습니다.

```text
Event Group bits

+---+---+---+---+---+---+---+---+
| 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
+---+---+---+---+---+---+---+---+
```

각 bit는 어떤 event가 발생했는지를 나타낼 수 있습니다.

예를 들어:

```text
bit 0 = Wi-Fi 연결 완료
bit 1 = 센서 데이터 준비 완료
bit 2 = 버튼 눌림
bit 3 = 저장 장치 준비 완료
```

그림으로 보면:

```text
Event Group

+------------------------------------------------+
| bits                                           |
|------------------------------------------------|
| bit 0: Wi-Fi connected                         |
| bit 1: sensor ready                            |
| bit 2: button pressed                          |
| bit 3: storage ready                           |
+------------------------------------------------+
```

## Queue와 뭐가 다를까?

Queue는 데이터를 넣고 뺍니다.

```text
Queue

+------+------+------+
| data | data |      |
+------+------+------+
```

Semaphore는 token을 기다립니다.

```text
Semaphore

+----------------+
| token exists?  |
+----------------+
```

Mutex는 owner를 봅니다.

```text
Mutex

+----------------+
| owner = Task A |
+----------------+
```

Event Group은 bit 상태를 봅니다.

```text
Event Group

+----------------+
| bits = 0101    |
+----------------+
```

즉 Event Group의 질문은 이것입니다.

```text
내가 기다리는 bit 조건이 만족됐는가?
```

## Event Group의 기본 구조

Event Group을 쉽게 보면 이렇게 생겼습니다.

```text
+------------------------------------------------+
|                  Event Group                   |
|------------------------------------------------|
|                                                |
|  Event Bits                                    |
|                                                |
|  +---+---+---+---+---+---+---+---+             |
|  | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |             |
|  +---+---+---+---+---+---+---+---+             |
|                                                |
|------------------------------------------------|
|                                                |
|  Wait List                                     |
|                                                |
|  bit 조건이 만족될 때까지 기다리는 task들       |
|                                                |
|  +----------------+     +----------------+     |
|  | Task A item    | --> | Task B item    |     |
|  | waiting bits   |     | waiting bits   |     |
|  +----------------+     +----------------+     |
|                                                |
+------------------------------------------------+
```

즉:

```text
Event Group
 ├─ 현재 bit 상태
 └─ bit 조건을 기다리는 task list
```

## task가 bit를 기다리는 예시

Task A가 Wi-Fi 연결 완료를 기다린다고 합시다.

```text
bit 0 = Wi-Fi connected
```

현재 Event Group 상태는 이렇습니다.

```text
bits = 0000

bit 0이 아직 0
```

Task A는 이렇게 기다립니다.

```text
Task A:
    "bit 0이 1이 될 때까지 기다릴게."
```

그림:

```text
Before wait

Event Group bits

+---+---+---+---+
| 3 | 2 | 1 | 0 |
+---+---+---+---+
| 0 | 0 | 0 | 0 |
+---+---+---+---+

Task A calls wait for bit 0
```

조건이 아직 만족되지 않았습니다.

```text
bit 0 == 0
    |
    v
condition not satisfied
```

그래서 Task A는 event group wait list에 들어갑니다.

```text
Event Group Wait List

+----------------+
| Task A         |
| waits bit 0    |
+----------------+
```

## bit가 set되면 task가 깨어난다

나중에 다른 task나 ISR이 bit 0을 set합니다.

```text
set bit 0
```

Event Group 상태가 바뀝니다.

```text
Before

bits = 0000


After set bit 0

bits = 0001
```

이제 Task A의 조건이 만족됩니다.

```text
Task A waits bit 0
bits = 0001
    |
    v
condition satisfied
```

그러면 Task A는 wait list에서 빠져 ready list로 이동합니다.

```text
Event Group Wait List
    |
    | bit condition satisfied
    v
Ready List
```

그림:

```text
Before bit set

Event Group bits
+---+---+---+---+
| 0 | 0 | 0 | 0 |
+---+---+---+---+

Wait List
+----------------+
| Task A         |
| waits bit 0    |
+----------------+


set bit 0


After

Event Group bits
+---+---+---+---+
| 0 | 0 | 0 | 1 |
+---+---+---+---+

Wait List
empty

Ready List
+----------------+
| Task A         |
+----------------+
```

## ANY bit 조건

Event Group에서 task는 여러 bit 중 하나라도 set되면 깨어나게 할 수 있습니다.

예를 들어 Task A가 이렇게 기다린다고 합시다.

```text
bit 0 = Wi-Fi connected
bit 1 = Ethernet connected
```

Task A의 조건:

```text
bit 0 또는 bit 1 중 하나라도 set되면 깨어남
```

그림:

```text
Task A waits for ANY of:

+----------------------+
| bit 0 Wi-Fi          |
| bit 1 Ethernet       |
+----------------------+
```

현재 bits:

```text
bits = 0000
```

아직 조건 불만족입니다.

```text
bit 0 = 0
bit 1 = 0
    |
    v
Task A waits
```

나중에 bit 1이 set됩니다.

```text
bits = 0010
```

그러면 Task A는 깨어납니다.

```text
bit 1이 set됨
    |
    v
ANY 조건 만족
    |
    v
Task A ready
```

그림:

```text
ANY condition

Wait bits:
bit 0 or bit 1

Current bits = 0000
    |
    v
not satisfied


Set bit 1

Current bits = 0010
    |
    v
satisfied
```

## ALL bits 조건

반대로 task가 여러 bit가 모두 set될 때까지 기다릴 수도 있습니다.

예를 들어 Task B가 시스템 시작 조건을 기다린다고 합시다.

```text
bit 0 = Wi-Fi ready
bit 1 = Sensor ready
bit 2 = Storage ready
```

Task B의 조건:

```text
bit 0, bit 1, bit 2가 모두 set되어야 깨어남
```

그림:

```text
Task B waits for ALL of:

+----------------------+
| bit 0 Wi-Fi ready    |
| bit 1 Sensor ready   |
| bit 2 Storage ready  |
+----------------------+
```

현재 bits:

```text
bits = 0001

bit 0만 set
```

아직 조건 불만족입니다.

```text
bit 0 = 1
bit 1 = 0
bit 2 = 0

ALL 조건 불만족
```

나중에 bit 1이 set됩니다.

```text
bits = 0011

bit 0, bit 1 set
bit 2 아직 0
```

아직도 불만족입니다.

나중에 bit 2가 set됩니다.

```text
bits = 0111
```

이제 조건 만족입니다.

```text
bit 0 = 1
bit 1 = 1
bit 2 = 1

ALL 조건 만족
Task B ready
```

그림:

```text
ALL condition

Need:
bit 0, bit 1, bit 2

bits = 0001
    -> not enough

bits = 0011
    -> still not enough

bits = 0111
    -> satisfied
```

## Queue와 달리 여러 task를 한 번에 깨울 수 있다

Queue는 보통 item 하나가 들어오면 receiver 하나가 깨어나는 식으로 생각하기
쉽습니다.

```text
Queue send
    |
    v
waiting receiver 하나 wake
```

하지만 Event Group은 bit 상태를 보고 조건을 만족하는 task들을 깨웁니다.

하나의 bit update가 여러 task의 조건을 동시에 만족시킬 수 있습니다.

예:

```text
Task A waits for bit 0
Task B waits for bit 0 or bit 1
Task C waits for bit 0 and bit 2
```

현재:

```text
bits = 0000
```

bit 0을 set합니다.

```text
bits = 0001
```

그러면:

```text
Task A
    bit 0 필요
    -> 만족

Task B
    bit 0 또는 bit 1 필요
    -> 만족

Task C
    bit 0과 bit 2 필요
    -> 아직 불만족
```

그림:

```text
Before

bits = 0000

Wait List
+-------------------------+
| Task A waits bit 0      |
+-------------------------+
| Task B waits bit 0 or 1 |
+-------------------------+
| Task C waits bit 0 and 2|
+-------------------------+


set bit 0


After

bits = 0001

Ready List
+-------------------------+
| Task A                  |
+-------------------------+
| Task B                  |
+-------------------------+

Still waiting
+-------------------------+
| Task C waits bit 2 too  |
+-------------------------+
```

즉:

```text
Event Group은 한 번의 bit 변화로 여러 task를 깨울 수 있다.
```

## Event Group wait도 결국 list movement다

앞에서 계속 봤던 FreeRTOS 문법이 또 나옵니다.

```text
조건이 만족되지 않음
    |
    v
current task block
    |
    v
event group wait list에 들어감
```

조건이 만족되면:

```text
event bits set
    |
    v
wait list 검사
    |
    v
조건이 맞는 task를 ready list로 이동
```

그림:

```text
Ready List
    |
    | wait for bits, condition false
    v
Event Group Wait List
    |
    | bits changed, condition true
    v
Ready List
```

즉 Event Group도 queue/semaphore/mutex와 같은 scheduler 언어를 씁니다.

```text
object-specific condition
    -> task waits
    -> condition changes
    -> task becomes ready
```

## Queue, Semaphore, Mutex, Event Group 비교

```text
+----------------+-----------------------------+
| Object         | 기다리는 조건               |
+----------------+-----------------------------+
| Queue          | data가 있나? 공간이 있나?   |
| Semaphore      | token이 있나?               |
| Mutex          | lock owner가 풀었나?        |
| Event Group    | 원하는 bit 조건이 맞나?     |
+----------------+-----------------------------+
```

모두 공통 패턴은 같습니다.

```text
조건 불만족
    -> task block

조건 만족
    -> task ready
```

그림:

```text
Queue
    data 없음
        -> wait
    data 들어옴
        -> ready

Semaphore
    token 없음
        -> wait
    token 생김
        -> ready

Mutex
    이미 owner 있음
        -> wait
    owner가 release
        -> ready

Event Group
    bit 조건 불만족
        -> wait
    bit 조건 만족
        -> ready
```

## Event Group 전체 구조 그림

```text
+--------------------------------------------------------------+
|                         Event Group                          |
|--------------------------------------------------------------|
|                                                              |
|  Event Bits                                                  |
|                                                              |
|      bit 0 = Wi-Fi ready                                     |
|      bit 1 = Sensor ready                                    |
|      bit 2 = Button pressed                                  |
|      bit 3 = Storage ready                                   |
|                                                              |
|      Current bits:                                           |
|                                                              |
|      +---+---+---+---+                                       |
|      | 3 | 2 | 1 | 0 |                                       |
|      +---+---+---+---+                                       |
|      | 0 | 1 | 0 | 1 |                                       |
|      +---+---+---+---+                                       |
|                                                              |
|--------------------------------------------------------------|
|                                                              |
|  Wait List                                                   |
|                                                              |
|      +-------------------------------+                       |
|      | Task A waits for bit 0        |                       |
|      +-------------------------------+                       |
|                                                              |
|      +-------------------------------+                       |
|      | Task B waits for bit 1 or 2   |                       |
|      +-------------------------------+                       |
|                                                              |
|      +-------------------------------+                       |
|      | Task C waits for bit 0 and 3  |                       |
|      +-------------------------------+                       |
|                                                              |
+--------------------------------------------------------------+
```

현재 bits가 `0101`이라고 보면:

```text
bit 0 = 1
bit 1 = 0
bit 2 = 1
bit 3 = 0
```

판단:

```text
Task A waits bit 0
    -> 만족

Task B waits bit 1 or 2
    -> bit 2가 있으므로 만족

Task C waits bit 0 and 3
    -> bit 3이 없으므로 불만족
```

그래서 Task A와 Task B는 ready로 갈 수 있고, Task C는 계속 기다립니다.

## Event Group은 FIFO buffer가 아니다

Queue는 순서대로 데이터가 들어가고 나가는 구조입니다.

```text
Queue

A -> B -> C
```

Event Group은 그런 구조가 아닙니다.

Event Group은 현재 bit 상태를 봅니다.

```text
Event Group

bits = 0101
```

중요한 질문도 다릅니다.

```text
Queue:
    어떤 data를 꺼낼까?

Event Group:
    어떤 bit 조건이 만족됐나?
```

Queue에서는 item 하나가 소비될 수 있습니다.

Event Group에서는 bit 상태가 여러 task에게 동시에 의미를 줄 수 있습니다.

```text
bit 0 set
    -> Task A도 깨어남
    -> Task B도 깨어남
    -> Task C는 조건에 따라 계속 기다림
```

## 예시: 시스템 시작 대기

임베디드 시스템에서 여러 초기화가 끝난 뒤 main task를 시작하고 싶다고 합시다.

```text
bit 0 = network ready
bit 1 = sensor ready
bit 2 = storage ready
```

MainTask는 모두 준비될 때까지 기다립니다.

```text
MainTask waits for ALL:
    bit 0, bit 1, bit 2
```

초기 상태:

```text
bits = 0000
```

NetworkTask가 준비됩니다.

```text
set bit 0

bits = 0001
```

아직 MainTask는 기다립니다.

SensorTask가 준비됩니다.

```text
set bit 1

bits = 0011
```

아직 bit 2가 없으므로 기다립니다.

StorageTask가 준비됩니다.

```text
set bit 2

bits = 0111
```

이제 MainTask가 깨어납니다.

```text
MainTask ready
```

그림:

```text
MainTask waits for ALL bits 0,1,2

bits = 0000
    -> wait

Network ready
bits = 0001
    -> wait

Sensor ready
bits = 0011
    -> wait

Storage ready
bits = 0111
    -> ready
```

## 예시: 여러 이벤트 중 하나 기다리기

이번에는 UI task가 여러 입력 중 하나라도 오면 깨어나야 한다고 합시다.

```text
bit 0 = button pressed
bit 1 = touch input
bit 2 = UART command
```

UITask는 하나라도 오면 깨어나면 됩니다.

```text
UITask waits for ANY:
    bit 0, bit 1, bit 2
```

초기 상태:

```text
bits = 0000
```

UART command가 들어옵니다.

```text
set bit 2

bits = 0100
```

ANY 조건 만족입니다.

```text
UITask ready
```

그림:

```text
UITask waits for ANY bit 0,1,2

bits = 0000
    -> wait

UART command
bits = 0100
    -> ready
```

## timeout도 붙을 수 있다

Event Group wait도 timeout이 있을 수 있습니다.

예를 들어:

```text
Task waits for bit 0, max 100 ticks
```

그러면 task는 두 가지 이유로 깨어날 수 있습니다.

```text
1. bit 0이 set됨
2. 100 tick timeout이 끝남
```

이건 queue wait와 비슷합니다.

```text
xStateListItem
    -> delayed list
       "언제 timeout인가?"

xEventListItem
    -> event group wait list
       "어떤 bit 조건을 기다리는가?"
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
             | Delayed List  |   | Event Group Wait List    |
             | timeout=100   |   | waits for bit condition  |
             +---------------+   +--------------------------+
```

## Event Group을 읽을 때 볼 것

Event Group 코드를 읽을 때는 이 질문들을 보면 됩니다.

```text
1. 현재 event bits는 무엇인가?
2. task가 기다리는 bit mask는 무엇인가?
3. ANY 조건인가, ALL 조건인가?
4. 조건이 아직 false라면 task가 어느 wait list에 들어가는가?
5. bit가 set되었을 때 어떤 task들이 ready list로 이동하는가?
```

핵심은 늘 같습니다.

```text
bit 조건 검사
    |
    +--> 만족하면 바로 return 또는 ready
    |
    +--> 불만족이면 wait list로 이동
```

## Event Group 동작 전체 흐름

Wait path:

```text
xEventGroupWaitBits()
    |
    v
현재 bits 확인
    |
    v
조건 만족?
    |
    +--> Yes
    |       |
    |       v
    |   바로 return
    |
    +--> No
            |
            v
        기다릴 수 있는가?
            |
            +--> No
            |       |
            |       v
            |   timeout 없이 return
            |
            +--> Yes
                    |
                    v
              current task를 event group wait list에 넣음
                    |
                    v
              scheduler가 다른 task 선택
```

Set bits path:

```text
xEventGroupSetBits()
    |
    v
event bits 변경
    |
    v
wait list 확인
    |
    v
조건 만족 task 찾기
    |
    v
그 task들을 ready list로 이동
    |
    v
필요하면 context switch
```

## 그림으로 전체 정리

```text
Task A waits for bits
        |
        v
+-----------------------------+
| Event Group bits 확인       |
+-------------+---------------+
              |
       +------+------+
       |             |
   condition true    condition false
       |             |
       v             v
   바로 진행     Event Group Wait List
                     |
                     v
             scheduler runs another task


나중에 bits set

+-----------------------------+
| Event Group bits 변경       |
+-------------+---------------+
              |
              v
+-----------------------------+
| Wait List 검사              |
+-------------+---------------+
              |
              v
+-----------------------------+
| 조건 만족 task를 Ready로 이동|
+-----------------------------+
```

## 가장 중요한 그림

```text
                   +----------------------+
                   |     Event Group      |
                   +----------------------+
                              |
            +-----------------+-----------------+
            |                                   |
            v                                   v

+-------------------------+        +-----------------------------+
| Event Bits              |        | Event Group Wait List       |
|-------------------------|        |-----------------------------|
| bit0: Wi-Fi ready       |        | Task A waits bit0           |
| bit1: Sensor ready      |        | Task B waits bit1 OR bit2   |
| bit2: Button pressed    |        | Task C waits bit0 AND bit3  |
+-------------------------+        +-----------------------------+

            bits set
               |
               v
        조건 만족 task들
               |
               v
          Ready List
```

## 최종 요약

```text
Event Group
    = bit 상태를 이용하는 동기화 object

Event bits
    = 여러 event 상태를 bit로 표현

wait for bits
    = 특정 bit 조건이 만족될 때까지 task가 기다림

ANY condition
    = 기다리는 bit 중 하나라도 set되면 만족

ALL condition
    = 기다리는 bit가 모두 set되어야 만족

condition false
    = task가 event group wait list에 들어감

bits set
    = 조건이 만족된 task들이 ready list로 이동

Queue와 다른 점
    = FIFO buffer가 아님
    = data item을 주고받지 않음
    = 하나의 bit update가 여러 task를 깨울 수 있음
```

한 문장으로 정리하면:

```text
FreeRTOS Event Group은
queue처럼 데이터를 기다리는 것이 아니라,
여러 event를 bit로 표현하고
task가 원하는 bit 조건이 만족될 때 ready 상태로 돌아오게 하는 동기화 object다.
```
