# Task creation

`xTaskCreate()`는 task가 태어나서 scheduler 후보가 되기까지의 과정입니다.

핵심은 이것입니다.

```text
xTaskCreate()는 단순히 함수를 등록하는 API가 아니다.

FreeRTOS 안에서는
1. TCB_t를 만들고
2. stack을 만들고
3. 처음 실행 가능한 것처럼 stack을 꾸며놓고
4. ready list에 넣는다.
```

## 우리가 보는 API

사용자는 보통 이렇게 task를 만듭니다.

```c
xTaskCreate(
    vSensorTask,      /* 실행할 함수 */
    "SensorTask",    /* task 이름 */
    128,             /* stack 크기 */
    NULL,            /* task parameter */
    3,               /* priority */
    NULL             /* task handle */
);
```

겉으로 보면 이런 의미입니다.

```text
"vSensorTask라는 함수를 priority 3짜리 task로 만들어줘."
```

하지만 FreeRTOS 내부에서는 이 함수 하나를 바로 실행하지 않습니다. FreeRTOS는 이
입력을 커널이 관리할 수 있는 object로 바꿔야 합니다.

## xTaskCreate()의 목표

`xTaskCreate()`가 끝났을 때 FreeRTOS 안에는 이런 것들이 생겨야 합니다.

```text
+-------------------+
|      TCB_t        |
|-------------------|
| task name         |
| priority          |
| stack information |
| list items        |
+-------------------+

+-------------------+
|    Task Stack     |
|-------------------|
| fake stack frame  |
| for first run     |
+-------------------+

Ready List
+-------------------+
| task's ListItem_t |
+-------------------+
```

즉, task creation의 목표는 이것입니다.

```text
사용자가 준 함수
    |
    v
FreeRTOS가 scheduling할 수 있는 task object
```

## 전체 흐름

본문에서 따라갈 경로는 이것입니다.

```text
xTaskCreate()
    -> prvCreateTask()
    -> prvInitialiseNewTask()
    -> pxPortInitialiseStack()
    -> prvAddNewTaskToReadyList()
```

그림으로 보면:

```text
+-----------------------------+
| xTaskCreate()               |
|-----------------------------|
| 사용자가 호출하는 API        |
+-------------+---------------+
              |
              v
+-----------------------------+
| prvCreateTask()             |
|-----------------------------|
| TCB와 stack 메모리 준비      |
+-------------+---------------+
              |
              v
+-----------------------------+
| prvInitialiseNewTask()      |
|-----------------------------|
| TCB 필드 초기화              |
| task 이름, priority 등 설정 |
+-------------+---------------+
              |
              v
+-----------------------------+
| pxPortInitialiseStack()     |
|-----------------------------|
| 처음 실행될 수 있도록        |
| stack을 미리 꾸며놓음        |
+-------------+---------------+
              |
              v
+-----------------------------+
| prvAddNewTaskToReadyList()  |
|-----------------------------|
| priority에 맞는 ready list에 |
| task를 넣음                 |
+-----------------------------+
```

## xTaskCreate()는 신청서 접수에 가깝다

`xTaskCreate()`는 사용자 입장에서 보이는 입구입니다.

```text
Application code

xTaskCreate(
    task function,
    task name,
    stack depth,
    parameter,
    priority,
    handle
);
```

이 정보들은 아직 커널 내부 자료구조가 아닙니다.

```text
사용자 입력

+----------------+
| task function  |
| name           |
| stack size     |
| parameter      |
| priority       |
+----------------+
```

FreeRTOS는 이것을 다음 형태로 바꿔야 합니다.

```text
커널 내부 object

+----------------+
| TCB_t          |
+----------------+

+----------------+
| Stack memory   |
+----------------+

+----------------+
| Ready list item|
+----------------+
```

즉:

```text
xTaskCreate()
    = task 생성 요청을 커널 object 생성으로 바꾸는 입구
```

## prvCreateTask(): TCB와 stack을 만든다

Task가 실행되려면 최소한 두 가지가 필요합니다.

```text
1. TCB_t
   task management information

2. Stack
   task가 실행 중 사용할 stack memory
```

그림으로 보면:

```text
prvCreateTask()

+--------------------------+
| allocate TCB_t memory    |
+--------------------------+

+--------------------------+
| allocate stack memory    |
+--------------------------+
```

결과는 이런 모습입니다.

