# Task Control Block

`TCB_t`는 FreeRTOS가 task를 관리하기 위해 붙여두는 학생부, 신분증, 저장 파일처럼
생각하면 됩니다.

핵심은 이것입니다.

```text
FreeRTOS에서 task는 단순히 함수 하나가 아니다.

task function
+ stack
+ priority
+ current execution position
+ ready/blocked state
+ waiting event information

이 모든 것을 scheduler가 다룰 수 있게 묶어둔 object가 TCB_t다.
```

## 우리가 생각하는 task

처음에는 task를 이렇게 생각하기 쉽습니다.

```c
void vSensorTask( void * pvParameters )
{
    while( 1 )
    {
        read_sensor();
        vTaskDelay( 100 );
    }
}
```

그래서 이렇게 생각할 수 있습니다.

```text
Task = function
```

하지만 FreeRTOS 입장에서는 이것만으로 부족합니다. Scheduler는 이런 것을 알아야
합니다.

```text
이 task의 priority는?
이 task는 지금 ready 상태인가?
이 task는 blocked 상태인가?
이 task의 stack은 어디 있는가?
이 task가 다시 실행될 때 CPU register를 어디서 복원해야 하는가?
이 task는 queue를 기다리고 있는가?
```

그래서 FreeRTOS는 task 하나마다 관리용 구조체를 만듭니다. 그게 바로 `TCB_t`입니다.

```text
Task function
   |
   v
+----------------------+
|        TCB_t         |
| task management data |
+----------------------+
```

## TCB_t는 task의 관리 카드다

`TCB_t`는 Task Control Block의 약자입니다. 쉽게 말하면:

```text
TCB_t = FreeRTOS가 task를 관리하기 위해 들고 있는 정보 카드
```

그림으로 보면:

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| pxTopOfStack                   |
| xStateListItem                 |
| xEventListItem                 |
| uxPriority                     |
| pxStack                        |
| pcTaskName                     |
+--------------------------------+
```

처음에는 이 필드들만 잡으면 충분합니다.

```text
pxTopOfStack
    = 현재 task의 stack top 위치

xStateListItem
    = ready / delayed / suspended 같은 상태 list에 들어갈 때 쓰는 node

xEventListItem
    = queue / semaphore 같은 event wait list에 들어갈 때 쓰는 node

uxPriority
    = task priority

pxStack
    = task stack memory 시작 위치

pcTaskName
    = task name
```

실제 코드는 설정에 따라 필드가 훨씬 많지만, 첫 패스에서는 아래 excerpt처럼
읽으면 됩니다.

```c
typedef struct tskTaskControlBlock
{
    volatile StackType_t * pxTopOfStack;
    ListItem_t xStateListItem;
    ListItem_t xEventListItem;
    UBaseType_t uxPriority;
    StackType_t * pxStack;
    char pcTaskName[ configMAX_TASK_NAME_LEN ];
} TCB_t;
```

## TCB_t 전체 그림

Task 하나를 그림으로 보면 이렇게 생각할 수 있습니다.

```text
+------------------------------------------------+
|                    TCB_t                       |
|------------------------------------------------|
|                                                |
|  pcTaskName                                    |
|    "SensorTask"                                |
|                                                |
|  uxPriority                                    |
|    3                                           |
|                                                |
|  pxStack                                       |
|    task stack start address                    |
|                                                |
|  pxTopOfStack                                  |
|    current saved stack top                     |
|                                                |
|  xStateListItem                                |
|    ready / delayed / suspended list node       |
|                                                |
|  xEventListItem                                |
|    queue / semaphore wait list node            |
|                                                |
+------------------------------------------------+
```

더 단순하게 보면:

```text
+-------------------+
|      TCB_t        |
+-------------------+
| task name         |
| priority          |
| stack information |
| state list item   |
| event list item   |
+-------------------+
```

## task function과 TCB_t의 관계

Task function은 실제로 실행되는 코드입니다.

```text
+-------------------------+
| vSensorTask()           |
|                         |
| while (1)               |
|   read_sensor();        |
|   vTaskDelay(100);      |
+-------------------------+
```

하지만 scheduler가 직접 관리하는 것은 함수 포인터 하나가 아니라 `TCB_t`입니다.

```text
+-------------------------+
| task function           |
| vSensorTask()           |
+------------+------------+
             |
             v
