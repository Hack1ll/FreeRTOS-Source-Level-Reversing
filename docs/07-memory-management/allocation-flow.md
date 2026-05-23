# Allocation flow

이번 주제는 Allocation flow입니다.

FreeRTOS에서 task나 queue 같은 커널 object가 만들어질 때 메모리가 어떻게
준비되는지 보는 장입니다.

핵심은 이것입니다.

```text
FreeRTOS object는 scheduler에 들어가기 전에
먼저 메모리 공간을 가져야 한다.

메모리 할당 성공
    -> TCB, stack, Queue_t 같은 object 생성 가능

메모리 할당 실패
    -> task나 queue 자체가 만들어지지 못함
```

이번 장에서 같이 보면 좋은 source file은 다음입니다.

- `FreeRTOS-Kernel/tasks.c`
- `FreeRTOS-Kernel/queue.c`
- `FreeRTOS-Kernel/portable/MemMang/heap_4.c`

## 커널 object도 결국 메모리가 필요하다

우리가 지금까지 본 FreeRTOS object들은 전부 메모리 위에 존재합니다.

```text
Task
    -> TCB_t 필요
    -> stack 필요

Queue
    -> Queue_t 필요
    -> queue storage 필요

Semaphore / Mutex
    -> 내부 queue-like object 필요
```

즉 scheduler가 task를 고르기 전에, 먼저 이런 일이 필요합니다.

```text
heap에서 메모리 확보
    |
    v
커널 object 초기화
    |
    v
scheduler list에 연결
```

## 전체 흐름을 먼저 보기

```text
FreeRTOS API 호출
        |
        v
+---------------------------+
| 필요한 메모리 할당         |
+------------+--------------+
             |
             v
+---------------------------+
| object 초기화              |
+------------+--------------+
             |
             v
+---------------------------+
| scheduler/list에 연결      |
+------------+--------------+
             |
             v
+---------------------------+
| 실제 커널 object로 동작     |
+---------------------------+
```

예를 들어 task는:

```text
xTaskCreate()
    |
    v
TCB와 stack 할당
    |
    v
TCB 초기화
    |
    v
ready list에 삽입
    |
    v
scheduler 후보가 됨
```

Queue는:

```text
xQueueGenericCreate()
    |
    v
Queue_t와 storage 할당
    |
    v
wait list 초기화
    |
    v
send/receive 가능한 queue가 됨
```

## Task allocation

동적 task 생성은 보통 `xTaskCreate()`에서 시작합니다.

사용자 입장에서는 이렇게 호출합니다.

```c
xTaskCreate(
    vTaskCode,
    "TaskA",
    128,
    NULL,
    3,
    &handle
);
```

겉으로는 task 하나 만들어줘입니다.

하지만 FreeRTOS 내부에서는 최소 두 가지 메모리가 필요합니다.

```text
1. TCB_t
   task 관리 정보

2. task stack
   task가 실행 중 사용할 stack 메모리
```

그림:

```text
xTaskCreate()
     |
     v
+------------------+      +------------------+
| TCB_t allocation |      | Stack allocation |
+------------------+      +------------------+
```

## TCB_t와 stack은 역할이 다르다

`TCB_t`는 task의 관리 카드입니다.

```text
TCB_t

+-----------------------------+
| task name                   |
| priority                    |
| pxTopOfStack                |
| xStateListItem              |
| xEventListItem              |
+-----------------------------+
```

Stack은 task가 실제 실행될 때 쓰는 작업 공간입니다.

```text
Task Stack

+-----------------------------+
| local variables             |
| function call frames        |
| saved registers             |
| context switch state        |
+-----------------------------+
```

둘 다 필요합니다.

```text
TCB_t만 있고 stack이 없음
    -> task 실행 불가

stack만 있고 TCB_t가 없음
    -> scheduler가 task를 관리 불가
```

## task 생성 흐름

동적 allocation path는 대략 이렇습니다.

```text
xTaskCreate()
    |
    v
allocate TCB
    |
    v
allocate stack
    |
    v
initialize task
    |
    v
insert into ready list
```

그림:

