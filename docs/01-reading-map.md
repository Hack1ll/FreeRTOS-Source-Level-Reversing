# Reading map

`tasks.c`를 열기 전에 먼저 읽는 순서를 정해두는 것이 좋습니다.

FreeRTOS는 여러 방향에서 읽을 수 있습니다.

```text
public API에서 시작
    xTaskCreate()
    xQueueSend()

port layer에서 시작
    SysTick
    PendSV

memory allocator에서 시작
    pvPortMalloc()
    heap_4.c
```

이 프로젝트는 가장 작은 공통 구조부터 시작해 scheduler와 port layer로 올라갑니다.

```text
ListItem_t
    |
    v
TCB_t
    |
    v
ready lists and delayed lists
    |
    v
scheduler tick
    |
    v
PendSV context switch
    |
    v
queues, semaphores, mutexes, heap allocation
```

핵심은 이것입니다.

```text
FreeRTOS를 함수 이름 순서로 읽기보다,
"task가 어떤 list를 오가는가"를 기준으로 읽는다.
```

---

## 1. List부터 읽기

처음 볼 파일은 다음입니다.

```text
FreeRTOS-Kernel/include/list.h
FreeRTOS-Kernel/list.c
```

FreeRTOS의 list는 단순한 container library가 아닙니다.

FreeRTOS에서는 list가 task의 상태를 표현합니다.

```text
task가 ready list에 있음
    =
task가 실행 가능함

task가 delayed list에 있음
    =
task가 시간 때문에 잠들어 있음

task가 queue event list에 있음
    =
task가 queue event를 기다리고 있음
```

그림:

```text
TCB_t
  |
  +--> xStateListItem  ---> ready list or delayed list
  |
  +--> xEventListItem  ---> queue/semaphore/event wait list
```

처음에 눈에 익혀야 할 이름은 다음입니다.

```text
List_t
ListItem_t
MiniListItem_t
pvOwner
xItemValue
```

특히 `pvOwner`는 중요합니다.

```text
ListItem_t
    |
    v
pvOwner
    |
    v
TCB_t
```

list 안에 task 전체가 들어가는 것이 아니라, task 안의 list item이 들어갑니다.

---

## 2. 그다음 TCB_t 읽기

다음으로 볼 파일은 `FreeRTOS-Kernel/tasks.c`입니다.

여기서 가장 먼저 찾을 구조체는:

```text
TCB_t
```

입니다.

`TCB_t`는 task의 관리 카드입니다.

```text
TCB_t

+-----------------------------+
| pxTopOfStack                |
| xStateListItem              |
| xEventListItem              |
| uxPriority                  |
| pxStack                     |
+-----------------------------+
```

처음부터 모든 field를 외울 필요는 없습니다.

첫 번째 패스에서는 이 field들이 중요합니다.

```text
pxTopOfStack
    = context restore를 시작할 stack 위치

xStateListItem
    = ready/delayed/suspended 같은 task 상태 list에 들어가는 item

xEventListItem
    = queue/semaphore/event group 같은 event wait list에 들어가는 item

uxPriority
    = scheduler가 ready task를 고를 때 보는 priority

pxStack
    = task stack memory의 시작점
```

전역 변수도 같이 익혀둡니다.

```text
pxCurrentTCB
pxReadyTasksLists
xDelayedTaskList1
xDelayedTaskList2
xSuspendedTaskList
```

이 이름들이 익숙해지면 `tasks.c`는 거대한 파일 하나가 아니라 list transition들의 모음으로 보이기 시작합니다.

---

## 3. Task creation 따라가기

첫 번째 긴 경로는 task 생성입니다.

```text
xTaskCreate()
    |
    v
prvCreateTask()
    |
    v
prvInitialiseNewTask()
    |
    v
pxPortInitialiseStack()
    |
    v
prvAddNewTaskToReadyList()
```

여기서 중요한 점은 이것입니다.

```text
새 task는 아직 실행된 적이 없지만,
scheduler가 나중에 stack에서 context를 restore할 수 있어야 한다.
```