+-------------------------+
| TCB_t                   |
| "SensorTask"            |
| priority = 3            |
| stack info              |
| list items              |
+-------------------------+
```

즉:

```text
task function = 실행할 코드
TCB_t         = 그 코드를 task로 관리하기 위한 정보
```

## Stack이 왜 중요할까?

일반 프로그램에서도 함수 호출을 하면 stack을 씁니다.

```c
void foo( void )
{
    int a = 10;
    bar();
}
```

이런 지역 변수, 함수 호출 정보 등이 stack에 쌓입니다. FreeRTOS task도 각각 자기
stack을 가집니다.

```text
Task A stack

+------------------+
| local variables  |
| return address   |
| saved registers  |
| function frames  |
+------------------+
```

Task가 여러 개라면 stack도 여러 개입니다.

```text
+------------------+     +------------------+     +------------------+
| Task A stack     |     | Task B stack     |     | Task C stack     |
+------------------+     +------------------+     +------------------+
```

그래서 TCB는 "내 task의 stack이 어디 있는지"를 기억해야 합니다.

## pxStack과 pxTopOfStack

TCB 안의 stack 관련 필드는 크게 두 개로 보면 됩니다.

```text
pxStack
    = stack memory의 시작 위치

pxTopOfStack
    = 현재 stack top 위치
```

그림으로 보면:

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| pxStack       ----+            |
| pxTopOfStack  ----|----+       |
+-------------------|----|-------+
                    |    |
                    v    v

             Task Stack Memory

             +----------------+
pxStack ---> | stack start    |
             |                |
             |                |
             | saved data     |
             | saved registers|
             |                |
pxTopOfStack -> current top   |
             +----------------+
```

`pxStack`은 이 stack의 시작점이고, `pxTopOfStack`은 지금 이 task를 다시 실행하려면
여기서부터 복원해야 한다는 위치입니다.

## pxTopOfStack이 가장 중요하다

`pxTopOfStack`은 context switch와 직접 연결됩니다.

Context switch는 이런 뜻입니다.

```text
지금 실행 중인 Task A를 멈추고,
Task B를 실행하도록 CPU 상태를 바꾸는 것
```

CPU는 task를 실행할 때 register를 사용합니다.

```text
CPU registers

R0
R1
R2
...
PC
LR
xPSR
```

Task A를 멈추려면 현재 CPU register 상태를 저장해야 합니다.

```text
Task A 실행 중
      |
      v
CPU registers를 Task A stack에 저장
      |
      v
TCB A의 pxTopOfStack에 stack 위치 기록
```

그림으로 보면:

```text
현재 Task A 실행 중

+----------------+
| CPU Registers  |
| R0, R1, R2...  |
+--------+-------+
         |
         | 저장
         v

+-------------------------+
| Task A Stack            |
| saved registers         |
+------------+------------+
             ^
             |
             |
+------------|------------+
| TCB A      |            |
| pxTopOfStack -----------+
+-------------------------+
```

나중에 Task A를 다시 실행할 때는 반대로 합니다.

```text
TCB A의 pxTopOfStack을 본다
      |
      v
Task A stack에서 register 복원
      |
      v
Task A가 멈춘 지점부터 다시 실행
```

## context switch를 그림으로 보기

Task A에서 Task B로 전환된다고 해봅시다.

Step 1. Task A 실행 중:

```text
+-------------+
| CPU         |
| running A   |
+------+------+
       |
       v
+-------------+
| TCB A       |
+-------------+
```

Step 2. Task A의 CPU 상태 저장:

```text
+----------------+
| CPU Registers  |
+--------+-------+
         |
         v
+----------------+
| Task A Stack   |
| saved context  |
+--------+-------+
         ^
         |
+--------|-------+
| TCB A          |
| pxTopOfStack --+
+----------------+
```