```text
+-----------------------------+
|            TCB_t            |
|-----------------------------|
| pxTopOfStack                |
| xStateListItem              |
| xEventListItem              |
| uxPriority                  |
| pxStack                     |
| pcTaskName                  |
+-----------------------------+

+-----------------------------+
|         Stack Memory        |
|-----------------------------|
|                             |
|                             |
|                             |
+-----------------------------+
```

아직 이 task는 실행 가능한 상태가 아닙니다. 그냥 빈 task object와 빈 stack 공간이
생긴 정도입니다.

## prvInitialiseNewTask(): TCB를 채운다

이제 TCB 안에 정보를 넣습니다. 예를 들어 사용자가 이렇게 만들었다고 합시다.

```c
xTaskCreate(
    vSensorTask,
    "SensorTask",
    128,
    NULL,
    3,
    NULL
);
```

그러면 TCB에는 대략 이런 정보가 들어갑니다.

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| pcTaskName   = "SensorTask"    |
| uxPriority   = 3               |
| pxStack      = stack start     |
| pxTopOfStack = set later       |
| xStateListItem                 |
| xEventListItem                 |
+--------------------------------+
```

또 중요한 일도 합니다. TCB 안의 list item들이 자기 주인인 TCB를 가리키게 합니다.

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| xStateListItem                 |
|   pvOwner ----------------+    |
|                            |    |
| xEventListItem             |    |
|   pvOwner -------------+   |    |
+-------------------------|---|---+
                          |   |
                          v   v
                       this TCB
```

이렇게 해둬야 나중에 ready list나 queue wait list에서 list item을 꺼냈을 때 다시
TCB로 돌아올 수 있습니다.

```text
ListItem_t
    |
    v
pvOwner
    |
    v
TCB_t
```

## 가장 이상한 부분: task는 실행되기 전에 이미 실행되다 멈춘 것처럼 만들어진다

여기가 task creation에서 가장 중요한 부분입니다.

처음 만들어진 task는 아직 한 번도 실행된 적이 없습니다. 그런데 FreeRTOS는 나중에
이 task를 실행할 때 보통 이런 방식으로 실행합니다.

```text
TCB의 pxTopOfStack을 본다
    |
    v
stack에서 CPU register를 복원한다
    |
    v
task를 실행한다
```

문제는 새 task는 아직 실행된 적이 없기 때문에 복원할 CPU 상태가 없다는 점입니다.

그래서 FreeRTOS는 trick을 씁니다.

```text
새 task의 stack에
마치 예전에 실행되다가 멈춘 task처럼
가짜 초기 CPU 상태를 만들어 둔다.
```

이 일을 하는 함수가:

```text
pxPortInitialiseStack()
```

입니다.

## pxPortInitialiseStack(): fake initial stack frame 만들기

Cortex-M 같은 CPU에서는 interrupt나 context switch 후 복원할 때 stack에 저장된
register들을 꺼내서 실행을 이어갑니다. FreeRTOS는 이 동작을 이용합니다.

새 task의 stack을 이렇게 꾸며둡니다.

```text
Task Stack

+-----------------------------+
| fake xPSR                   |
+-----------------------------+
| fake PC = task function     |
+-----------------------------+
| fake LR                     |
+-----------------------------+
| R12                         |
+-----------------------------+
| R3                          |
+-----------------------------+
| R2                          |
+-----------------------------+
| R1                          |
+-----------------------------+
| R0 = task parameter         |
+-----------------------------+
| additional saved registers  |
+-----------------------------+
```

핵심은 두 개입니다.

```text
PC = task function address
R0 = task parameter
```

C에서 함수 호출을 생각하면:

```c
vSensorTask( parameter );
```

이런 식으로 시작해야 합니다. Cortex-M에서는 첫 번째 인자가 보통 `R0`에 들어갑니다.
그래서 FreeRTOS는 stack에 미리 이렇게 만들어 둡니다.

```text
R0 = pvParameters
PC = pxTaskCode
```

그러면 나중에 CPU가 이 stack frame을 복원할 때 이렇게 됩니다.

```text
CPU가 register를 복원함
    |
    v
PC에 task 함수 주소가 들어감
    |
    v
R0에 task parameter가 들어감
    |
    v
task 함수가 처음부터 실행됨
```

## 그림으로 보는 fake initial stack

사용자가 만든 task:

```c
void vSensorTask( void * pvParameters )
{
    while( 1 )
    {
        read_sensor();
    }
}
```

FreeRTOS는 stack을 이렇게 준비합니다.

```text
Allocated Stack

+--------------------------------+
|                                |
|                                |
|                                |
| fake initial exception frame   |
|--------------------------------|
| PC = vSensorTask               |
| R0 = pvParameters              |
| other initial register values  |
+--------------------------------+
                ^
                |
        pxTopOfStack
```

