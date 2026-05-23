# Task delay

```text
vTaskDelay()
    = 현재 task를 일정 시간 동안 scheduler 후보에서 제외하는 함수
```

즉, sleeping은 그냥 멈추는 게 아니라 **scheduler의 list를 바꾸는 일**입니다.

---

## 1. vTaskDelay()를 사용하면 무슨 일이 일어날까?

사용자 코드는 보통 이렇게 생겼습니다.

```c
void vSensorTask(void *pvParameters)
{
    while (1)
    {
        read_sensor();

        vTaskDelay(100);
    }
}
```

뜻은 대략 이렇습니다.

```text
센서를 읽고,
100 tick 동안 나를 실행하지 말아줘.
```

중요한 점은 이것입니다.

```text
vTaskDelay(100)은 CPU를 100 tick 동안 멈추는 게 아니다.

현재 task만 잠시 scheduler 후보에서 빠지는 것이다.
```

---

## 2. delay 전 상태

예를 들어 현재 `Task A`가 실행 중이라고 합시다.

```text
현재 실행 중

+---------+
| Task A  |
+---------+
```

Ready list에는 실행 가능한 task들이 있습니다.

```text
Ready List

Priority 3
+---------+     +---------+
| Task A  | --> | Task B  |
+---------+     +---------+

Priority 2
+---------+
| Task C  |
+---------+
```

이때 `Task A`가 `vTaskDelay(100)`을 호출합니다.

---

## 3. vTaskDelay()의 핵심 동작

흐름은 이렇습니다.

```text
vTaskDelay(100)
    |
    v
현재 tick 확인
    |
    v
wake tick 계산
    |
    v
현재 task를 ready list에서 제거
    |
    v
delayed list에 삽입
    |
    v
다른 task로 yield
```

그림으로 보면:

```text
Before vTaskDelay()

Ready List
+----------------+
| Task A         |
+----------------+

Delayed List
empty


Task A calls vTaskDelay(100)


After vTaskDelay()

Ready List
Task A 없음

Delayed List
+-----------------------------+
| Task A                      |
| wake tick = current + 100   |
+-----------------------------+
```

---

## 4. "잠든다"는 말의 실제 의미

일반적으로는 이렇게 말합니다.

```text
Task A가 잠든다.
```

FreeRTOS 내부적으로는 이렇게 말하는 게 더 정확합니다.

```text
Task A의 xStateListItem을
ready list에서 빼서
delayed list에 넣는다.
```

즉:

```text
Task A
  |
  | vTaskDelay()
  v

Ready List에서 제거
  |
  v
Delayed List에 추가
```

그림으로 보면:

```text
+------------------+
|      TCB A       |
|------------------|
| xStateListItem --+----------------+
+------------------+                |
                                    v

Before
+-------------------------+
| Ready List              |
| Task A state item       |
+-------------------------+


After
+-------------------------+
| Delayed List            |
| Task A state item       |
| wake tick = 150         |
+-------------------------+
```

---

## 5. wake tick이란?

`vTaskDelay(100)`은 "100 tick 뒤에 다시 실행 가능하게 해줘"라는 뜻입니다.

예를 들어 현재 tick이 50이면:

```text
current tick = 50
delay = 100

wake tick = 150
```

즉:

```text
Task A는 tick 150이 되기 전까지 ready 상태가 아니다.
```

Delayed list에는 이 wake tick이 저장됩니다.

```text
Delayed List

+---------------------------+
| Task A                    |
| xItemValue = 150          |
+---------------------------+
```

여기서 `xItemValue`가 wake tick 역할을 합니다.

```text
xStateListItem.xItemValue = wake tick
```

---

## 6. 왜 delayed list를 사용할까?

만약 delayed list가 없다면 tick마다 모든 task를 검사해야 할 수 있습니다.

```text
tick 발생
    |
    v
모든 task 확인
    |
    v
이 task 깨어날 시간 됐나?
저 task 깨어날 시간 됐나?
다른 task는?
```

task가 많아지면 비효율적입니다.

FreeRTOS는 delayed list를 wake tick 순서로 정렬해둡니다.

```text
Delayed List

+------------------+     +------------------+     +------------------+
| Task A           | --> | Task B           | --> | Task C           |
| wake tick = 120  |     | wake tick = 150  |     | wake tick = 200  |
+------------------+     +------------------+     +------------------+
```

