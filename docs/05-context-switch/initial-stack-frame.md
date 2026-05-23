# Initial stack frame

이번 주제는 아직 한 번도 실행된 적 없는 task를 어떻게 context restore로
시작할 수 있을까 하는 질문입니다.

핵심은 이것입니다.

```text
새로 만든 task는 이전 CPU 상태가 없다.

그런데 FreeRTOS는 새 task도 기존 task처럼
"stack에서 context를 복원하는 방식"으로 시작하고 싶다.

그래서 task 생성 시점에 stack 위에
가짜 초기 context를 미리 만들어 둔다.
```

관련 source file은 다음입니다.

- `FreeRTOS-Kernel/portable/GCC/ARM_CM4F/port.c`

## 문제 상황: 새 task는 멈춘 적이 없다

기존 task는 실행되다가 멈춘 적이 있습니다.

```text
Task A 실행 중
    |
    v
context switch 발생
    |
    v
CPU register들이 Task A stack에 저장됨
```

그래서 나중에 다시 실행할 때는 stack에서 복원하면 됩니다.

```text
Task A stack
    |
    v
CPU register 복원
    |
    v
Task A가 멈췄던 위치부터 다시 실행
```

그런데 새 task는 다릅니다.

```text
새 Task B

아직 실행된 적 없음
멈춘 적 없음
저장된 register 없음
```

그럼 문제가 생깁니다.

```text
FreeRTOS scheduler:
    "Task B를 실행하려면 stack에서 context를 복원해야 하는데..."

Task B:
    "나는 아직 실행된 적이 없어서 저장된 context가 없는데?"
```

## FreeRTOS의 해결책: 가짜 context 만들기

FreeRTOS는 task를 만들 때 stack을 그냥 빈 공간으로 두지 않습니다.

`pxPortInitialiseStack()`이 새 task의 stack을 미리 꾸며둡니다.

```text
pxPortInitialiseStack()
    =
    새 task stack에
    "마치 예전에 실행되다가 interrupt된 것처럼 보이는"
    가짜 초기 stack frame을 만들어 둔다.
```

즉 새 task를 이런 상태로 만들어 둡니다.

```text
아직 실행된 적은 없지만,
마치 실행되다가 멈춘 적 있는 task처럼 restore 가능하다.
```

## task stack을 준비하는 모습

처음 stack은 그냥 할당된 메모리입니다.

```text
Allocated Stack

+-------------------------+
|                         |
|                         |
|                         |
|                         |
|                         |
+-------------------------+
```

`pxPortInitialiseStack()`이 여기에 초기 context를 만들어 둡니다.

```text
Prepared Stack

+-------------------------+
|                         |
|                         |
| fake initial context    |
|-------------------------|
| initial xPSR            |
| initial PC              |
| initial LR              |
| task parameter          |
| software-saved slots    |
+-------------------------+
          ^
          |
    pxTopOfStack
```

여기서 핵심은 두 개입니다.

```text
initial PC
    = task 함수 주소

task parameter
    = task 함수에 전달할 인자
```

## PC가 task 함수 주소를 가리킨다

CPU에서 `PC`는 Program Counter입니다.

```text
PC = 다음에 실행할 명령어 주소
```

FreeRTOS는 새 task stack에 이렇게 넣어둡니다.

```text
initial PC = task entry function
```

예를 들어 사용자가 이런 task를 만들었다고 합시다.

```c
void vSensorTask(void *pvParameters)
{
    while (1)
    {
        read_sensor();
    }
}
```

그러면 stack에는 대략 이런 정보가 들어갑니다.

```text
New Task Stack

+-----------------------------+
| fake context                |
|-----------------------------|
| PC = vSensorTask            |
| R0 = pvParameters           |
| other initial register data |
+-----------------------------+
```

나중에 CPU가 이 stack을 복원하면:

```text
PC = vSensorTask
```

가 됩니다.

그러면 CPU는 자연스럽게 `vSensorTask()`의 첫 줄부터 실행합니다.

## task parameter는 함수 인자 위치에 넣는다

C 함수로 보면 task는 이렇게 시작해야 합니다.

```c
vSensorTask(pvParameters);
```

Cortex-M의 함수 호출 규칙에서는 첫 번째 인자가 보통 `R0`에 들어갑니다.

그래서 FreeRTOS는 초기 stack frame에 이렇게 준비합니다.

```text
R0 = pvParameters
PC = vSensorTask
```

그림으로 보면:

```text
Prepared Stack

+-----------------------------+
| initial PC = vSensorTask    |
+-----------------------------+
| initial R0 = pvParameters   |
+-----------------------------+
| other register slots        |
+-----------------------------+
```

복원 후 CPU 입장에서는 이렇게 보입니다.