Step 3. Scheduler가 다음 task를 고름:

```text
Ready List

+----------+     +----------+     +----------+
| Task A   |     | Task B   |     | Task C   |
+----------+     +----------+     +----------+
                      ^
                      |
               scheduler selects
```

Step 4. `pxCurrentTCB`가 Task B를 가리킴:

```text
Before

pxCurrentTCB
     |
     v
+---------+
| TCB A   |
+---------+

After

pxCurrentTCB
     |
     v
+---------+
| TCB B   |
+---------+
```

Step 5. Task B의 stack에서 CPU 상태 복원:

```text
+----------------+
| TCB B          |
| pxTopOfStack --+----+
+----------------+    |
                      v
              +----------------+
              | Task B Stack   |
              | saved context  |
              +--------+-------+
                       |
                       v
              +----------------+
              | CPU Registers  |
              | restored B     |
              +----------------+
```

이제 CPU는 Task B를 실행합니다.

## pxTopOfStack이 TCB의 첫 번째 필드여야 하는 이유

FreeRTOS Cortex-M port에서는 assembly code가 TCB를 직접 읽습니다. 여기서 중요한
전제가 있습니다.

```text
TCB_t의 맨 앞에 pxTopOfStack이 있어야 한다.
```

왜냐하면 port layer의 assembly가 대략 이런 식으로 생각하기 때문입니다.

```text
TCB 시작 주소를 안다
      |
      v
그 시작 주소 바로 앞부분에 pxTopOfStack이 있다고 믿는다
      |
      v
그 값을 읽어서 stack pointer로 사용한다
```

그림으로 보면:

```text
TCB_t memory layout

+-------------------------+  offset 0
| pxTopOfStack            |  <- port assembly가 바로 여기 있다고 믿음
+-------------------------+
| xStateListItem          |
+-------------------------+
| xEventListItem          |
+-------------------------+
| uxPriority              |
+-------------------------+
| pxStack                 |
+-------------------------+
| pcTaskName              |
+-------------------------+
```

만약 누가 구조체 순서를 바꿔서 이렇게 만들면?

```text
잘못된 예

+-------------------------+  offset 0
| uxPriority              |
+-------------------------+
| pxTopOfStack            |
+-------------------------+
```

Port assembly는 여전히 offset 0을 `pxTopOfStack`이라고 생각합니다. 그러면 실제로는
priority 값을 stack pointer처럼 읽게 됩니다.

```text
assembly:
    "여기가 pxTopOfStack이겠지?"

실제:
    "아닌데, uxPriority인데?"
```

결과는 치명적입니다.

```text
잘못된 stack pointer 사용
    |
    v
잘못된 register 복원
    |
    v
task 실행 깨짐
```

그래서 `pxTopOfStack`은 단순한 필드가 아닙니다.

```text
pxTopOfStack
    = scheduler와 CPU port assembly 사이의 약속
```

## xStateListItem은 task의 큰 상태를 나타낸다

앞에서 list를 배웠다면, 여기서 다시 연결됩니다. TCB 안에는 `xStateListItem`이
있습니다.

```text
+----------------------+
|        TCB_t         |
|----------------------|
| xStateListItem       |
+----------------------+
```

이것은 task가 ready인지, delayed인지, suspended인지 같은 큰 상태를 나타내는 list에
들어갈 때 사용됩니다.

```text
xStateListItem
    -> ready list
    -> delayed list
    -> suspended list
```

그림으로 보면:

```text
+------------------+
| TCB A            |
| xStateListItem --+----+
+------------------+    |
                        v
                 +--------------+
                 | Ready List   |
                 +--------------+
```

또는 delay 중이면:

```text
+------------------+
| TCB A            |
| xStateListItem --+----+
+------------------+    |
                        v
                 +--------------+
                 | Delayed List |
                 +--------------+
```

즉 `xStateListItem`은 task의 현재 큰 상태를 list로 표현하는 데 쓰입니다.

## xStateListItem 상태 이동 예시