```text
+------------------------------+
| xTaskCreate()                |
+--------------+---------------+
               |
               v
+------------------------------+
| pvPortMalloc(sizeof(TCB_t))  |
| TCB 메모리 확보              |
+--------------+---------------+
               |
               v
+------------------------------+
| pvPortMalloc(stack size)     |
| stack 메모리 확보            |
+--------------+---------------+
               |
               v
+------------------------------+
| TCB 초기화                   |
| - name                       |
| - priority                   |
| - pxStack                    |
| - pxTopOfStack               |
| - list item owner            |
+--------------+---------------+
               |
               v
+------------------------------+
| initial stack frame 생성      |
+--------------+---------------+
               |
               v
+------------------------------+
| ready list에 xStateListItem  |
| 삽입                         |
+--------------+---------------+
               |
               v
+------------------------------+
| scheduler 후보가 됨          |
+------------------------------+
```

## task가 만들어진 후의 메모리 그림

```text
Heap memory

+-------------------+------------------------+------------------+
| TCB_t for Task A  | Stack for Task A       | remaining free   |
+-------------------+------------------------+------------------+
```

TCB와 stack은 서로 연결됩니다.

```text
+--------------------------------+
|             TCB A              |
|--------------------------------|
| pxStack -----------------------+----+
| pxTopOfStack ------------------+--+ |
| uxPriority = 3                 |  | |
| xStateListItem                 |  | |
+--------------------------------+  | |
                                    | |
                                    | v
                                    | +----------------------+
                                    | | Task A Stack         |
                                    | | fake initial context |
                                    | | saved context later  |
                                    | +----------------------+
                                    |
                                    v
                              stack base
```

그리고 ready list에 들어갑니다.

```text
Priority 3 Ready List

+------------------------+
| Task A xStateListItem  | ---> TCB A
+------------------------+
```

## allocation 실패 시 task는 태어나지 못한다

중요합니다.

`pvPortMalloc()`이 실패하면 필요한 메모리를 못 받은 것입니다.

```text
TCB_t allocation 실패
    -> task 생성 불가

stack allocation 실패
    -> task 생성 불가
```

즉 allocation 실패는 단순한 C 프로그래밍 문제가 아닙니다.

```text
메모리 부족
    |
    v
task object가 생성되지 않음
    |
    v
scheduler 후보가 되지 않음
```

그림:

```text
xTaskCreate()
     |
     v
allocate TCB
     |
     +--> 실패
            |
            v
      task 생성 실패
      ready list에 들어가지 않음
```

또는:

```text
xTaskCreate()
     |
     v
allocate TCB 성공
     |
     v
allocate stack
     |
     +--> 실패
            |
            v
      TCB 정리 후 task 생성 실패
```

## Static allocation이면 heap을 피한다

FreeRTOS는 동적 allocation만 있는 것이 아닙니다.

정적 allocation을 사용하면 사용자가 직접 메모리를 제공합니다.

```text
Dynamic allocation
    = FreeRTOS가 heap에서 메모리 가져옴

Static allocation
    = 사용자가 TCB와 stack 메모리를 직접 제공
```

예를 들어 static task 생성은 이런 느낌입니다.

```text
사용자가 준비:

+------------------------+
| StaticTask_t storage   |
+------------------------+

+------------------------+
| StackType_t array      |
+------------------------+
```

FreeRTOS는 이 메모리를 받아 초기화만 합니다.

```text
xTaskCreateStatic()
    |
    v
caller가 준 TCB storage 사용
caller가 준 stack 사용
    |
    v
heap allocation 없음
```

그림:

```text
Static allocation

Application provides memory
        |
        v
+------------------+      +------------------+
| TCB storage      |      | Stack array      |
+------------------+      +------------------+
        |
        v
FreeRTOS initializes them
        |
        v
ready list에 삽입
```

즉:

```text
정적 allocation
    = heap_4.c 경로를 피함
```

## Queue allocation

Queue도 task와 비슷합니다.

사용자 입장에서는 이렇게 만듭니다.

```c
QueueHandle_t q = xQueueCreate(10, sizeof(int));
```

뜻:

```text
int 10개를 저장할 수 있는 queue를 만들어줘.
```