그러면 tick handler는 앞쪽부터 보면 됩니다.

```text
현재 tick = 121

Delayed List 첫 번째 확인
Task A wake tick = 120
    -> 깨울 수 있음

다음 Task B wake tick = 150
    -> 아직 아님
    -> 뒤는 볼 필요 적음
```

즉:

```text
delayed list는
"언제 깨어날지" 기준으로 정렬된 잠자는 task 목록이다.
```

---

## 7. vTaskDelay() 후에는 누가 실행될까?

`Task A`가 delay에 들어가면 더 이상 ready task가 아닙니다.

그러면 scheduler는 다른 ready task를 골라야 합니다.

```text
Before

Running:
+---------+
| Task A  |
+---------+

Ready List:
Task A, Task B, Task C


Task A calls vTaskDelay()


After

Delayed List:
Task A

Ready List:
Task B, Task C
```

이제 scheduler는 `Task B`나 `Task C` 중에서 실행할 task를 고릅니다.

```text
Task A sleeps
    |
    v
scheduler selects another ready task
    |
    v
Task B runs
```

그림:

```text
+---------+     vTaskDelay()     +----------------+
| Task A  | -------------------> | Delayed List   |
+---------+                      +----------------+

Ready List
+---------+     +---------+
| Task B  | --> | Task C  |
+---------+     +---------+

Scheduler
    |
    v
Task B 실행
```

---

## 8. task는 스스로 깨어나지 않는다

중요한 점입니다.

```text
Task A가 vTaskDelay()로 잠들면,
Task A가 스스로 깨어나는 게 아니다.
```

왜냐하면 잠든 task는 실행 중이 아니기 때문입니다.

깨우는 역할은 tick handler가 합니다.

FreeRTOS에서는 tick interrupt가 주기적으로 발생합니다.

```text
tick interrupt
tick interrupt
tick interrupt
...
```

각 tick마다 `xTaskIncrementTick()`이 호출되어 시간을 증가시킵니다.

```text
xTaskIncrementTick()
    |
    v
tick count 증가
    |
    v
delayed list 확인
    |
    v
wake tick이 된 task를 ready list로 이동
```

---

## 9. waking up 과정

예를 들어 Task A가 tick 150에 깨어나야 한다고 합시다.

```text
Delayed List

+------------------+
| Task A           |
| wake tick = 150  |
+------------------+
```

시간이 흐릅니다.

```text
tick = 148
tick = 149
tick = 150
```

tick이 150이 되면:

```text
xTaskIncrementTick()
    |
    v
Task A의 wake tick 도달
    |
    v
Task A를 delayed list에서 제거
    |
    v
Task A를 ready list에 넣음
```

그림:

```text
Before tick 150

Delayed List
+------------------+
| Task A           |
| wake tick = 150  |
+------------------+

Ready List
+------------------+
| Task B           |
+------------------+


tick becomes 150


After

Delayed List
empty

Ready List
+------------------+     +------------------+
| Task B           | --> | Task A           |
+------------------+     +------------------+
```

이제 Task A는 다시 scheduler 후보가 됩니다.

---

## 10. 깨어났다고 바로 실행되는 것은 아니다

Task A가 delayed list에서 ready list로 돌아왔다고 해서 무조건 즉시 실행되는 건 아닙니다.

정확히는:

```text
Task A가 다시 실행 가능 상태가 된다.
```

그다음 scheduler가 priority를 보고 결정합니다.

예를 들어:

```text
Task A priority = 3
현재 실행 중 Task B priority = 2
```

그러면 Task A가 더 높기 때문에 context switch가 일어날 수 있습니다.

```text
Task A wakes up
    |
    v
Task A priority > current task priority
    |
    v
scheduler may switch to Task A
```

반대로 현재 실행 중인 task가 더 높은 priority라면 Task A는 ready list에 들어가서 기다립니다.

```text
Task A wakes up
    |
    v
ready list에 들어감
    |
    v
하지만 더 높은 priority task가 실행 중이면 기다림
```

---

## 11. 전체 흐름 한 장으로 보기