```text
R0에 parameter가 있음
PC가 task 함수 주소임
    |
    v
vSensorTask(pvParameters) 시작
```

## return into task처럼 보인다

Cortex-M에서는 exception에서 빠져나올 때 stack에 있던 값을 이용해 CPU 상태를
복원합니다.

FreeRTOS는 이 동작을 이용합니다.

```text
prepared stack 복원
    |
    v
exception return
    |
    v
PC가 task 함수 주소로 복원됨
    |
    v
task 함수 시작
```

그래서 새 task는 실제로는 처음 실행되는 것이지만, CPU 입장에서는 이렇게
보입니다.

```text
"어딘가에서 return했더니 task 함수로 돌아왔다."
```

그림:

```text
+---------------------------+
| PendSV restore path       |
+-------------+-------------+
              |
              v
+---------------------------+
| pxCurrentTCB->pxTopOfStack|
+-------------+-------------+
              |
              v
+---------------------------+
| prepared stack frame      |
| PC = task function        |
| R0 = parameter            |
+-------------+-------------+
              |
              v
+---------------------------+
| exception return          |
+-------------+-------------+
              |
              v
+---------------------------+
| task function starts      |
+---------------------------+
```

## 왜 이런 방식을 쓸까?

이 방식의 장점은 매우 큽니다.

FreeRTOS는 새 task와 기존 task를 다르게 처리하지 않아도 됩니다.

다른 방식이라면 scheduler가 이렇게 해야 할 수도 있습니다.

```text
if 새 task라면:
    task 함수를 직접 호출한다
else:
    stack에서 context를 복원한다
```

하지만 FreeRTOS는 이렇게 합니다.

```text
모든 task는 stack에서 context를 복원한다.
```

기존 task:

```text
실제로 저장된 context 복원
    |
    v
멈췄던 지점부터 재개
```

새 task:

```text
미리 만든 fake context 복원
    |
    v
task 함수 첫 줄부터 시작
```

둘 다 같은 restore path를 씁니다.

```text
기존 task든 새 task든

pxCurrentTCB
    |
    v
TCB_t.pxTopOfStack
    |
    v
stack에서 context restore
```

## 기존 task와 새 task 비교

기존 task는 이전에 실행된 적이 있습니다.

```text
Task A Stack

+-----------------------------+
| real saved context          |
|-----------------------------|
| PC = 멈췄던 위치             |
| registers = 당시 값          |
+-----------------------------+
```

복원하면:

```text
Task A가 멈췄던 위치부터 다시 실행
```

새 task는 실행된 적이 없습니다.

```text
Task B Stack

+-----------------------------+
| fake initial context        |
|-----------------------------|
| PC = task 함수 주소          |
| R0 = task parameter         |
+-----------------------------+
```

복원하면:

```text
Task B의 task 함수 첫 줄부터 실행
```

## 전체 흐름: xTaskCreate()부터 첫 실행까지

```text
xTaskCreate()
    |
    v
TCB_t 생성
    |
    v
stack 할당
    |
    v
pxPortInitialiseStack()
    |
    v
stack에 fake initial frame 생성
    |
    v
TCB_t.pxTopOfStack에 저장
    |
    v
ready list에 task 추가
    |
    v
scheduler가 이 task 선택
    |
    v
PendSV가 stack 복원
    |
    v
task 함수 시작
```

그림으로 보면:

```text
+-----------------------------+
| xTaskCreate()               |
+-------------+---------------+
              |
              v
+-----------------------------+
| TCB_t 생성                  |
+-------------+---------------+
              |
              v
+-----------------------------+
| Stack 할당                  |
+-------------+---------------+
              |
              v
+-----------------------------+
| pxPortInitialiseStack()     |
| fake initial context 생성   |
+-------------+---------------+
              |
              v
+-----------------------------+
| TCB_t.pxTopOfStack 저장     |
+-------------+---------------+
              |
              v
+-----------------------------+
| Ready List에 추가           |
+-------------+---------------+
              |
              v
+-----------------------------+
| Scheduler가 선택            |
+-------------+---------------+
              |
              v
+-----------------------------+
| PendSV restore              |
+-------------+---------------+
              |
              v
+-----------------------------+
| task function 시작          |
+-----------------------------+
```

## TCB와 stack의 연결

새 task가 만들어진 후에는 이런 구조가 됩니다.

```text
+--------------------------------+
|             TCB_t              |
|--------------------------------|
| pxTopOfStack ------------------+----+
| pxStack                        |    |
| pcTaskName = "SensorTask"      |    |
| uxPriority = 3                 |    |
+--------------------------------+    |
                                      v
                         +-------------------------+
                         | Task Stack              |
                         |-------------------------|
                         | fake initial context    |
                         | PC = vSensorTask        |
                         | R0 = pvParameters       |
                         +-------------------------+
```