내부적으로는 최소한 두 가지가 필요합니다.

```text
1. Queue_t
   queue control object

2. queue storage
   실제 item들이 저장될 buffer
```

그림:

```text
xQueueCreate()
     |
     v
+--------------------+      +----------------------+
| Queue_t allocation |      | storage allocation   |
+--------------------+      +----------------------+
```

## Queue_t와 storage의 차이

`Queue_t`는 queue를 관리하는 구조체입니다.

```text
Queue_t

+--------------------------------+
| pcHead                         |
| pcWriteTo                      |
| uxMessagesWaiting              |
| uxLength                       |
| uxItemSize                     |
| xTasksWaitingToSend            |
| xTasksWaitingToReceive         |
+--------------------------------+
```

Storage는 실제 데이터가 들어가는 공간입니다.

```text
Queue Storage

+------+------+------+------+------+
| item | item | item |      |      |
+------+------+------+------+------+
```

둘의 관계:

```text
+--------------------+
| Queue_t            |
| pcHead ------------+----+
| pcWriteTo ---------+--+ |
+--------------------+  | |
                        | |
                        v v
                 +------+------+------+------+
                 | item | item |      |      |
                 +------+------+------+------+
```

## queue 생성 흐름

```text
xQueueGenericCreate()
    |
    v
allocate Queue_t
    |
    v
allocate or attach storage
    |
    v
initialize queue fields
    |
    v
initialize wait lists
```

그림:

```text
+--------------------------------+
| xQueueGenericCreate()          |
+---------------+----------------+
                |
                v
+--------------------------------+
| Queue_t 메모리 확보            |
+---------------+----------------+
                |
                v
+--------------------------------+
| item storage 메모리 확보       |
| length * item size             |
+---------------+----------------+
                |
                v
+--------------------------------+
| Queue_t 필드 초기화            |
| - uxLength                     |
| - uxItemSize                   |
| - uxMessagesWaiting = 0        |
| - pcHead                       |
| - pcWriteTo                    |
+---------------+----------------+
                |
                v
+--------------------------------+
| wait list 초기화               |
| - xTasksWaitingToSend          |
| - xTasksWaitingToReceive       |
+---------------+----------------+
                |
                v
+--------------------------------+
| 사용 가능한 Queue 완성         |
+--------------------------------+
```

## queue가 만들어진 후의 메모리 그림

```text
Heap memory

+------------------+-----------------------+------------------+
| Queue_t          | Queue storage         | remaining free   |
+------------------+-----------------------+------------------+
```

Queue_t는 storage를 가리킵니다.

```text
+--------------------------------+
|            Queue_t             |
|--------------------------------|
| pcHead ------------------------+----+
| pcWriteTo ---------------------+--+ |
| uxLength = 10                  |  | |
| uxItemSize = sizeof(int)       |  | |
| xTasksWaitingToSend            |  | |
| xTasksWaitingToReceive         |  | |
+--------------------------------+  | |
                                    | |
                                    v v
                          +------+------+------+------+
                          | item | item |      |      |
                          +------+------+------+------+
```

그리고 wait list들은 처음에는 비어 있습니다.

```text
xTasksWaitingToSend
    empty

xTasksWaitingToReceive
    empty
```

## queue allocation 실패도 커널 행동에 영향을 준다

`Queue_t`나 storage allocation이 실패하면 queue가 만들어지지 않습니다.

```text
xQueueCreate()
    |
    v
Queue_t allocation 실패
    |
    v
queue 생성 실패
```

또는:

```text
Queue_t allocation 성공
    |
    v
storage allocation 실패
    |
    v
queue 생성 실패
```

이 경우 application은 queue handle을 얻지 못합니다.

```text
QueueHandle_t q = NULL
```

그 결과:

```text
task들이 기다릴 queue 자체가 없음
```

즉 allocator 실패는 scheduler와 synchronization object의 존재 여부에 직접
영향을 줍니다.

## Semaphore와 mutex도 queue allocation과 연결된다

앞에서 semaphore와 mutex는 queue 메커니즘 위에 만들어진다고 했습니다.