그리고 TCB가 이 위치를 기억합니다.

```text
+-------------------------------+
|            TCB_t              |
|-------------------------------|
| pxTopOfStack -----------------+----+
| pxStack                       |    |
| uxPriority = 3                |    |
| pcTaskName = "SensorTask"     |    |
+-------------------------------+    |
                                     v
                           +--------------------+
                           | Task Stack         |
                           | fake stack frame   |
                           +--------------------+
```

즉, 새 task는 실제로 실행된 적이 없지만, FreeRTOS 입장에서는 이렇게 보입니다.

```text
"이 task는 예전에 실행되다가 멈춘 적이 있는 것처럼 복원 가능하다."
```

## 왜 이렇게 할까?

특별한 첫 실행 전용 코드를 만들지 않기 위해서입니다.

나쁜 방식으로 생각하면 scheduler가 이렇게 해야 할 수도 있습니다.

```text
if task가 처음 실행되는 task라면:
    task 함수를 직접 호출
else:
    stack에서 context 복원
```

하지만 FreeRTOS는 이렇게 하지 않습니다. 대신 모든 task를 똑같이 처리합니다.

```text
모든 task는 pxTopOfStack에서 context를 복원한다.
```

새 task도 예외가 아닙니다.

```text
새 task
    -> fake stack frame을 복원
    -> task 함수로 처음 진입

기존 task
    -> 실제 저장된 stack frame을 복원
    -> 멈췄던 지점부터 재개
```

그림으로 보면:

```text
기존 task

+----------------+
| saved context  |
+----------------+
        |
        v
멈췄던 지점부터 실행

새 task

+----------------+
| fake context   |
+----------------+
        |
        v
task 함수 첫 줄부터 실행
```

둘 다 scheduler 입장에서는 같습니다.

```text
pxTopOfStack을 보고 복원한다
```

## prvAddNewTaskToReadyList(): ready list에 넣는다

이제 TCB도 있고, stack도 있고, 처음 실행될 준비도 끝났습니다. 마지막으로 이 task를
scheduler 후보에 넣어야 합니다. 그게 ready list입니다.

```text
prvAddNewTaskToReadyList()
    |
    v
priority에 맞는 ready list에 task의 xStateListItem을 넣음
```

예를 들어 priority가 3이면:

```text
Priority 3 Ready List

+----------------------+
| Task의 xStateListItem|
| pvOwner -> TCB       |
+----------------------+
```

전체 그림:

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| uxPriority = 3                 |
| xStateListItem ---------------+|
+--------------------------------||
                                 ||
                                 |v
                    +-------------------------+
                    | Priority 3 Ready List   |
                    |-------------------------|
                    | xStateListItem          |
                    | pvOwner -> TCB          |
                    +-------------------------+
```

이 순간부터 task는 scheduler가 고를 수 있는 정상 후보가 됩니다.

```text
ready list에 들어감
    |
    v
scheduler가 선택 가능
```

## Task creation 전체 그림

```text
사용자 코드

xTaskCreate(
    vSensorTask,
    "SensorTask",
    128,
    NULL,
    3,
    &handle
);
        |
        v

+------------------------------------------------+
| 1. TCB_t 생성                                  |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 2. Stack 메모리 생성                           |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 3. TCB 초기화                                  |
|    - 이름                                      |
|    - priority                                  |
|    - pxStack                                   |
|    - list item owner 설정                      |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 4. Stack 초기화                                |
|    - fake initial stack frame 생성             |
|    - PC = task function                        |
|    - R0 = parameter                            |
|    - pxTopOfStack 저장                         |
+------------------------------------------------+
        |
        v
+------------------------------------------------+
| 5. Ready list에 추가                           |
|    - priority에 맞는 ready list에 삽입          |
+------------------------------------------------+
        |
        v

Scheduler가 실행 후보로 볼 수 있는 task 완성
```

## task가 만들어진 직후의 모습

```text
+----------------------------------------------------------+
|                        TCB_t                             |
|----------------------------------------------------------|
| pcTaskName = "SensorTask"                                |
| uxPriority = 3                                           |
| pxStack  ----------------------------------+             |
| pxTopOfStack --------------------------+   |             |
| xStateListItem -------------------+    |   |             |
| xEventListItem                    |    |   |             |
+-----------------------------------|----|---|-------------+
                                    |    |   |
                                    |    |   v
                                    |    |  +----------------------+
                                    |    |  | Stack memory         |
                                    |    |  |----------------------|
                                    |    |  | fake context         |
                                    |    |  | PC = vSensorTask     |
                                    |    |  | R0 = parameter       |
                                    |    |  +----------------------+
                                    |    |
                                    |    v
                                    |  saved top of stack
                                    |
                                    v
                         +-------------------------+
                         | Priority 3 Ready List   |
                         |-------------------------|
                         | xStateListItem          |
                         | pvOwner -> TCB          |
                         +-------------------------+