나중에 scheduler가 이 TCB를 선택합니다.

```text
pxCurrentTCB
     |
     v
+--------------------------------+
|             TCB_t              |
| pxTopOfStack ------------------+----+
+--------------------------------+    |
                                      v
                         +-------------------------+
                         | prepared stack          |
                         +-------------------------+
```

PendSV는 이 stack을 복원합니다.

```text
prepared stack
    |
    v
CPU registers
    |
    v
PC = task function
    |
    v
task starts
```

## 정확한 stack 순서를 처음부터 외울 필요는 없다

ARM Cortex-M에서는 실제로 어떤 register가 어떤 순서로 stack에 쌓이는지
중요합니다.

하지만 첫 번째로 공부할 때는 모든 세부 순서를 외우려고 하지 않아도 됩니다.

처음에는 이 큰 그림이 중요합니다.

```text
새 task의 stack에는
처음 context restore가 성공하도록
초기 CPU 상태가 미리 만들어져 있다.
```

즉 핵심은 이것입니다.

```text
PC를 task 함수로,
parameter를 함수 호출 규칙에 맞는 위치로,
나머지 register 자리도 restore 가능한 형태로 준비한다.
```

## 왜 pretending the task was interrupted인가?

일반적으로 context restore는 이런 task에 대해 동작합니다.

```text
실행 중이던 task
    |
    v
interrupt 또는 PendSV 발생
    |
    v
context가 stack에 저장됨
    |
    v
나중에 stack에서 restore
```

새 task는 사실 이런 과정을 겪은 적이 없습니다.

하지만 FreeRTOS가 stack을 이렇게 만들어 둡니다.

```text
마치 interrupt 때문에 context가 저장된 것처럼 생긴 stack
```

그래서 CPU는 이 task가 처음 실행되는지 구분하지 않습니다.

```text
CPU:
    "stack에 context가 있네?
     복원하면 되겠군."
```

복원 결과:

```text
PC = task 함수 주소
    |
    v
task 함수 시작
```

## 비유: 영화 재생 위치 조작하기

영화 플레이어가 있다고 해봅시다.

기존 영화는 중간에 멈췄기 때문에 이어보기 위치가 있습니다.

```text
기존 task
    = 이어보기 위치가 저장된 영화
```

새 영화는 본 적이 없지만, 시스템이 이어보기 위치를 처음 장면으로 만들어
둡니다.

```text
새 task
    = 이어보기 위치를 0초로 미리 만들어 둔 영화
```

그러면 플레이어는 둘 다 똑같이 처리합니다.

```text
저장된 위치에서 재생한다
```

FreeRTOS도 같습니다.

```text
기존 task
    = 실제 저장된 context에서 restore

새 task
    = fake initial context에서 restore
```

## 가장 중요한 그림

```text
새 task 생성

+------------------+
| task function    |
| vSensorTask      |
+------------------+
          |
          v
+-------------------------------+
| pxPortInitialiseStack()       |
|-------------------------------|
| stack에 fake context 생성     |
| PC = vSensorTask              |
| R0 = pvParameters             |
+---------------+---------------+
                |
                v
+-------------------------------+
| TCB_t                         |
| pxTopOfStack -> prepared stack|
+---------------+---------------+
                |
                v
+-------------------------------+
| scheduler가 task 선택         |
+---------------+---------------+
                |
                v
+-------------------------------+
| PendSV restore                |
+---------------+---------------+
                |
                v
+-------------------------------+
| vSensorTask(pvParameters) 시작|
+-------------------------------+
```

## 최종 요약

```text
새 task의 문제
    = 이전에 실행된 적이 없어서 저장된 CPU context가 없음

FreeRTOS의 해결
    = pxPortInitialiseStack()이 stack에 fake initial context를 만들어 둠

initial PC
    = task 함수 주소

task parameter
    = 함수 호출 규칙에 맞는 위치에 배치됨
    = Cortex-M에서는 첫 번째 인자 위치에 해당

pxTopOfStack
    = 준비된 fake context의 위치를 가리킴

첫 실행
    = 특별히 task 함수를 직접 호출하는 것이 아니라
      일반 context restore 경로를 통해 시작됨

장점
    = 새 task와 기존 task를 같은 방식으로 다룰 수 있음
```

한 문장으로 정리하면:

```text
pxPortInitialiseStack()은 새 task의 stack을
"이미 실행되다가 멈춘 task처럼" 꾸며놓는다.

그래서 scheduler와 PendSV는 새 task도 기존 task처럼
stack에서 context를 복원하기만 하면 되고,
복원 결과 CPU는 task 함수 첫 줄로 들어간다.
```