Task A가 실행 가능할 때:

```text
Ready List

+----------------+
| Task A state   | ----> TCB A
+----------------+
```

Task A가 `vTaskDelay(100)`을 호출하면:

```text
Task A
  |
  | vTaskDelay(100)
  v
Ready List에서 빠짐
  |
  v
Delayed List로 이동
```

그림으로 보면:

```text
Before

Ready List
+----------------+
| Task A item    | ---> TCB A
+----------------+

Delayed List
empty

After vTaskDelay(100)

Ready List
empty

Delayed List
+----------------+
| Task A item    | ---> TCB A
| wake tick=100  |
+----------------+
```

여기서 사용되는 list item이 `xStateListItem`입니다.

## xEventListItem은 무엇을 기다리는지 나타낸다

TCB에는 또 하나의 list item이 있습니다.

```text
+----------------------+
|        TCB_t         |
|----------------------|
| xStateListItem       |
| xEventListItem       |
+----------------------+
```

`xEventListItem`은 queue, semaphore, mutex 같은 event object를 기다릴 때 사용됩니다.

```text
xEventListItem
    -> queue receive wait list
    -> queue send wait list
    -> semaphore wait list
    -> mutex wait list
```

예를 들어 Task A가 queue receive를 시도했는데 queue가 비어 있다고 합시다.

```text
Task A
  |
  | xQueueReceive()
  v
Queue empty
  |
  v
Queue의 receive wait list에 들어감
```

그림으로 보면:

```text
+------------------+
| TCB A            |
| xEventListItem --+----+
+------------------+    |
                        v
        +--------------------------------+
        | Queue_t                        |
        | xTasksWaitingToReceive         |
        |                                |
        | +----------------+             |
        | | Task A event   | ---> TCB A  |
        | +----------------+             |
        +--------------------------------+
```

여기서 사용되는 list item이 `xEventListItem`입니다.

## 왜 list item이 두 개 필요할까?

처음에는 이렇게 생각할 수 있습니다.

```text
task 상태를 나타내는 list item 하나면 충분하지 않나?
```

하지만 FreeRTOS에서는 task가 두 가지 관점에서 관리될 수 있습니다.

```text
1. scheduler view
   이 task는 ready인가?
   delayed인가?
   suspended인가?

2. event view
   이 task는 어떤 queue를 기다리는가?
   어떤 semaphore를 기다리는가?
```

예를 들어 Task A가 queue를 기다리고 있다고 해봅시다. 이때 Task A는:

```text
큰 상태로는 blocked 상태
구체적으로는 어떤 queue의 receive event를 기다리는 상태
```

입니다. 그래서 두 list item이 필요합니다.

```text
+--------------------------------+
|             TCB A              |
|--------------------------------|
|                                |
| xStateListItem                 |
|   -> delayed / blocked list    |
|                                |
| xEventListItem                 |
|   -> queue receive wait list   |
|                                |
+--------------------------------+
```

한 그림으로 보면:

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
             +---------------+   +--------------------------+
```

즉:

```text
xStateListItem
    = task의 큰 상태를 표현

xEventListItem
    = task가 기다리는 event를 표현
```

## 각 list item의 pvOwner는 자기 TCB를 가리킨다

앞에서 list를 배울 때 `pvOwner`를 봤습니다.

```text
ListItem_t
    pvOwner -> TCB_t
```

TCB 안의 두 list item도 마찬가지입니다.

```text
+--------------------------------+
|             TCB A              |
|--------------------------------|
|                                |
| xStateListItem                 |
|   pvOwner ----------------+    |
|                            |    |
| xEventListItem             |    |
|   pvOwner -------------+   |    |
|                         |   |    |
+-------------------------|---|----+
                          |   |
                          v   v
                       TCB A itself
```

즉:

```text
TCB A의 xStateListItem.pvOwner = TCB A
TCB A의 xEventListItem.pvOwner = TCB A
```

왜 이렇게 할까요? List에는 TCB 전체가 아니라 `ListItem_t`가 들어가기 때문입니다.

```text
Queue wait list에서 ListItem_t 하나를 발견
        |
        v