```text
Task A running
     |
     | vTaskDelay(100)
     v
+----------------------------+
| wake tick 계산             |
| current tick + 100         |
+-------------+--------------+
              |
              v
+----------------------------+
| Ready List에서 Task A 제거 |
+-------------+--------------+
              |
              v
+----------------------------+
| Delayed List에 Task A 삽입 |
| xItemValue = wake tick     |
+-------------+--------------+
              |
              v
+----------------------------+
| scheduler가 다른 task 선택 |
+-------------+--------------+
              |
              v
       Task B or Task C runs


시간 흐름...


tick interrupt
     |
     v
xTaskIncrementTick()
     |
     v
wake tick이 된 task 확인
     |
     v
Task A를 Ready List로 이동
     |
     v
필요하면 context switch
```

---

## 12. delayed list 안의 xItemValue

앞에서 배웠던 `ListItem_t`를 다시 연결해보면:

```text
TCB A
+--------------------------------+
| xStateListItem                 |
|   xItemValue = wake tick       |
|   pvOwner -> TCB A             |
+--------------------------------+
```

Delayed list는 이 `xItemValue`를 기준으로 정렬됩니다.

```text
Delayed List

+-----------------------------+
| Task A xStateListItem       |
| xItemValue = 120            |
| pvOwner -> TCB A            |
+-----------------------------+
        |
        v
+-----------------------------+
| Task B xStateListItem       |
| xItemValue = 150            |
| pvOwner -> TCB B            |
+-----------------------------+
        |
        v
+-----------------------------+
| Task C xStateListItem       |
| xItemValue = 200            |
| pvOwner -> TCB C            |
+-----------------------------+
```

즉 delayed list에서 `xItemValue`의 의미는 이것입니다.

```text
xItemValue = 이 task가 깨어날 tick
```

---

## 13. 두 개의 delayed list가 필요한 이유

FreeRTOS에는 delayed list가 두 개 있습니다.

```text
xDelayedTaskList1
xDelayedTaskList2
```

그리고 실제로는 포인터로 이렇게 사용합니다.

```text
pxDelayedTaskList
    = 현재 사용하는 delayed list

pxOverflowDelayedTaskList
    = tick overflow 이후를 위한 delayed list
```

처음 보면 이상합니다.

```text
왜 delayed list가 하나면 안 되지?
```

이유는 tick counter가 언젠가 overflow 되기 때문입니다.

---

## 14. tick count overflow란?

tick count는 보통 정수입니다.

예를 들어 아주 작은 8-bit tick counter라고 가정해봅시다.

```text
0, 1, 2, 3, ... 254, 255, 0, 1, 2, ...
```

255 다음에는 256이 아니라 다시 0으로 돌아갑니다.

이걸 overflow 또는 wrap-around라고 합니다.

실제 FreeRTOS에서는 tick type 크기가 설정에 따라 다르지만, 원리는 같습니다.

```text
tick count는 유한한 숫자라서 언젠가 다시 0으로 돌아간다.
```

---

## 15. overflow가 왜 문제일까?

현재 tick이 250이라고 해봅시다.

```text
current tick = 250
```

Task A가 3 tick 뒤에 깨어나야 합니다.

```text
wake tick = 253
```

이건 문제 없습니다.

```text
250 -> 251 -> 252 -> 253
```

그런데 Task B가 10 tick 뒤에 깨어나야 한다면?

```text
current tick = 250
delay = 10
wake tick = 260
```

하지만 8-bit tick에서는 260이 없습니다.

255 다음에 0으로 돌아가므로:

```text
250 -> 251 -> 252 -> 253 -> 254 -> 255 -> 0 -> 1 -> 2 -> 3 -> 4
```

결국 wake tick은 4가 됩니다.

```text
wake tick = 4
```

숫자만 보면 4는 250보다 작습니다.

```text
wake tick 4 < current tick 250
```

하지만 실제 의미는:

```text
overflow 후 tick 4에 깨어나라
```

입니다.

이걸 하나의 list에서 단순 정렬하면 헷갈릴 수 있습니다.

---

## 16. 그래서 delayed list를 두 개로 나눈다

FreeRTOS는 이런 식으로 나눕니다.

```text
현재 tick count가 overflow되기 전에 깨어날 task
    -> current delayed list

tick count가 overflow된 뒤에 깨어날 task
    -> overflow delayed list
```

예시:

```text
current tick = 250
```

Task A:

```text
delay = 3
wake tick = 253

overflow 전이므로 current delayed list
```

Task B:

```text
delay = 10
wake tick = 4

overflow 후이므로 overflow delayed list
```

그림:

```text
current tick = 250


Current Delayed List
+------------------+
| Task A           |
| wake tick = 253  |
+------------------+


Overflow Delayed List
+------------------+
| Task B           |
| wake tick = 4    |
+------------------+
```

---

## 17. tick overflow가 발생하면 list를 swap한다

시간이 흘러 tick이 overflow됩니다.

```text
253
254
255
0   <- overflow 발생
```

이 순간 FreeRTOS는 delayed list 두 개를 바꿉니다.

```text
pxDelayedTaskList <-> pxOverflowDelayedTaskList
```

그림으로 보면:

```text
Before overflow

pxDelayedTaskList
    |
    v
Current Delayed List
+------------------+
| Task A wake 253  |
+------------------+

pxOverflowDelayedTaskList
    |
    v
Overflow Delayed List
+------------------+
| Task B wake 4    |
+------------------+


After overflow

pxDelayedTaskList
    |
    v
Overflow Delayed List
+------------------+
| Task B wake 4    |
+------------------+

pxOverflowDelayedTaskList
    |
    v
Old Current Delayed List
empty
```

이제 tick count는 0부터 다시 증가하므로, wake tick 4인 Task B를 자연스럽게 처리할 수 있습니다.

```text
tick = 0
tick = 1
tick = 2
tick = 3
tick = 4
    |
    v
Task B wake
```

---

## 18. delayed list 두 개를 쓰는 이유 한 줄 요약

```text
tick count는 언젠가 0으로 돌아간다.

그래서 overflow 전까지 깨어날 task와
overflow 후에 깨어날 task를
서로 다른 delayed list에 넣는다.
```

---

## 19. vTaskDelay() 전체 그림

```text
Task A running
     |
     | calls vTaskDelay(100)
     v

+--------------------------------+
| current tick 읽기              |
+--------------------------------+
     |
     v
+--------------------------------+
| wake tick 계산                 |
| wake tick = current + 100      |
+--------------------------------+
     |
     v
+--------------------------------+
| wake tick이 overflow 전인가?   |
+-------------+------------------+
              |
       +------+------+
       |             |
      Yes            No
       |             |
       v             v
+-------------+   +-----------------------+
| current     |   | overflow delayed list |
| delayed list|   | 에 넣음               |
| 에 넣음     |   +-----------------------+
+-------------+
       |
       v

Task A는 ready list에서 빠짐
       |
       v
다른 task 실행
```

---

## 20. xTaskIncrementTick() 전체 그림

```text
tick interrupt
     |
     v
+------------------------+
| xTaskIncrementTick()   |
+------------------------+
     |
     v
+------------------------+
| tick count 증가        |
+------------------------+
     |
     v
+------------------------+
| tick overflow 발생?    |
+----------+-------------+
           |
     +-----+-----+
     |           |
    Yes          No
     |           |
     v           v
delayed list     그대로 진행
swap
     |
     v
+-------------------------------+
| delayed list의 앞쪽 task 확인 |
+-------------------------------+
     |
     v
+-------------------------------+
| wake tick <= current tick ?   |
+----------+--------------------+
           |
     +-----+-----+
     |           |
    Yes          No
     |           |
     v           v
ready list로 이동   아직 잠들어 있음
     |
     v
필요하면 context switch
```

---

## 21. 예제로 이해하기

현재 tick이 100이라고 합시다.

```text
current tick = 100
```

Task A가 실행 중입니다.

```text
Task A calls vTaskDelay(50)
```

그러면:

```text
wake tick = 100 + 50 = 150
```

Task A는 ready list에서 빠지고 delayed list로 들어갑니다.

```text
Before

Ready List
+---------+     +---------+
| Task A  | --> | Task B  |
+---------+     +---------+

Delayed List
empty


After

Ready List
+---------+
| Task B  |
+---------+

Delayed List
+------------------+
| Task A           |
| wake tick = 150  |
+------------------+
```

tick이 증가합니다.

```text
tick = 101
tick = 102
...
tick = 149
```

Task A는 아직 ready가 아닙니다.