그래서 port layer가 fake initial stack frame을 만듭니다.

```text
new task stack

+-----------------------------+
| fake initial context        |
| PC = task function          |
| R0 = task parameter         |
+-----------------------------+
```

그 뒤 TCB는 ready list에 들어갑니다.

```text
xTaskCreate()
    |
    v
TCB_t + stack 준비
    |
    v
initial stack frame 생성
    |
    v
ready list 삽입
    |
    v
scheduler 후보가 됨
```

---

## 4. Scheduler start 보기

다음 경로는 scheduler 시작입니다.

```text
vTaskStartScheduler()
    |
    v
xPortStartScheduler()
    |
    v
start the first task
```

여기서 common kernel code가 port layer로 넘어갑니다.

첫 번째 패스에서는 GCC ARM Cortex-M4F port를 봅니다.

```text
FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c
FreeRTOS-Kernel/portable/GCC/ARM_CM4F/portmacro.h
```

이 port는 이런 질문에 답합니다.

```text
첫 task는 어떻게 시작되는가?
SysTick은 어떻게 설정되는가?
PendSV는 어떻게 context switch handler가 되는가?
interrupt priority는 어떻게 다루는가?
```

그림:

```text
common kernel
    |
    v
port.c
    |
    v
Cortex-M4F CPU
```

---

## 5. 일반적인 context switch 보기

Cortex-M에서 일반적인 scheduler 경로는 이렇게 볼 수 있습니다.

```text
SysTick interrupt
    |
    v
xPortSysTickHandler()
    |
    v
xTaskIncrementTick()
    |
    v
switch가 필요하면 portYIELD()
    |
    v
PendSV pending
    |
    v
xPortPendSVHandler()
    |
    v
save current context
    |
    v
vTaskSwitchContext()
    |
    v
restore next context
```

여기서 역할 분리가 중요합니다.

```text
xTaskIncrementTick()
vTaskSwitchContext()
    = common kernel logic

xPortSysTickHandler()
xPortPendSVHandler()
    = Cortex-M port logic
```

그림:

```text
SysTick
   |
   v
common tick logic
   |
   v
PendSV request
   |
   v
port-specific context switch
```

FreeRTOS가 portable한 이유는 이 경계가 작고 명확하기 때문입니다.

---

## 6. Blocking과 wakeup 읽기

기본 실행 흐름을 본 뒤에는 task가 잠들고 다시 깨어나는 흐름을 봅니다.

볼 함수는 다음입니다.

```text
vTaskDelay()
vTaskPlaceOnEventList()
vTaskRemoveFromUnorderedEventList()
xTaskIncrementTick()
```

이 부분에서 list model이 힘을 발휘합니다.

```text
blocking
    = 현재 task를 ready list에서 빼서
      delayed list나 event wait list에 넣는 것

wakeup
    = 조건이 만족된 task를 wait list에서 빼서
      ready list에 다시 넣는 것
```

그림:

```text
Ready List
    |
    | delay or wait
    v
Delayed/Event Wait List
    |
    | tick or event
    v
Ready List
```

---

## 7. Queue를 synchronization object로 읽기

다음으로 `FreeRTOS-Kernel/queue.c`를 봅니다.

중요한 함수는 다음입니다.

```text
xQueueGenericCreate()
xQueueGenericSend()
xQueueReceive()
xQueueGenericSendFromISR()
xQueueReceiveFromISR()
```

Queue는 단순 FIFO buffer가 아닙니다.

```text
Queue
    = data buffer
    + receive wait list
    + send wait list
```

그림:

```text
+------------------------------------------------+
| Queue                                          |
|------------------------------------------------|
| data buffer                                    |
| receive wait list                              |
| send wait list                                 |
+------------------------------------------------+
```

Queue를 이해하면 semaphore와 mutex가 훨씬 쉬워집니다.

```text
Semaphore
    = queue mechanics를 token 중심으로 사용

Mutex
    = queue mechanics + owner + priority inheritance
```

---

## 8. Event group까지 같은 문법으로 보기