이게 어느 task의 item이지?
        |
        v
pvOwner를 따라감
        |
        v
TCB A 발견
```

그림으로 보면:

```text
Queue wait list

+----------------+
| ListItem_t     |
| pvOwner -------+----+
+----------------+    |
                      v
                 +---------+
                 | TCB A   |
                 +---------+
```

그래서 `pvOwner`는 list item에서 task로 돌아가는 길입니다.

## TCB_t와 List_t의 관계 전체 그림

```text
+------------------------------------------------+
|                    TCB A                       |
|------------------------------------------------|
| pcTaskName = "SensorTask"                      |
| uxPriority = 3                                 |
| pxStack                                        |
| pxTopOfStack                                   |
|                                                |
| xStateListItem                                 |
|   pvOwner ------------------------------+      |
|                                         |      |
| xEventListItem                          |      |
|   pvOwner --------------------------+   |      |
+-------------------------------------|---|------+
                                      |   |
                                      v   v
                                    TCB A itself
```

그리고 이 list item들이 각각 다른 list에 들어갑니다.

```text
                    +------------------+
                    |      TCB A       |
                    +--------+---------+
                             |
             +---------------+---------------+
             |                               |
             v                               v

+-----------------------+       +-----------------------------+
| xStateListItem        |       | xEventListItem              |
| pvOwner -> TCB A      |       | pvOwner -> TCB A            |
+----------+------------+       +-------------+---------------+
           |                                  |
           v                                  v

+-----------------------+       +-----------------------------+
| Ready / Delayed List  |       | Queue / Semaphore Wait List |
+-----------------------+       +-----------------------------+
```

## uxPriority는 scheduler가 task를 고를 때 쓴다

`uxPriority`는 task의 우선순위입니다.

```text
높은 priority task가 있으면,
FreeRTOS는 보통 그 task를 먼저 실행한다.
```

예를 들어:

```text
Task A priority 1
Task B priority 3
Task C priority 2
```

Ready 상태라면 보통 Task B가 먼저 선택됩니다.

```text
Ready Lists

Priority 3
+----------+
| Task B   |
+----------+

Priority 2
+----------+
| Task C   |
+----------+

Priority 1
+----------+
| Task A   |
+----------+
```

Scheduler는 높은 priority ready list부터 확인합니다.

```text
가장 높은 priority ready list 찾기
        |
        v
그 list에서 다음 task 고르기
        |
        v
pxCurrentTCB 갱신
```

## pcTaskName은 디버깅용으로 유용하다

`pcTaskName`은 task 이름입니다.

```text
pcTaskName = "SensorTask"
```

이 필드는 scheduling 핵심 로직보다는 debugging이나 trace에서 유용합니다.

```text
현재 실행 중인 task가 누구인가?
stack overflow가 발생한 task 이름은?
debugger에서 이 TCB가 어떤 task인가?
```

이런 것을 볼 때 도움이 됩니다.

## pxCurrentTCB란?

이제 가장 중요한 전역 포인터가 나옵니다.

```text
pxCurrentTCB
```

이건 현재 실행 중인 task의 TCB를 가리킵니다.

```text
pxCurrentTCB
     |
     v
+----------------+
| TCB of Task A  |
+----------------+
```

즉:

```text
pxCurrentTCB = 지금 CPU에서 실행 중인 task의 TCB
```

Task B로 context switch되면 `pxCurrentTCB`가 바뀝니다.

```text
Before context switch

pxCurrentTCB
     |
     v
+---------+
| TCB A   |
+---------+

After context switch

pxCurrentTCB
     |
     v
+---------+
| TCB B   |
+---------+
```

## scheduler와 port layer의 역할 분리

FreeRTOS 안에는 크게 두 층이 있습니다.

```text
Common scheduler code
    = 어떤 task를 다음에 실행할지 결정

Port layer
    = 실제 CPU register를 저장/복원