```

## task가 실행된다는 말의 진짜 의미

Task가 만들어졌다고 바로 실행되는 것은 아닙니다. 정확한 흐름은 이렇습니다.

```text
xTaskCreate()
    |
    v
task object 생성
    |
    v
ready list에 들어감
    |
    v
scheduler가 나중에 선택
    |
    v
context restore
    |
    v
task 함수 실행 시작
```

즉:

```text
task creation  = 실행 준비 완료
task scheduling = 실제 실행 선택
context restore = CPU가 그 task로 진입
```

## scheduler가 새 task를 처음 실행할 때

새 task가 ready list에 들어갔다고 합시다.

```text
Priority 3 Ready List

+----------------------------+
| SensorTask xStateListItem  |
| pvOwner -> TCB             |
+----------------------------+
```

Scheduler가 이 task를 선택합니다.

```text
Scheduler
    |
    v
ready list에서 ListItem_t 선택
    |
    v
pvOwner로 TCB 찾음
    |
    v
pxCurrentTCB = SensorTask의 TCB
```

그다음 port layer가 stack을 복원합니다.

```text
Port layer
    |
    v
pxCurrentTCB->pxTopOfStack 확인
    |
    v
stack에서 fake context 복원
    |
    v
PC = vSensorTask
R0 = pvParameters
    |
    v
vSensorTask( pvParameters ) 실행 시작
```

그림으로 보면:

```text
+----------------+
| Scheduler      |
+-------+--------+
        |
        v
+----------------+
| pxCurrentTCB   |
| -> TCB         |
+-------+--------+
        |
        v
+----------------------------+
| TCB                        |
| pxTopOfStack --------------+----+
+----------------------------+    |
                                  v
                         +----------------+
                         | Task Stack     |
                         | fake context   |
                         | PC = task func |
                         | R0 = parameter |
                         +-------+--------+
                                 |
                                 v
                         task 함수 시작
```

## 새 task의 priority가 더 높으면?

이미 scheduler가 실행 중인 상황에서 새 task를 만들 수도 있습니다. 예를 들어 현재
Task A가 실행 중입니다.

```text
현재 실행 중

Task A priority 2
```

그런데 새 task를 만듭니다.

```text
새 Task B priority 5
```

그러면 상황이 바뀝니다.

```text
Task B가 Task A보다 priority가 높음
```

FreeRTOS는 이렇게 판단할 수 있습니다.

```text
"방금 만든 Task B가 지금 실행 중인 Task A보다 더 중요하다.
그러면 곧바로 Task B로 바꿔야 할 수도 있다."
```

그래서 task creation은 단순한 메모리 할당이 아닙니다.

```text
task 생성
    |
    v
ready list 변경
    |
    v
가장 높은 priority ready task가 바뀔 수 있음
    |
    v
context switch 요청 가능
```

그림:

```text
Before

Running:
+-------------------+
| Task A priority 2 |
+-------------------+

Ready List priority 5:
empty

xTaskCreate(Task B, priority 5)

After

Running:
+-------------------+
| Task A priority 2 |
+-------------------+

Ready List priority 5:
+-------------------+
| Task B            |
+-------------------+

Result:
Task B가 더 높은 priority이므로 yield/context switch 가능
```

## creation은 allocation만이 아니다

초보자는 task creation을 이렇게 생각할 수 있습니다.

```text
xTaskCreate()
    = memory allocation
```

하지만 FreeRTOS에서는 더 정확히 이렇게 봐야 합니다.

```text
xTaskCreate()
    = task를 scheduler가 이해할 수 있는 형태로 등록하는 과정
```

즉:

```text
1. TCB 생성
2. stack 생성
3. fake context 생성
4. ready list 등록
5. 필요하면 scheduling 변화 유발
```

## xTaskCreate() 전과 후

Before:

```text
FreeRTOS는 아직 이 task를 모름

Application function

+----------------------+
| vSensorTask()        |
+----------------------+
```

이 함수는 그냥 코드일 뿐입니다.

After:

```text
FreeRTOS가 관리 가능한 task object가 됨