Event group은 queue처럼 data를 주고받지 않습니다.

대신 bit 조건을 기다립니다.

```text
Event Group
    |
    v
event bits
    |
    v
조건 만족 task를 ready list로 이동
```

그래도 scheduler 관점의 문법은 같습니다.

```text
condition false
    -> task waits

condition true
    -> task becomes ready
```

즉 queue, semaphore, mutex, event group은 서로 달라 보이지만 같은 질문으로 읽을 수 있습니다.

```text
무엇을 기다리는가?
기다릴 때 어느 list에 들어가는가?
조건이 만족되면 어느 list로 돌아오는가?
```

---

## 9. heap_4로 첫 패스 마무리

마지막으로 `FreeRTOS-Kernel/portable/MemMang/heap_4.c`를 봅니다.

중요한 이름은 다음입니다.

```text
BlockLink_t
pvPortMalloc()
vPortFree()
prvHeapInit()
prvInsertBlockIntoFreeList()
```

`heap_4.c`는 첫 allocator로 읽기 좋습니다.

```text
heap_4.c
    = allocation 가능
    = free 가능
    = free list 사용
    = adjacent block coalescing 지원
```

task와 queue는 결국 메모리 위에 만들어집니다.

```text
xTaskCreate()
    -> TCB_t allocation
    -> stack allocation

xQueueCreate()
    -> Queue_t allocation
    -> storage allocation
```

그래서 allocator behavior도 kernel behavior입니다.

```text
allocation 실패
    |
    v
kernel object 생성 실패
    |
    v
scheduler 또는 synchronization 흐름에 영향
```

---

## 작은 source index

아래 line number는 commit `a8c9d3515` 기준입니다.

upstream kernel이 바뀌면 line number는 달라질 수 있습니다.

```text
FreeRTOS-Kernel/tasks.c:375
    TCB_t

FreeRTOS-Kernel/tasks.c:1741
    xTaskCreate()

FreeRTOS-Kernel/tasks.c:3700
    vTaskStartScheduler()

FreeRTOS-Kernel/tasks.c:4736
    xTaskIncrementTick()

FreeRTOS-Kernel/tasks.c:5120
    vTaskSwitchContext() single-core path

FreeRTOS-Kernel/tasks.c:5307
    vTaskPlaceOnEventList()

FreeRTOS-Kernel/tasks.c:5498
    vTaskRemoveFromUnorderedEventList()

FreeRTOS-Kernel/queue.c:103
    Queue_t

FreeRTOS-Kernel/queue.c:949
    xQueueGenericSend()

FreeRTOS-Kernel/queue.c:1509
    xQueueReceive()

FreeRTOS-Kernel/include/list.h:154
    ListItem_t

FreeRTOS-Kernel/include/list.h:172
    List_t

FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c:202
    pxPortInitialiseStack()

FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c:305
    xPortStartScheduler()

FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c:504
    xPortPendSVHandler()

FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c:560
    xPortSysTickHandler()

FreeRTOS-Kernel/portable/GCC/ARM_CM4F/portmacro.h:88
    portYIELD()

FreeRTOS-Kernel/portable/MemMang/heap_4.c:173
    pvPortMalloc()

FreeRTOS-Kernel/portable/MemMang/heap_4.c:354
    vPortFree()
```

---

## 최종 요약

첫 번째 읽기 순서는 이렇게 잡습니다.

```text
List
    |
    v
TCB_t
    |
    v
Task creation
    |
    v
Ready / delayed / event lists
    |
    v
Scheduler tick
    |
    v
Cortex-M context switch
    |
    v
Queue / semaphore / mutex / event group
    |
    v
heap_4 allocator
```

한 문장으로 정리하면:

```text
FreeRTOS 첫 번째 패스는
task와 kernel object가 list 위에서 어떻게 상태를 바꾸고,
그 상태 변화가 scheduler와 port layer를 거쳐 실제 CPU 실행으로 이어지는지 따라가는 길이다.
```

다음 장은 이 길의 가장 작은 출발점인 list implementation에서 시작합니다.