그래서 semaphore/mutex 생성도 queue allocation과 비슷합니다.

```text
xSemaphoreCreateBinary()
    |
    v
내부적으로 queue-like object 생성
    |
    v
Queue_t memory 필요
```

Mutex도:

```text
xSemaphoreCreateMutex()
    |
    v
Queue_t 기반 mutex object 생성
    |
    v
owner 정보와 wait list 준비
```

그림:

```text
Semaphore / Mutex API
        |
        v
+-------------------------+
| Queue-based object      |
+------------+------------+
             |
             v
+-------------------------+
| pvPortMalloc()          |
+-------------------------+
```

## heap_4.c와 연결하기

동적 allocation을 쓴다면 결국 이런 함수로 갑니다.

```text
pvPortMalloc()
```

그리고 `heap_4.c`에서는:

```text
pvPortMalloc()
    |
    v
free list에서 충분히 큰 free block 찾기
    |
    v
필요하면 split
    |
    v
user pointer 반환
```

반대로 object 삭제 시:

```text
vPortFree()
    |
    v
block header 복구
    |
    v
free list에 삽입
    |
    v
인접 free block과 coalescing
```

즉 task와 queue 생성은 heap allocator와 직접 연결됩니다.

```text
xTaskCreate()
    -> pvPortMalloc()
    -> heap_4 free list

xQueueCreate()
    -> pvPortMalloc()
    -> heap_4 free list
```

## 전체 연결 그림

```text
+------------------------------------------------------+
| Application APIs                                     |
|------------------------------------------------------|
| xTaskCreate()                                        |
| xQueueCreate()                                       |
| xSemaphoreCreateBinary()                             |
+--------------------------+---------------------------+
                           |
                           v
+------------------------------------------------------+
| Kernel object creation                               |
|------------------------------------------------------|
| TCB_t                                                |
| Task stack                                           |
| Queue_t                                              |
| Queue storage                                        |
| Semaphore/mutex object                               |
+--------------------------+---------------------------+
                           |
                           v
+------------------------------------------------------+
| Memory allocation                                    |
|------------------------------------------------------|
| pvPortMalloc()                                       |
| vPortFree()                                          |
+--------------------------+---------------------------+
                           |
                           v
+------------------------------------------------------+
| heap_4.c                                             |
|------------------------------------------------------|
| free list                                            |
| block split                                          |
| block coalescing                                     |
+------------------------------------------------------+
```

## object가 scheduler object가 되는 과정

메모리만 있다고 바로 scheduler object가 되는 것은 아닙니다.

Task의 경우:

```text
메모리 확보
    |
    v
TCB_t 초기화
    |
    v
stack 초기화
    |
    v
xStateListItem 준비
    |
    v
ready list에 삽입
    |
    v
scheduler 후보
```

그림:

```text
Heap memory
    |
    v
+----------------+
| TCB_t          |
+----------------+
    |
    v
initialize
    |
    v
+----------------+
| xStateListItem |
+----------------+
    |
    v
Ready List
```

Queue의 경우:

```text
메모리 확보
    |
    v
Queue_t 초기화
    |
    v
send/receive wait list 초기화
    |
    v
동기화 object로 사용 가능
```

그림:

```text
Heap memory
    |
    v
+----------------+
| Queue_t        |
+----------------+
    |
    v
initialize
    |
    v
+-----------------------------+
| xTasksWaitingToSend         |
| xTasksWaitingToReceive      |
+-----------------------------+
    |
    v
task를 block/wake할 수 있음
```

## allocation 실패는 왜 중요한가?

일반 C 프로그래밍에서도 malloc 실패는 문제입니다.

하지만 FreeRTOS에서는 더 직접적입니다.

```text
allocation 실패
    |
    v
kernel object 생성 실패
    |
    v
task, queue, semaphore가 존재하지 않음
    |
    v
scheduler와 동기화 흐름 자체가 달라짐
```

예:

```text
LogTask 생성 실패
    -> 로그 처리 task가 scheduler 후보가 안 됨

SensorQueue 생성 실패
    -> sensor task와 processing task가 통신할 수 없음

Mutex 생성 실패
    -> shared resource 보호 불가
```