```

그림으로 보면:

```text
+----------------------------------+
| FreeRTOS common scheduler        |
| tasks.c                          |
|----------------------------------|
| 다음 task를 고른다               |
| pxCurrentTCB를 바꾼다            |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| Port layer                       |
| ARM_CM4F/port.c                  |
|----------------------------------|
| pxCurrentTCB->pxTopOfStack 사용  |
| CPU register 저장/복원           |
+----------------------------------+
```

즉 scheduler는 말합니다.

```text
다음에 실행할 task는 이거야.
pxCurrentTCB를 이 TCB로 바꿔둘게.
```

그러면 port layer가 말합니다.

```text
알겠어.
그 TCB 안의 pxTopOfStack을 보고 CPU 상태를 복원할게.
```

## vTaskSwitchContext()와 PendSV의 관계

FreeRTOS에서 context switch 흐름을 아주 단순화하면 이렇습니다.

```text
vTaskSwitchContext()
    -> 다음 task를 선택
    -> pxCurrentTCB 갱신

PendSV handler
    -> 현재 CPU register 저장
    -> pxCurrentTCB->pxTopOfStack 읽음
    -> 다음 task의 CPU register 복원
```

그림으로 보면:

```text
+--------------------------+
| vTaskSwitchContext()     |
|--------------------------|
| 다음 task 선택            |
| pxCurrentTCB 변경         |
+------------+-------------+
             |
             v
+--------------------------+
| pxCurrentTCB             |
| now points to TCB B      |
+------------+-------------+
             |
             v
+--------------------------+
| PendSV Handler           |
|--------------------------|
| TCB B의 pxTopOfStack 사용 |
| Task B context 복원       |
+--------------------------+
```

## context switch 전체 그림

Task A에서 Task B로 바뀌는 과정을 한 번에 보면:

```text
[1] Task A 실행 중

pxCurrentTCB
     |
     v
+---------+
| TCB A   |
+---------+

[2] interrupt 또는 tick 발생

CPU:
"이제 context switch가 필요할 수 있음"

[3] Task A 상태 저장

+----------------+
| CPU registers  |
+--------+-------+
         |
         v
+----------------+
| Task A stack   |
+--------+-------+
         ^
         |
+--------|--------+
| TCB A           |
| pxTopOfStack ---+
+-----------------+

[4] scheduler가 Task B 선택

vTaskSwitchContext()
      |
      v
pxCurrentTCB = &TCB_B

[5] Task B 상태 복원

+-----------------+
| TCB B           |
| pxTopOfStack ---+
+--------+--------+
         |
         v
+----------------+
| Task B stack   |
+--------+-------+
         |
         v
+----------------+
| CPU registers  |
| restored B     |
+----------------+

[6] Task B 실행 시작
```

## TCB_t는 단순 metadata가 아니다

TCB를 단순히 이렇게 보면 부족합니다.

```text
TCB_t = task 이름, priority 저장하는 구조체
```

정확히는 이렇게 봐야 합니다.

```text
TCB_t = scheduler와 CPU port code가 공유하는 task 실행 상태 object
```

왜냐하면 TCB 안의 `pxTopOfStack`은 실제 CPU context switch에 쓰이기 때문입니다.

```text
scheduler
    pxCurrentTCB를 바꿈

port layer
    pxCurrentTCB->pxTopOfStack을 믿고 CPU 상태 복원
```

이 둘이 같은 TCB layout을 믿고 동작합니다.

## TCB_t를 중심으로 전체 구조 보기

```text
                         +------------------+
                         |   pxCurrentTCB   |
                         +--------+---------+
                                  |
                                  v
+------------------------------------------------------+
|                       TCB_t                          |
|------------------------------------------------------|
| pxTopOfStack  -----> saved stack context             |
|                                                      |
| xStateListItem ----> ready / delayed / suspended list|
|                                                      |
| xEventListItem ----> queue / semaphore wait list     |
|                                                      |
| uxPriority     ----> scheduler priority              |
|                                                      |
| pxStack        ----> stack memory start              |
|                                                      |
| pcTaskName     ----> debugging name                  |
+------------------------------------------------------+
```

## task가 ready list에 있을 때

```text
Ready List for priority 3