+----------------------+
| vSensorTask()        |
+----------+-----------+
           |
           v
+----------------------+
| TCB_t                |
| name = SensorTask    |
| priority = 3         |
| pxTopOfStack         |
+----------+-----------+
           |
           v
+----------------------+
| Stack                |
| fake initial context |
+----------------------+

Ready List priority 3
+----------------------+
| xStateListItem       |
| pvOwner -> TCB       |
+----------------------+
```

## 핵심 비유: 수업에 학생 등록하기

Task creation을 학교 수업 등록에 비유하면 쉽습니다. 사용자가 `xTaskCreate()`를
호출하는 것은:

```text
"이 학생을 수업에 등록해 주세요."
```

라고 신청하는 것입니다. 그러면 학교는 이런 것을 만듭니다.

```text
학생부 기록        = TCB_t
개인 사물함        = stack
출석부에 이름 추가 = ready list에 넣기
첫 수업 준비물     = fake initial stack frame
```

그 학생은 아직 수업을 듣기 시작하지 않았지만, 이제 선생님이 부를 수 있습니다.

```text
ready list에 들어감
    =
scheduler가 선택할 수 있음
```

## 전체를 한 장으로 정리

```text
                    xTaskCreate()
                         |
                         v
+--------------------------------------------------+
| 사용자 입력                                       |
|--------------------------------------------------|
| task function                                    |
| task name                                        |
| stack depth                                      |
| parameter                                        |
| priority                                         |
| handle                                           |
+------------------------+-------------------------+
                         |
                         v
+--------------------------------------------------+
| prvCreateTask()                                  |
|--------------------------------------------------|
| TCB_t 할당                                       |
| stack 할당                                       |
+------------------------+-------------------------+
                         |
                         v
+--------------------------------------------------+
| prvInitialiseNewTask()                           |
|--------------------------------------------------|
| TCB 필드 채우기                                  |
| list item owner 설정                             |
+------------------------+-------------------------+
                         |
                         v
+--------------------------------------------------+
| pxPortInitialiseStack()                          |
|--------------------------------------------------|
| stack에 fake initial context 생성                |
| PC = task function                               |
| R0 = parameter                                   |
| TCB_t.pxTopOfStack = prepared stack top          |
+------------------------+-------------------------+
                         |
                         v
+--------------------------------------------------+
| prvAddNewTaskToReadyList()                       |
|--------------------------------------------------|
| priority에 맞는 ready list에 xStateListItem 추가 |
+------------------------+-------------------------+
                         |
                         v
+--------------------------------------------------+
| 이제 scheduler가 선택할 수 있는 task가 됨        |
+--------------------------------------------------+
```

## 가장 중요한 그림

```text
xTaskCreate()
     |
     v

+------------------+        +----------------------+
|      TCB_t       |        |      Stack           |
|------------------|        |----------------------|
| task name        |        | fake context         |
| priority         |        | PC = task function   |
| pxStack ---------+------> | R0 = parameter       |
| pxTopOfStack ----+---+    +----------------------+
| xStateListItem   |   |
+--------+---------+   |
         |             |
         |             v
         |      saved top of stack
         |
         v

+-----------------------------+
| Ready List for priority N   |
|-----------------------------|
| xStateListItem              |
| pvOwner -> TCB              |
+-----------------------------+
```

## 진짜 핵심 요약

```text
xTaskCreate()
    = task 생성 API

prvCreateTask()
    = TCB와 stack 메모리 준비

prvInitialiseNewTask()
    = TCB 안의 이름, priority, list item 등을 초기화

pxPortInitialiseStack()
    = 새 task가 처음 실행될 수 있도록 stack을 미리 꾸며둠
    = PC에 task 함수 주소
    = R0에 task parameter

prvAddNewTaskToReadyList()
    = task를 priority에 맞는 ready list에 넣음
```

한 문장으로 정리하면:

```text
xTaskCreate()는 사용자가 준 함수를
FreeRTOS scheduler가 실행 가능한 task object로 바꾸는 과정이다.
```

그리고 가장 중요한 포인트는 이것입니다.

```text
새 task는 아직 한 번도 실행된 적이 없지만,
FreeRTOS는 stack에 fake context를 만들어서
마치 복원 가능한 task처럼 만들어 둔다.

그래서 scheduler는 새 task든 기존 task든
항상 같은 방식으로 실행할 수 있다.
```

즉:

```text
새 task 실행도 결국 context restore다.
```