```text
Delayed List
+------------------+
| Task A           |
| wake tick = 150  |
+------------------+
```

tick이 150이 됩니다.

```text
tick = 150
```

이제 Task A는 ready list로 돌아갑니다.

```text
Ready List
+---------+     +---------+
| Task B  | --> | Task A  |
+---------+     +---------+

Delayed List
empty
```

이제 scheduler가 priority에 따라 Task A를 다시 실행할 수 있습니다.

---

## 22. vTaskDelay()는 "정확히 N tick 동안 실행 중지"가 아니다

중요한 현실적인 포인트입니다.

`vTaskDelay(100)`은 보통 이렇게 이해하면 됩니다.

```text
최소 100 tick 동안 이 task를 ready 상태에서 빼라.
```

100 tick 뒤에 ready list로 돌아오지만, 바로 CPU를 얻는지는 priority와 scheduler 상황에 따라 달라집니다.

```text
wake tick 도달
    |
    v
ready list로 이동
    |
    v
scheduler가 선택하면 실행
```

즉:

```text
delay 끝 = 실행 가능해짐
delay 끝 ≠ 반드시 즉시 실행됨
```

---

## 23. vTaskDelay()와 busy wait의 차이

나쁜 방식:

```c
for (volatile int i = 0; i < 1000000; i++)
{
}
```

이건 CPU를 계속 붙잡고 있습니다.

```text
Task A
    |
    v
CPU 계속 사용
    |
    v
다른 task가 실행되기 어려움
```

`vTaskDelay()`는 다릅니다.

```c
vTaskDelay(100);
```

이건 CPU를 양보합니다.

```text
Task A
    |
    v
delayed list로 이동
    |
    v
CPU를 다른 task에게 양보
```

그림:

```text
Busy wait

Task A running
+----------------------------------+
| CPU를 계속 사용하며 기다림        |
+----------------------------------+


vTaskDelay()

Task A
+----------------------------------+
| ready list에서 빠짐               |
| delayed list로 이동               |
+----------------------------------+

CPU
+----------------------------------+
| Task B 실행 가능                  |
+----------------------------------+
```

---

## 24. "sleeping is scheduling"의 의미

본문의 문장:

```text
sleeping is scheduling
```

이 말은 이런 뜻입니다.

```text
task가 잔다
    =
그 task의 상태가 바뀐다
    =
scheduler가 볼 수 있는 ready set에서 빠진다
    =
다른 task가 실행될 수 있다
```

즉 sleep은 단순한 시간 대기가 아니라 scheduler 자료구조를 바꾸는 일입니다.

```text
Ready List
    |
    | vTaskDelay()
    v
Delayed List
```

그리고 시간이 지나면 다시 돌아옵니다.

```text
Delayed List
    |
    | tick reaches wake time
    v
Ready List
```

---

## 25. 가장 중요한 그림

```text
                 vTaskDelay(100)
                       |
                       v

+----------------+       remove        +----------------+
| Ready List     | ------------------> | Delayed List   |
| Task A         |                     | Task A         |
+----------------+                     | wake tick=150  |
                                       +----------------+

                       time passes
                           |
                           v

                    xTaskIncrementTick()
                           |
                           v

+----------------+       wake         +----------------+
| Delayed List   | -----------------> | Ready List     |
| Task A         |                    | Task A         |
| wake tick=150  |                    +----------------+
+----------------+
```

---

## 26. 최종 요약

```text
vTaskDelay()
    = 현재 task를 일정 tick 동안 실행 후보에서 빼는 함수

ready list
    = 지금 실행 가능한 task들의 목록

delayed list
    = 아직 실행하면 안 되는 task들의 목록

xStateListItem.xItemValue
    = delayed list에서는 wake tick

xTaskIncrementTick()
    = tick이 증가할 때 delayed list를 확인해서
      깨어날 시간이 된 task를 ready list로 옮김

두 개의 delayed list
    = tick count overflow를 처리하기 위해 사용

delay가 끝난 task
    = 바로 실행되는 것이 아니라 ready 상태가 됨
```

한 문장으로 정리하면:

```text
vTaskDelay()는 현재 task를 ready list에서 빼서
wake tick 기준으로 delayed list에 넣고,
나중에 tick handler가 시간이 된 task를 다시 ready list로 돌려보내는 과정이다.
```