+---------------------+     +---------------------+
| Task A state item   | --> | Task B state item   |
| pvOwner -> TCB A    |     | pvOwner -> TCB B    |
+---------------------+     +---------------------+
          |                            |
          v                            v
      +-------+                    +-------+
      | TCB A |                    | TCB B |
      +-------+                    +-------+
```

Scheduler는 ready list에서 list item을 고릅니다.

```text
ListItem_t 선택
      |
      v
pvOwner 확인
      |
      v
TCB_t 찾음
      |
      v
pxCurrentTCB로 설정
```

## task가 queue를 기다릴 때

Task A가 queue receive를 기다린다고 합시다.

```text
Queue_t

+------------------------------------------------+
| xTasksWaitingToReceive                         |
|                                                |
| +----------------------+                       |
| | Task A event item    | ----> TCB A           |
| +----------------------+                       |
+------------------------------------------------+
```

동시에 Task A는 scheduler 관점에서는 blocked 상태입니다.

```text
TCB A
 ├─ xStateListItem
 │    -> blocked/delayed list
 │
 └─ xEventListItem
      -> queue receive wait list
```

그래서 두 list item이 필요합니다.

## TCB_t를 게임 저장 파일처럼 생각하기

비유하면 이렇습니다. 게임에서 캐릭터를 잠깐 멈췄다가 다시 시작하려면 저장 파일이
필요합니다. 저장 파일에는 이런 게 들어갑니다.

```text
캐릭터 위치
체력
아이템
현재 퀘스트
진행 상황
```

FreeRTOS task도 마찬가지입니다. Task를 잠깐 멈췄다가 다시 실행하려면 상태가
필요합니다.

```text
CPU register 상태
stack 위치
priority
어떤 list에 있는지
무엇을 기다리는지
```

그 저장 파일 역할을 하는 것이 `TCB_t`입니다.

```text
Task의 저장 파일 = TCB_t
```

## 진짜 핵심 요약

```text
TCB_t
    = FreeRTOS가 task 하나를 관리하기 위한 핵심 object

pxTopOfStack
    = context switch 때 CPU 상태를 저장/복원할 stack 위치
    = TCB의 첫 번째 필드여야 함

pxStack
    = task stack의 시작 주소

uxPriority
    = task 우선순위

pcTaskName
    = task 이름

xStateListItem
    = ready / delayed / suspended 같은 scheduler 상태 list에 들어가는 node

xEventListItem
    = queue / semaphore / mutex 같은 event wait list에 들어가는 node

pvOwner
    = list item에서 다시 자기 TCB로 돌아가는 pointer

pxCurrentTCB
    = 현재 실행 중인 task의 TCB를 가리키는 pointer
```

가장 중요한 그림은 이것입니다.

```text
                 +----------------+
                 |  pxCurrentTCB  |
                 +--------+-------+
                          |
                          v
+------------------------------------------------+
|                    TCB_t                       |
|------------------------------------------------|
| pxTopOfStack  -----> saved task stack          |
|                                                |
| xStateListItem ----> ready/delayed/suspended   |
|                                                |
| xEventListItem ----> queue/semaphore wait list |
|                                                |
| uxPriority                                     |
| pxStack                                        |
| pcTaskName                                     |
+------------------------------------------------+
```

더 짧게는 이겁니다.

```text
Scheduler
   |
   v
pxCurrentTCB
   |
   v
TCB_t
   |
   +--> pxTopOfStack --> CPU context 복원
   |
   +--> xStateListItem --> ready/delayed list
   |
   +--> xEventListItem --> queue/semaphore wait list
```

## 한 문장으로 정리

```text
TCB_t는 FreeRTOS가 task를 멈췄다가 다시 실행하고,
ready/blocked 상태로 옮기고,
priority에 따라 scheduling하기 위해 사용하는
task의 핵심 관리 object다.
```

즉, task function은 실행할 코드이고, `TCB_t`는 그 코드를 운영체제가 task로
다루기 위한 모든 상태 정보입니다.