즉 allocator는 단순한 메모리 utility가 아닙니다.

```text
allocator behavior is kernel behavior
```

FreeRTOS에서는 이 말이 꽤 중요합니다.

## 첫 번째 읽기 루프가 완성된다

지금까지 흐름을 하나로 묶으면 이렇게 됩니다.

```text
[1] Allocation
    heap에서 TCB, stack, Queue_t 같은 메모리 확보

[2] Object initialization
    TCB, Queue_t, list item 초기화

[3] Scheduler lists
    task를 ready/delayed/wait list에 넣음

[4] Tick / event
    시간이 지나거나 event가 발생해서 task가 ready가 됨

[5] Scheduler decision
    vTaskSwitchContext()가 다음 TCB 선택

[6] Context switch
    PendSV가 pxTopOfStack을 이용해 task stack 복원

[7] Free
    object 삭제 시 heap으로 메모리 반환 가능
```

그림:

```text
+----------------------+
| Heap allocation      |
| pvPortMalloc()       |
+----------+-----------+
           |
           v
+----------------------+
| Kernel object        |
| TCB_t / Queue_t      |
+----------+-----------+
           |
           v
+----------------------+
| Scheduler lists      |
| ready / delayed/wait |
+----------+-----------+
           |
           v
+----------------------+
| Tick or event        |
| task becomes ready   |
+----------+-----------+
           |
           v
+----------------------+
| vTaskSwitchContext() |
| choose next TCB      |
+----------+-----------+
           |
           v
+----------------------+
| PendSV               |
| restore task stack   |
+----------+-----------+
           |
           v
+----------------------+
| Task runs            |
+----------------------+
```

## 전체 시스템을 한 장으로 보기

```text
                +----------------------+
                | pvPortMalloc()       |
                | heap_4.c             |
                +----------+-----------+
                           |
       +-------------------+-------------------+
       |                                       |
       v                                       v

+------------------+                  +------------------+
| Task allocation  |                  | Queue allocation |
|------------------|                  |------------------|
| TCB_t            |                  | Queue_t          |
| Stack            |                  | Storage          |
+--------+---------+                  +--------+---------+
         |                                     |
         v                                     v

+------------------+                  +---------------------------+
| TCB initialized  |                  | Queue initialized         |
| xStateListItem   |                  | send/receive wait lists   |
+--------+---------+                  +-------------+-------------+
         |                                          |
         v                                          v

+------------------+                  +---------------------------+
| Ready List       |                  | Queue Wait Lists          |
| scheduler target |                  | block/wake tasks          |
+------------------+                  +---------------------------+
```

## 최종 요약

```text
Task dynamic allocation
    = TCB_t 메모리 필요
    = stack 메모리 필요
    = 초기화 후 ready list에 들어감

Queue dynamic allocation
    = Queue_t 메모리 필요
    = queue storage 메모리 필요
    = wait list 초기화 후 synchronization object가 됨

Static allocation
    = caller가 storage를 직접 제공
    = heap allocation path를 피함

heap_4.c
    = pvPortMalloc(), vPortFree() 제공
    = FreeRTOS object들이 사용할 메모리를 관리

allocation 실패
    = 단순한 malloc 실패가 아니라
      task나 queue 같은 kernel object가 존재하지 못한다는 뜻
```

가장 중요한 그림은 이것입니다.

```text
xTaskCreate()
    |
    +--> pvPortMalloc(TCB_t)
    |
    +--> pvPortMalloc(Stack)
    |
    +--> initialize TCB
    |
    +--> insert into Ready List


xQueueCreate()
    |
    +--> pvPortMalloc(Queue_t)
    |
    +--> pvPortMalloc(Storage)
    |
    +--> initialize Queue
    |
    +--> initialize Wait Lists
```

한 문장으로 정리하면:

```text
FreeRTOS에서 task나 queue는 그냥 함수 호출만으로 생기는 것이 아니라,
heap에서 필요한 메모리를 확보하고,
그 메모리를 TCB_t나 Queue_t로 초기화한 뒤,
ready list나 wait list에 연결될 때 비로소 커널 object가 된다.
```
